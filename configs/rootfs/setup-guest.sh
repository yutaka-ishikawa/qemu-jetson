#!/bin/sh
set -eu
export DEBIAN_FRONTEND=noninteractive
[ "$(id -u)" = 0 ] || { echo 'Guest setup must run as root' >&2; exit 1; }
apt-get -o APT::Sandbox::User=root update
if apt-get -o APT::Sandbox::User=root install -y --no-install-recommends \
    systemd systemd-sysv udev kmod iproute2 policycoreutils ca-certificates \
    openssl tpm2-tools libtss2-tcti-device0 openssh-server sudo dbus; then
    :
else
    apt_status=$?
    echo "ROOTFS_DIAG: package installation failed (status=$apt_status)" >&2
    printf 'ROOTFS_DIAG: PATH=%s\n' "$PATH" >&2
    dpkg --audit >&2 || true
    if [ -e /var/lib/dpkg/info/ca-certificates.postinst ]; then
        for command_name in openssl sed find run-parts; do
            command -v "$command_name" >&2 || true
        done
        openssl version -a >&2 || true
        ldd /usr/bin/openssl >&2 || true
        echo 'ROOTFS_DIAG: tracing update-ca-certificates (last 100 lines)' >&2
        trace=$(mktemp /tmp/qemu-jetson-ca-trace.XXXXXX)
        if /bin/sh -ex /usr/sbin/update-ca-certificates --fresh --verbose >"$trace" 2>&1; then
            trace_status=0
        else
            trace_status=$?
        fi
        tail -n 100 "$trace" >&2 || true
        rm -f "$trace"
        echo "ROOTFS_DIAG: certificate trace status=$trace_status" >&2
        if [ -x /sbin/restorecon ]; then
            echo 'ROOTFS_DIAG: restorecon details and dry run (no relabeling)' >&2
            ls -l /sbin/restorecon >&2 || true
            if /sbin/restorecon -n -v /etc/ssl/certs/ca-certificates.crt >&2; then
                echo 'ROOTFS_DIAG: restorecon dry-run status=0' >&2
            else
                echo "ROOTFS_DIAG: restorecon dry-run status=$?" >&2
            fi
        fi
    fi
    exit "$apt_status"
fi
ldconfig
install -d -m 0700 /data/tee
mkdir -p /etc/systemd/system/multi-user.target.wants /usr/share/qemu-jetson
ln -sf ../jetson-tee-supplicant.service /etc/systemd/system/multi-user.target.wants/jetson-tee-supplicant.service
systemctl enable ssh.service systemd-networkd.service qemu-guest-setup.service
# Fresh images generate unique SSH host keys at first SSH-enabled boot.
rm -f /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub
systemctl enable ssh.service qemu-guest-setup.service systemd-networkd.service
# Generate unique host keys on each guest disk at first SSH start.
rm -f /etc/ssh/ssh_host_*
dpkg-query -W > /usr/share/qemu-jetson/packages.tsv
/usr/sbin/tee-supplicant --help
tpm2_getcap --version
rm -rf /var/lib/apt/lists/*
