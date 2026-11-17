import importlib.util
from pathlib import Path
import struct
import unittest

REPO=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('align_dtb',REPO/'scripts/align-optee-dtb.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)


def fixture(misaligned):
    words=lambda *args:struct.pack('>'+str(len(args))+'I',*args)
    body=words(1)+b'\0'*4
    if misaligned:body+=words(4)
    body+=words(1)+b'secure-chosen\0'+b'\0'*2
    seed=bytes.fromhex('0123456789abcdef')
    body+=words(3,8,0)+seed+words(2,2,9)
    names=b'kaslr-seed\0'
    header=words(0xd00dfeed,56+len(body)+len(names),56,56+len(body),40,17,16,0,len(names),len(body))
    return header+b'\0'*16+body+names,seed


class AlignmentTest(unittest.TestCase):
    def test_aligned_and_unaligned_seed(self):
        for bad in [False,True]:
            data,seed=fixture(bad)
            new,changed=module.align_seed(data)
            self.assertEqual(changed,bad)
            self.assertEqual(new.index(seed)%8,0)
            self.assertEqual(len(new),len(data)+(4 if bad else 0))
            self.assertEqual(module.align_seed(new),(new,False))
            self.assertEqual(struct.unpack_from('>I',new,4)[0],len(new))

    def test_missing_seed_is_not_silently_removed(self):
        data,_=fixture(False)
        with self.assertRaises(ValueError):module.align_seed(data.replace(b'kaslr-seed',b'other-name'))


if __name__=='__main__':unittest.main()
