#!/usr/bin/env python3
"""Verify the read-only Fuse model using unmodified NVIDIA driver functions."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import socket
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('qemu', type=Path)
parser.add_argument('--optee', type=Path, required=True)
parser.add_argument('--optee-sha256', default='96bcd44d8a4ceee39fa8a4ffd97b5bc0e193c6b3d5fc6cdc2208b806aeb9beb9')
parser.add_argument('--firmware-dir', type=Path, default=Path('work/t234-firmware'))
parser.add_argument('--image-dir', type=Path, default=Path('work/fuse'))
parser.add_argument('--output-dir', type=Path, default=Path('work/t234-fuse-results'))
args = parser.parse_args()
args.output_dir.mkdir(parents=True, exist_ok=True)
if hashlib.sha256(args.optee.read_bytes()).hexdigest() != args.optee_sha256:
    raise SystemExit('OP-TEE baseline hash mismatch')
images = {name: args.image_dir / f'device-{name}.bin' for name in ('a', 'b')}
profiles = {name: json.loads(Path(f'configs/fuse/test-device-{name}.json').read_text()) for name in images}
hashes = {name: hashlib.sha256(p.read_bytes()).hexdigest() for name, p in images.items()}
report = {'scope': 'Fuse register model and binary driver calls, not complete OP-TEE initialization',
          'input_sha256': args.optee_sha256, 'image_sha256': hashes, 'tests': {}}


def command(image, firmware, payload=False, extra=()):
    if ',' in str(image):
        raise SystemExit('Image path must not contain a comma')
    cmd = [str(args.qemu.resolve()), '-machine', 'jetson-t234-dev,fuse-image=' + str(image),
           '-accel', 'tcg', '-cpu', 'max', '-m', '128M', '-display', 'none',
           '-monitor', 'none', '-serial', 'stdio',
           '-semihosting-config', 'enable=on,target=native',
           '-bios', str(args.firmware_dir / (firmware + '.bin'))]
    if payload:
        cmd += ['-kernel', str(args.optee)]
    return cmd + list(extra)


def run(name, cmd, expected_code=0):
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
    (args.output_dir / (name + '.stdout.log')).write_text(p.stdout)
    (args.output_dir / (name + '.stderr.log')).write_text(p.stderr)
    report['tests'][name] = {'returncode': p.returncode, 'command': cmd}
    if (expected_code == 0 and p.returncode != 0) or (expected_code != 0 and p.returncode == 0):
        raise AssertionError(f'{name}: unexpected exit {p.returncode}\n{p.stdout}\n{p.stderr}')
    return p.stdout, p.stderr


def identities(text):
    words = [f'{int(word, 16):08x}' for word in re.search(r'FUSE: ECID128=([^\n]+)', text)[1].split()]
    return {'ecid128_words': words,
            'ecid64': re.search(r'FUSE: ECID64=([0-9A-Fa-f]+)', text)[1].lower(),
            'sn': re.search(r'FUSE: SN=([0-9A-Fa-f]+)', text)[1].lower()}


try:
    for name, image in images.items():
        for attempt in range(2):
            label = f'identity_{name}_{attempt}'
            out, _ = run(label, command(image, 'fuse-probe', payload=True))
            assert 'BOOT: FUSE probe PASS' in out
            actual = identities(out)
            assert actual == profiles[name]['expected'], (actual, profiles[name]['expected'])
            report['tests'][label]['identity'] = actual
            print(name, actual)
    assert profiles['a']['expected'] != profiles['b']['expected']
    for name, firmware, marker in [
        ('write_rejected', 'fuse-write', 'BOOT: FUSE write rejected, vendor=0000000000000002'),
        ('unsupported_read', 'fuse-bad-read', 'BOOT: FUSE unsupported read rejected'),
        ('secure_only', 'fuse-isolation', 'BOOT: NS isolation PASS')]:
        out, _ = run(name, command(images['a'], firmware))
        assert marker in out, name
        if name == 'secure_only':
            assert '0000000003810200' in out
    # Input validation is part of the partial model's contract.
    short = args.output_dir / 'short.bin'
    short.write_bytes(b'\0' * 4)
    _, err = run('reject_size', command(short, 'selftest'), expected_code=1)
    assert 'exactly 0x600 bytes' in err
    unknown = args.output_dir / 'unknown.bin'
    content = bytearray(0x600)
    content[0] = 1
    unknown.write_bytes(content)
    _, err = run('reject_unsupported_data', command(unknown, 'selftest'), expected_code=1)
    assert 'nonzero unsupported offset' in err

    # Pause in EL3 after the probe, reset through QMP, and compare both runs.
    qmp_path = (args.output_dir / 'qmp.sock').resolve()
    if qmp_path.exists():
        qmp_path.unlink()
    log_path = args.output_dir / 'reset.stdout.log'
    with log_path.open('w') as stdout, (args.output_dir / 'reset.stderr.log').open('w') as stderr:
        process = subprocess.Popen(command(images['a'], 'fuse-reset', payload=True,
            extra=['-qmp', 'unix:' + str(qmp_path) + ',server=on,wait=off']), stdout=stdout, stderr=stderr)
        connection = None
        try:
            deadline = time.monotonic() + 10
            while not qmp_path.exists():
                if process.poll() is not None or time.monotonic() > deadline:
                    raise AssertionError('QMP endpoint did not start')
                time.sleep(0.02)
            connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            connection.settimeout(5)
            connection.connect(str(qmp_path))
            stream = connection.makefile('rwb', buffering=0)
            assert 'QMP' in json.loads(stream.readline())

            def qmp(execute, arguments=None):
                packet = {'execute': execute, 'id': execute}
                if arguments is not None:
                    packet['arguments'] = arguments
                stream.write(json.dumps(packet).encode() + b'\n')
                while True:
                    response = json.loads(stream.readline())
                    if response.get('id') == execute:
                        return response

            def wait_count(count):
                limit = time.monotonic() + 10
                while log_path.read_text().count('BOOT: FUSE probe PASS') < count:
                    if process.poll() is not None or time.monotonic() > limit:
                        raise AssertionError('Fuse probe failed to reach the EL3 wait loop')
                    time.sleep(0.02)

            assert 'return' in qmp('qmp_capabilities')
            wait_count(1)
            response = qmp('qom-set', {'path': '/machine', 'property': 'fuse-image',
                                       'value': str(images['b'])})
            assert 'immutable' in response['error']['desc']
            assert 'return' in qmp('system_reset')
            wait_count(2)
            assert 'return' in qmp('quit')
            process.wait(timeout=5)
            assert process.returncode == 0
        finally:
            if connection:
                connection.close()
            if process.poll() is None:
                process.kill()
                process.wait()
            if qmp_path.exists():
                qmp_path.unlink()
    reset_output = log_path.read_text()
    sections = reset_output.split('BOOT: EL3 entry')[1:]
    assert len(sections) == 2
    assert all(identities(section) == profiles['a']['expected'] for section in sections)
    report['tests']['qmp_reset_and_immutable_property'] = {'passed': True, 'runs': 2}
    assert hashes == {name: hashlib.sha256(p.read_bytes()).hexdigest() for name, p in images.items()}
    report['passed'] = True
    print('PASS: NVIDIA binary identity conversion, restart/reset stability, read-only and secure-only policy')
finally:
    (args.output_dir / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
