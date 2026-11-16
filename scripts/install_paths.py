"""Shared artifact prefix; mutable per-device state remains under work/."""
import os
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]

def install_dir():
    path = Path(os.environ.get('INSTALL_DIR', REPO/'install')).expanduser()
    return (path if path.is_absolute() else REPO/path).resolve()

def boot_dir():
    return install_dir()/'share/qemu-jetson/ftpm-virt'

def guest_lib_dir():
    return install_dir()/'lib/aarch64-linux-gnu'

def guest_bin_dir():
    return install_dir()/'libexec/aarch64-linux-gnu'

def ta_dev_kit():
    return install_dir()/'lib/optee/ta-dev-kit-aarch64'
