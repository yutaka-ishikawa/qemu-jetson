#!/usr/bin/env python3
"""Check the stock AArch64 emulator, not Jetson or OP-TEE functionality."""
import argparse
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('qemu', type=Path)
parser.add_argument('--data-dir', type=Path)
args = parser.parse_args()
installed_data=args.qemu.resolve().parent.parent/'share/qemu'
data_dir=args.data_dir or (installed_data if installed_data.is_dir() else Path(__file__).resolve().parents[1]/'qemu/pc-bios')
commands = [
    {'execute': 'qmp_capabilities', 'id': 'capabilities'},
    {'execute': 'query-status', 'id': 'status'},
    {'execute': 'query-cpu-model-expansion', 'id': 'cpu',
     'arguments': {'type': 'full', 'model': {'name': 'max'}}},
    {'execute': 'quit', 'id': 'quit'},
]
result = subprocess.run(
    [str(args.qemu.resolve()), '-L', str(data_dir.resolve()), '-machine', 'virt,secure=on', '-accel', 'tcg',
     '-cpu', 'max', '-smp', '1', '-m', '128M', '-display', 'none',
     '-serial', 'none', '-monitor', 'none', '-S', '-qmp', 'stdio'],
    input=''.join(json.dumps(c) + '\n' for c in commands),
    capture_output=True, text=True, timeout=30, check=True,
)
messages = [json.loads(line) for line in result.stdout.splitlines() if line.strip()]
errors = [message for message in messages if 'error' in message]
if errors:
    raise SystemExit(f'QMP errors: {errors}')
responses = {message['id']: message for message in messages if 'id' in message}
if set(responses) != {'capabilities', 'status', 'cpu', 'quit'}:
    raise SystemExit(f'Missing QMP responses: {responses}')
status = responses['status']['return']
if status['running'] or status['status'] != 'prelaunch':
    raise SystemExit(f'Unexpected machine state: {status}')
props = responses['cpu']['return']['model']['props']
if props.get('pauth') is not True:
    raise SystemExit(f'Pointer Authentication is unavailable: {props}')
print('PASS: stock virt, secure=on, TCG, max CPU with PAUTH, QMP prelaunch and clean exit')
print('No firmware, Linux, OP-TEE, or TPM has been booted by this check.')
