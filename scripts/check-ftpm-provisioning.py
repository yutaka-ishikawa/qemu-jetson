#!/usr/bin/env python3
"""Exercise provisioning handoff bounds; no device keys/certificates generated."""
import struct
import unittest
from ftpm_provisioning import HEADER_SIZE, dt_nodes, pack, parse


class HandoffBounds(unittest.TestCase):
    def setUp(self):
        # Structural fixtures only, deliberately not valid cryptographic material.
        self.image = pack({1: b's' * 32, 2: b'k' * 32, 3: b'certificate',
                           91: b'0123456789', 92: b'e' * 32,
                           93: b'rsa-cert', 94: b'ec-cert'})

    def reject(self, offset, value):
        changed = bytearray(self.image)
        struct.pack_into('<I', changed, offset, value)
        with self.assertRaises(ValueError):
            parse(changed)

    def test_round_trip_and_dt_pointers(self):
        entries = parse(self.image)
        self.assertEqual(entries[91][1], 10)
        nodes = dt_nodes(self.image)
        self.assertIn('secure-status = "okay"', nodes)
        self.assertIn('nvidia,ftpm-firmware-id-privkey', nodes)
        self.assertNotIn('0123456789', nodes)

    def test_truncation(self):
        for length in (0, 8, HEADER_SIZE - 1, len(self.image) - 1):
            with self.assertRaises(ValueError):
                parse(self.image[:length])

    def test_excess_entry_count(self):
        self.reject(12, 17)

    def test_payload_in_header(self):
        self.reject(20, HEADER_SIZE - 1)

    def test_32bit_overflow_size(self):
        self.reject(24, 0xffffffff)

    def test_duplicate_id(self):
        self.reject(32, 1)

    def test_overlapping_entries(self):
        self.reject(36, HEADER_SIZE)

    def test_nonzero_reserved(self):
        self.reject(28, 1)

    def test_missing_provisioning_data(self):
        with self.assertRaises(ValueError):
            pack({1: b's' * 32, 2: b'k' * 32, 3: b'cert',
                  91: b'0123456789', 92: b'e' * 32})


if __name__ == '__main__':
    unittest.main()
