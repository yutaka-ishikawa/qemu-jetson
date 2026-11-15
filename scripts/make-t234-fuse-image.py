#!/usr/bin/env python3
"""Build the explicit partial, read-only register image; not an OTP fuseblob."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('profile', type=Path)
parser.add_argument('output', type=Path)
args = parser.parse_args()
profile = json.loads(args.profile.read_text())
if profile['format'] != 't234-readonly-fuse-v1':
    raise SystemExit('Unsupported profile format')
supported = {0x1a0, 0x200, 0x204, 0x208, 0x20c, 0x210, 0x214,
             0x218, 0x220, 0x268, 0x29c, 0x408, 0x40c}
registers = {int(k, 0): int(v, 0) for k, v in profile['registers'].items()}
if len(registers) != len(profile['registers']) or set(registers) != supported:
    raise SystemExit('Specify each supported register exactly once')
if any(not 0 <= value <= 0xffffffff for value in registers.values()):
    raise SystemExit('Register values must be unsigned 32-bit integers')
if any(((registers[0x208] >> shift) & 63) >= 36 for shift in [24, 18, 12, 6, 0]):
    raise SystemExit('Invalid base-36 lot digit')
image = bytearray(0x600)
for offset, value in registers.items():
    struct.pack_into('<I', image, offset, value)
args.output.parent.mkdir(parents=True, exist_ok=True)
if args.output.exists() and args.output.read_bytes() != image:
    raise SystemExit('Refusing to replace a different image; use a new output path')
args.output.write_bytes(image)
print(hashlib.sha256(image).hexdigest(), args.output)
