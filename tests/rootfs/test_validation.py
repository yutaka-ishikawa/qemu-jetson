"""Regression checks for accidentally creating an overlay-only rootfs tar."""
import io
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / 'scripts'))
from rootfs_validation import validate_rootfs


class RootfsValidationTest(unittest.TestCase):
    def test_reject_before_modifying_archive(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'rootfs.tar'
            for state in ('missing', 'empty', 'overlay'):
                if state != 'missing':
                    with tarfile.open(path, 'w') as tar:
                        if state == 'overlay':
                            item = tarfile.TarInfo('usr/local/sbin/ftpm-functional-test')
                            tar.addfile(item, io.BytesIO(b''))
                original = path.read_bytes() if path.exists() else None
                result = subprocess.run(
                    [sys.executable, str(REPO / 'scripts/prepare-ftpm-test-rootfs.py'),
                     str(path), str(Path(directory) / 'missing-fixtures')],
                    capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('No archive was modified', result.stderr)
                self.assertEqual(path.read_bytes() if path.exists() else None, original)
                self.assertFalse(path.with_suffix('.tar.sha256').exists())

    def test_accept_expected_layout_with_dot_prefix(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'rootfs.tar'
            with tarfile.open(path, 'w') as tar:
                for name in ('usr/sbin', 'usr/lib', 'usr/bin/dpkg', 'etc/passwd',
                             'usr/sbin/tee-supplicant', 'usr/sbin/nvftpm-helper-app'):
                    item = tarfile.TarInfo('./' + name)
                    if name in ('usr/sbin', 'usr/lib'):
                        item.type = tarfile.DIRTYPE
                    tar.addfile(item)
            validate_rootfs(path)


if __name__ == '__main__':
    unittest.main()
