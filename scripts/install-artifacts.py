#!/usr/bin/env python3
"""Install selected compiled artifacts, never device secrets or mutable disks."""
import argparse
import os
from pathlib import Path
import shutil
from install_paths import REPO, install_dir, boot_dir, guest_bin_dir, guest_lib_dir, ta_dev_kit


def copy(source, target, mode=0o644):
    source, target = Path(source), Path(target)
    if source.name in ('device-identity.bin','provisioning.bin','rootfs.ext4') or source.suffix in ('.pem','.key'):
        raise SystemExit('Device state/signing keys are not install artifacts: '+str(source))
    if source.absolute() == target.absolute():
        return
    if not source.exists():
        raise SystemExit('Missing build artifact: '+str(source))
    target.parent.mkdir(parents=True, exist_ok=True)
    if source.is_symlink():
        link = source.readlink()
        if link.is_absolute() or len(link.parts) != 1:
            raise SystemExit('Unexpected library symlink: '+str(source))
        if target.is_symlink() and target.readlink() == link:
            return
        if target.exists() or target.is_symlink(): target.unlink()
        target.symlink_to(link)
        return
    if target.is_symlink(): target.unlink()
    shutil.copyfile(source, target)
    target.chmod(mode)


def tree(source, target):
    if not Path(source).is_dir():
        raise SystemExit('Missing artifact tree: '+str(source))
    for path in sorted(Path(source).rglob('*')):
        # Signing keys are inputs, not deployable SDK artifacts.
        if 'keys' in path.relative_to(source).parts or path.suffix in ('.pem', '.key'):
            continue
        if path.is_file() or path.is_symlink():
            copy(path, Path(target)/path.relative_to(source), 0o755 if os.access(path, os.X_OK) else 0o644)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('component', choices=['firmware','probe','client','kernel','dtb','t234'])
    p.add_argument('--client-export',type=Path)
    args=p.parse_args()
    prefix=install_dir()
    if prefix in (Path('/'), REPO):
        p.error('Use an artifact directory, not / or the repository root')
    if args.component=='firmware':
        for name in ['flash.bin','linux-entry.bin','linux-entry.elf']:
            copy(REPO/'work/ftpm-virt'/name,boot_dir()/name)
        for name in ['tee-header_v2.bin','tee-pager_v2.bin','tee-pageable_v2.bin','tee.elf']:
            copy(REPO/'work/optee-virt/core'/name,prefix/'share/qemu-jetson/optee'/name)
        for name in ['bl1.bin','bl2.bin','bl31.bin','fip.bin']:
            copy(REPO/'work/tf-a/qemu/release'/name,prefix/'share/qemu-jetson/tf-a'/name)
        tree(REPO/'work/optee-virt/export-ta_arm64',ta_dev_kit())
        for directory in ['ms-tpm','ftpm-helper']:
            for source in (REPO/'work/optee-virt/early_ta'/directory).glob('*.ta'):
                copy(source,guest_lib_dir()/'optee_armtz'/source.name)
    elif args.component=='probe':
        copy(REPO/'work/helper-probe/ftpm-helper-probe',guest_bin_dir()/'ftpm-helper-probe',0o755)
        for source in (REPO/'work/helper-probe/ta').glob('*.ta'):
            copy(source,guest_lib_dir()/'optee_armtz'/source.name)
    elif args.component=='client':
        base=args.client_export or Path(os.environ.get('OPTEE_CLIENT_EXPORT', REPO/'work/optee-client/export/usr'))
        if (base/'libexec/aarch64-linux-gnu').is_dir():
            lib=base/'lib/aarch64-linux-gnu'
            bins=[base/'libexec/aarch64-linux-gnu']
        else:
            if (base/'usr').is_dir(): base=base/'usr'
            lib=base/'lib'
            bins=[base/'bin',base/'sbin']
        if not (base/'include/tee_client_api.h').is_file(): p.error('Missing client headers under '+str(base))
        if not any((directory/'tee-supplicant').is_file() for directory in bins): p.error('Missing tee-supplicant under '+str(base))
        tree(base/'include',prefix/'include')
        for source in lib.glob('lib*'):
            if source.is_file() or source.is_symlink(): copy(source,guest_lib_dir()/source.name)
        for directory in bins:
            for source in directory.glob('*'):
                if source.is_file(): copy(source,guest_bin_dir()/source.name,0o755)
        copy(REPO/'optee/optee/optee_os/lib/libutee/include/pta_jetson_ftpm_helper.h',prefix/'include/pta_jetson_ftpm_helper.h')
    elif args.component=='kernel':
        copy(REPO/'work/ftpm-virt/Image',boot_dir()/'Image')
        tree(REPO/'work/ftpm-virt/modules/lib/modules',prefix/'lib/modules')
    elif args.component=='dtb':
        for phase in ['first','second','export','bound']:
            copy(REPO/f'work/ftpm-virt/runtime-{phase}.dtb',boot_dir()/f'runtime-{phase}.dtb')
    elif args.component=='t234':
        baseline=REPO/'work/optee-baseline/tee-raw.bin'
        if baseline.is_file(): copy(baseline,prefix/'share/qemu-jetson/t234/tee-raw.bin')
        for source in (REPO/'work/t234-firmware').iterdir():
            if source.suffix in ('.bin','.elf','.dtb'):copy(source,prefix/'share/qemu-jetson/t234'/source.name)
    print('Installed '+args.component+' artifacts under '+str(prefix))

if __name__=='__main__': main()
