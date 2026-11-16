#!/usr/bin/env python3
"""Reject missing or overlay-only Ubuntu rootfs archives before modifying them."""
import sys
import tarfile


def validate_rootfs(path):
    required = {
        "usr/sbin": "directory",
        "usr/lib": "directory",
        "usr/bin/dpkg": "file",
        "etc/passwd": "file",
        "usr/sbin/tee-supplicant": "file",
        "usr/sbin/nvftpm-helper-app": "file",
    }
    with tarfile.open(path, "r:") as archive:
        members = {entry.name.removeprefix("./").rstrip("/"): entry
                   for entry in archive}
    missing = [name for name, kind in required.items()
               if name not in members or not
               (members[name].isdir() if kind == "directory" else members[name].isfile())]
    if missing:
        raise ValueError("Not a complete Ubuntu fTPM rootfs; missing: " + ", ".join(missing))


if __name__ == "__main__":
    try:
        validate_rootfs(sys.argv[1])
    except (OSError, tarfile.TarError, ValueError) as error:
        sys.exit(f"{error}. Build Ubuntu first with scripts/build-ubuntu-rootfs.sh; "
                 "see docs/build-install.md for recovery. No archive was modified.")
