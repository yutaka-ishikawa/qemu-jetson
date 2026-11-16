"""QEMU-only secure handoff format; not NVIDIA encrypted EKB format."""
import struct

MAGIC = b'JFPRV001'
BASE = 0x0c400000
MAX_SIZE = 65536
MAX_ENTRIES = 16
HEADER_SIZE = 16 + MAX_ENTRIES * 16
FIELDS = {
    'ftpm_seed': 1,
    'firmware_id_key': 2,
    'firmware_id_cert': 3,
    'sn': 91,
    'eps_seed': 92,
    'rsa_ek_cert': 93,
    'ec_ek_cert': 94,
    'sid_cert': 95,
    'rsa_ek_csr': 96,
    'ec_ek_csr': 97,
}


def parse(data):
    if len(data) < HEADER_SIZE or len(data) > MAX_SIZE or data[:8] != MAGIC:
        raise ValueError('invalid provisioning image header')
    total, count = struct.unpack_from('<II', data, 8)
    if total != len(data) or count > MAX_ENTRIES:
        raise ValueError('invalid provisioning image size/count')
    entries = {}
    ranges = []
    for i in range(count):
        key, off, size, reserved = struct.unpack_from('<IIII', data, 16 + i * 16)
        if key not in FIELDS.values() or key in entries or reserved:
            raise ValueError('unknown/duplicate entry or reserved bits')
        if off < HEADER_SIZE or size == 0 or off > total or size > total - off:
            raise ValueError('entry outside payload')
        if any(off < end and start < off + size for start, end in ranges):
            raise ValueError('overlapping provisioning entries')
        ranges.append((off, off + size))
        entries[key] = (off, size)
    for key, size in ((1, 32), (2, 32), (91, 10), (92, 32)):
        if key not in entries or entries[key][1] != size:
            raise ValueError('missing or invalid seed/key/SN')
    if 3 not in entries:
        raise ValueError('missing Firmware ID certificate')
    if not ({93, 94} <= entries.keys() or {95, 96, 97} <= entries.keys()):
        raise ValueError('need offline EK certificates or online SID certificate and EK CSRs')
    if any(size > 2048 for key, (_, size) in entries.items() if key >= 93 or key == 3):
        raise ValueError('certificate/CSR exceeds NVIDIA helper buffer size')
    return entries


def pack(values):
    data = bytearray(HEADER_SIZE)
    data[:8] = MAGIC
    for i, (key, payload) in enumerate(sorted(values.items())):
        if i >= MAX_ENTRIES:
            raise ValueError('too many entries')
        data.extend(b'\0' * (-len(data) % 4))
        struct.pack_into('<IIII', data, 16 + i * 16, key, len(data), len(payload), 0)
        data.extend(payload)
    struct.pack_into('<II', data, 8, len(data), len(values))
    parse(data)
    return bytes(data)


def dt_nodes(data):
    entries = parse(data)
    names = {1: 'nvidia,ftpm-seed', 2: 'nvidia,ftpm-firmware-id-privkey',
             3: 'nvidia,ftpm-firmware-id-certificate'}
    nodes = ['ftpm-contents { compatible = "nvidia,ftpm-contents";',
             'status = "disabled"; secure-status = "okay"; };']
    for key, name in names.items():
        off, size = entries[key]
        nodes.append(f'ftpm-data-{key}@{BASE + off:x} {{ compatible = "{name}"; '
                     'status = "disabled"; secure-status = "okay"; '
                     f'reg = <0 0x{BASE + off:x} 0 0x{size:x}>; }};')
    return '\n'.join(nodes)
