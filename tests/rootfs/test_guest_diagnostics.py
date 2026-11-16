"""Exercise guest setup diagnostics without apt, root, or a guest rootfs."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]


class GuestDiagnosticsTest(unittest.TestCase):
    def test_apt_failure_is_preserved_and_traced(self):
        source = (REPO/'configs/rootfs/setup-guest.sh').read_text().split('\nldconfig\n')[0]
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            for name, body in {
                'id': 'echo 0',
                'apt-get': '[ "$3" = update ] && exit 0; exit 100',
                'dpkg': 'echo mock-dpkg-audit',
                'openssl': 'echo mock-openssl-failure >&2; exit 127',
            }.items():
                target = directory/name
                target.write_text('#!/bin/sh\n'+body+'\n')
                target.chmod(0o755)
            postinst = directory/'postinst'
            postinst.touch()
            update = directory/'update-ca-certificates'
            update.write_text('openssl version\necho SHOULD_NOT_RUN_AFTER_FAILURE\n')
            source = source.replace('/var/lib/dpkg/info/ca-certificates.postinst', str(postinst))
            source = source.replace('/usr/sbin/update-ca-certificates', str(update))
            # The trace must explicitly target the guest updater.
            result = subprocess.run(['sh'], input=source, text=True, capture_output=True,
                                    env=dict(os.environ, PATH=tmp+':/usr/bin:/bin'))
            self.assertEqual(result.returncode, 100, result.stderr)
            self.assertIn('ROOTFS_DIAG: package installation failed (status=100)', result.stderr)
            self.assertIn('mock-openssl-failure', result.stderr)
            self.assertIn('certificate trace status=127', result.stderr)
            self.assertNotIn('SHOULD_NOT_RUN_AFTER_FAILURE', result.stderr)


if __name__ == '__main__':
    unittest.main()
