"""Verify launcher argument composition without opening a real TPM disk."""
import json
import os
import fcntl
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO=Path(__file__).resolve().parents[2]


class LauncherTest(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.root=Path(self.tmp.name)
        (self.root/'scripts').mkdir()
        for name in ['run-ftpm-virt.sh','host-common.sh']:
            shutil.copyfile(REPO/'scripts'/name,self.root/'scripts'/name)
        p=self.root/'scripts/prepare-ftpm-virt-dtb.sh'
        p.write_text('#!/bin/sh\nexit 0\n')
        out=self.root/'work/ftpm-virt';out.mkdir(parents=True)
        for name in ['device-identity.bin','provisioning.bin','rootfs.ext4']:(out/name).touch()
        boot=self.root/'install/share/qemu-jetson/ftpm-virt';boot.mkdir(parents=True)
        for name in ['flash.bin','Image']:(boot/name).touch()
        (boot/'firmware-cpus.txt').write_text('8\n')
        (boot/'firmware-gic.txt').write_text('3\n')
        binary=self.root/'install/bin/qemu-system-aarch64';binary.parent.mkdir(parents=True)
        binary.write_text('#!/usr/bin/env python3\nimport json,sys\nprint(json.dumps(sys.argv[1:]))\n')
        binary.chmod(0o755)
        (self.root/'bin').mkdir()
        (self.root/'bin/dtc').write_text('#!/bin/sh\nexit 0\n')
        (self.root/'bin/dtc').chmod(0o755)
        self.env={k:v for k,v in os.environ.items() if k not in ['INSTALL_DIR','FTPM_SECURE_LOG','FTPM_TIMEOUT']}

        self.env['PATH']=str(self.root/'bin')+':'+self.env['PATH']

    def tearDown(self): self.tmp.cleanup()

    def run_launcher(self,*args,success=True):
        result=subprocess.run(['bash',str(self.root/'scripts/run-ftpm-virt.sh'),*args],env=self.env,capture_output=True,text=True)
        if success:
            self.assertEqual(result.returncode,0,result.stderr)
            return json.loads(result.stdout)
        self.assertNotEqual(result.returncode,0,result.stdout)
        return result

    def test_normal_defaults_and_no_network(self):
        args=self.run_launcher()
        self.assertEqual(args[args.index('-smp')+1],'4')
        self.assertIn('none',args)
        self.assertTrue(args[args.index('-dtb')+1].endswith('runtime-normal.dtb'))
        self.assertNotIn('-netdev',args)

    def test_ssh_share_and_debug(self):
        share=self.root/'space and,comma';share.mkdir()
        args=self.run_launcher('setup','--cpus','2','--ssh-port','2223','--share',str(share),'--share-rw','--gdb-port','1235','--wait-gdb','--qemu-console')
        self.assertEqual(args[args.index('-smp')+1],'2')
        self.assertIn('127.0.0.1:2223-:22',args[args.index('-netdev')+1])
        self.assertEqual(args[args.index('-gdb')+1],'tcp:127.0.0.1:1235')
        self.assertIn('-S',args)
        self.assertIn('space and,,comma',args[args.index('-fsdev')+1])
        self.assertNotIn('readonly=on',args[args.index('-fsdev')+1])
        self.assertIn('monitor-hmp,id=hmp,chardev=console,readline=on',args)

    def test_readonly_and_unix_monitor(self):
        args=self.run_launcher('--share',str(self.root),'--monitor-socket',str(self.root/'monitor.sock'))
        self.assertIn('readonly=on',args[args.index('-fsdev')+1])
        self.assertIn('server=on,wait=off',args[args.index('-chardev')+1])

    def test_reject_invalid_combinations(self):
        for args in [('--cpus','0'),('--cpus','9'),('--ssh-port','65536'),('--gdb-port','0'),('--share-rw',),('second','--ssh'),('--qemu-console','--monitor-socket',str(self.root/'m')),('--timeout','-1')]:
            with self.subTest(args=args):self.run_launcher(*args,success=False)

    def test_reject_concurrent_launcher(self):
        with (self.root/'work/ftpm-virt/runtime.lock').open('a') as lock:
            fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
            result=self.run_launcher(success=False)
            self.assertIn('Another launcher',result.stderr)

    def test_reject_old_firmware(self):
        (self.root/'install/share/qemu-jetson/ftpm-virt/firmware-cpus.txt').unlink()
        r=self.run_launcher(success=False)
        self.assertIn('Rebuild firmware',r.stderr)


if __name__=='__main__':unittest.main()
