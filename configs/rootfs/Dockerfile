# Native build tools execute the ARM64 filesystem through PRoot/QEMU.
# No host binfmt registration or privileged container is required.
FROM --platform=$BUILDPLATFORM ubuntu:22.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    proot qemu-user-static ca-certificates && rm -rf /var/lib/apt/lists/*
ADD ubuntu-base-22.04.5-base-arm64.tar.gz /target/
COPY optee/ /target/
COPY overlay/ /target/
RUN cp /etc/resolv.conf /target/etc/resolv.conf \
    && proot -0 -q /usr/bin/qemu-aarch64-static -R /target /bin/sh -ec '\
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get -o APT::Sandbox::User=root update; \
    apt-get -o APT::Sandbox::User=root install -y --no-install-recommends \
        systemd systemd-sysv udev kmod iproute2 ca-certificates \
        openssl tpm2-tools libtss2-tcti-device0; \
    ldconfig; \
    install -d -m 0700 /data/tee; \
    mkdir -p /etc/systemd/system/multi-user.target.wants /usr/share/qemu-jetson; \
    ln -s ../jetson-tee-supplicant.service /etc/systemd/system/multi-user.target.wants/jetson-tee-supplicant.service; \
    dpkg-query -W > /usr/share/qemu-jetson/packages.tsv; \
    /usr/sbin/tee-supplicant --help; \
    tpm2_getcap --version; \
    rm -rf /var/lib/apt/lists/*' \
    && printf 'nameserver 10.0.2.3\n' > /target/etc/resolv.conf
FROM scratch
COPY --from=builder /target/ /
CMD ["/sbin/init"]
