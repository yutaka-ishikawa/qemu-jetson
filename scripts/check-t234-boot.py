#!/usr/bin/env python3
"""Test the development harness and record an optional OP-TEE diagnostic run."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('qemu', type=Path)
parser.add_argument('--firmware-dir', type=Path, default=Path('work/t234-firmware'))
parser.add_argument('--optee', type=Path)
parser.add_argument('--optee-sha256',
                    default='96bcd44d8a4ceee39fa8a4ffd97b5bc0e193c6b3d5fc6cdc2208b806aeb9beb9',
                    help='expected input hash; override explicitly for a separately recorded rebuild')
parser.add_argument('--output-dir', type=Path, default=Path('work/t234-results'))
args = parser.parse_args()
args.output_dir.mkdir(parents=True, exist_ok=True)
base = [str(args.qemu.resolve()), '-machine', 'jetson-t234-dev', '-accel', 'tcg',
        '-cpu', 'max', '-smp', '1', '-m', '128M', '-display', 'none',
        '-monitor', 'none', '-serial', 'stdio',
        '-semihosting-config', 'enable=on,target=native']


def run(name, options, timeout=10, stop_on_abort=False):
    command = base + options
    stdout_path = args.output_dir / (name + '.stdout.log')
    stderr_path = args.output_dir / (name + '.stderr.log')
    reason = 'process_exit'
    with stdout_path.open('w+b') as stdout, stderr_path.open('w+b') as stderr:
        process = subprocess.Popen(command, stdout=stdout, stderr=stderr)
        deadline = time.monotonic() + timeout
        while process.poll() is None:
            if stop_on_abort:
                # Read through a separate descriptor: never move the writer's offset.
                with stdout_path.open('rb') as reader:
                    sample = reader.read(256 * 1024)
                if b'Core data-abort at address' in sample:
                    reason = 'observed_data_abort'
                    process.terminate()
                    break
            if time.monotonic() >= deadline:
                reason = 'timeout'
                process.kill()
                break
            time.sleep(0.02)
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
    out = stdout_path.read_text(errors='replace')
    err = stderr_path.read_text(errors='replace')
    result = {'command': command, 'returncode': process.returncode,
              'timed_out': reason == 'timeout', 'stop_reason': reason}
    print('\n'.join(out.splitlines()[:50]))
    return result, out, err


report = {'scope': 'development harness; no Linux or functional TPM test', 'tests': {}}
for name, marker in [('selftest', 'BOOT: SELFTEST PASS'),
                     ('isolation', 'BOOT: NS isolation PASS')]:
    result, out, err = run(name, ['-bios', str(args.firmware_dir / (name + '.bin'))])
    result['passed'] = (not result['timed_out'] and result['returncode'] == 0
                        and marker in out)
    if name == 'selftest':
        result['passed'] &= 'BOOT: Secure EL1 entry' in out and 'TCU: ABC' in out
    report['tests'][name] = result
    if not result['passed']:
        (args.output_dir / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        raise SystemExit(f'{name} failed: {result}\n{err}')

# Reject configurations that disagree with the current fixed memory/CPU layout.
for name, options in [('reject_ram', ['-m', '256M']),
                      ('reject_smp', ['-smp', '2'])]:
    result, out, err = run(name, options)
    result['passed'] = not result['timed_out'] and result['returncode'] != 0
    report['tests'][name] = result
    if not result['passed']:
        raise SystemExit(f'{name} unexpectedly accepted an unsupported configuration')

if args.optee:
    digest = hashlib.sha256(args.optee.read_bytes()).hexdigest()
    expected = args.optee_sha256
    if digest != expected:
        raise SystemExit('OP-TEE input does not match the recorded unmodified baseline')
    result, out, err = run('optee', [
        '-bios', str(args.firmware_dir / 'boot.bin'), '-kernel', str(args.optee),
        '-dtb', str(args.firmware_dir / 'optee.dtb'),
        '-d', 'guest_errors,unimp', '-D', str(args.output_dir / 'optee.qemu.log')],
        10, stop_on_abort=True)
    result['input_sha256'] = digest
    result['first_log_observed'] = 'OP-TEE version:' in out
    result['data_abort_observed'] = 'Core data-abort at address' in out
    result['panic_observed'] = 'Panic' in out
    result['monitor_stop_observed'] = 'BOOT: STOP' in out
    # A log or a monitor trap does not establish complete initialization.
    result['diagnostic_observed'] = result['first_log_observed'] and (
        result['data_abort_observed'] or result['monitor_stop_observed']
        or result['panic_observed'])
    result['initialization_verified'] = False
    result['tpm_verified'] = False
    report['tests']['optee_diagnostic'] = result

(args.output_dir / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
if args.optee and not report['tests']['optee_diagnostic']['diagnostic_observed']:
    raise SystemExit('Harness tests passed, but the OP-TEE diagnostic milestone was not reached')
print('PASS: harness tests and requested diagnostic observation; OP-TEE initialization and TPM remain unverified')
