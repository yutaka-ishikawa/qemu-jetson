#!/bin/sh
set -eu
export DEBIAN_FRONTEND=noninteractive
[ "$(id -u)" = 0 ] || { echo 'Guest setup must run as root' >&2; exit 1; }
apt-get -o APT::Sandbox::User=root update
apt-get -o APT::Sandbox::User=root install -y --no-install-recommends \
    systemd systemd-sysv udev kmod iproute2 ca-certificates \
    openssl tpm2-tools libtss2-tcti-device0
ldconfig
install -d -m 0700 /data/tee
mkdir -p /etc/systemd/system/multi-user.target.wants /usr/share/qemu-jetson
ln -sf ../jetson-tee-supplicant.service /etc/systemd/system/multi-user.target.wants/jetson-tee-supplicant.service
dpkg-query -W > /usr/share/qemu-jetson/packages.tsv
/usr/sbin/tee-supplicant --help
tpm2_getcap --version
rm -rf /var/lib/apt/lists/*
