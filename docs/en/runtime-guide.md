# Interactive boot, SSH, host sharing and debugging

[日本語](../runtime-guide.md) | English

Use this alongside [build/install](build-install.md) and [tests](test-guide.md).
Launcher man pages: [English](../man/run-ftpm-virt.1) and [Japanese](../ja/man/run-ftpm-virt.1).

New environments start with [build-install.md](build-install.md). For an existing disk, complete [upgrade-guide.md](upgrade-guide.md) first.

## Initial setup console

Root is locked with no default password. Normal boot does not enable passwordless root login.
Only explicit setup mode connects a root shell to ttyAMA0 for provisioning.
Root SSH and SSH password authentication are always disabled.

After fresh installation, stage only your PUBLIC key. If existing user/key setup is complete, skip account creation and proceed to normal boot.

```bash
mkdir -p work/login-share
install -m 0644 "$HOME/.ssh/id_ed25519.pub" work/login-share/login.pub
bash scripts/run-ftpm-virt.sh setup --share "$PWD/work/login-share"
```

Use your own public-key filename. Never copy the private key. At the guest setup console:

```bash
qemu-mount-host
adduser cradsec
usermod -aG sudo cradsec
qemu-register-ssh-key cradsec /mnt/host/login.pub
```

Before powering off, verify `/home/cradsec/.ssh/authorized_keys` inside the guest.

```bash
stat -c '%a %U:%G %n' /home/cradsec/.ssh /home/cradsec/.ssh/authorized_keys
ssh-keygen -lf /mnt/host/login.pub
ssh-keygen -lf /home/cradsec/.ssh/authorized_keys
grep -Fqx -f /mnt/host/login.pub /home/cradsec/.ssh/authorized_keys && echo 'Public key installed: OK'
```

Check that `stat` reports `700 cradsec:cradsec` for `.ssh` and `600 cradsec:cradsec` for `authorized_keys`.
Both `ssh-keygen` outputs should include the same key fingerprint, and the final command should print `Public key installed: OK`.
If other keys were already registered, the authorized_keys output lists multiple fingerprints.
If the file is missing, ownership/permissions differ, or the key does not match, check the public-key input path, rerun the registration command and verify again.
After successful verification, power off.

```bash
poweroff
```

The example username is cradsec; replace it if needed. The adduser password is for local login/sudo, not SSH.
Do not rerun adduser for an existing account. Key registration preserves existing keys and avoids duplicate entries.
A fresh rootfs already contains the packages. This section only creates the account and registers its public key.
Root's password is not set by this procedure; use regular-user sudo. Setup is a privileged host-operator console, not the usual boot mode.

## Normal boot (no options)

The examples below are alternatives selected for your purpose, not a sequence to execute. Run only one host-side `run-ftpm-virt.sh` command.
Before trying another launch example, run `sudo poweroff` inside the guest and wait for QEMU to exit.
Options can be combined, except that `--qemu-console` and `--monitor-socket` are mutually exclusive.
Guest, separate-host-terminal and GDB commands are follow-up operations for the selected example.

```bash
bash scripts/run-ftpm-virt.sh
```

Never run concurrent instances against the disk. Default: four CPUs, 1GiB RAM, no test execution, automatic poweroff or 300-second limit.
Log into the console using the created user.

## Launch option 1: SSH

Choose this instead of the launch without options when SSH is needed:

```bash
bash scripts/run-ftpm-virt.sh --ssh
```

After boot, connect from another host terminal:

```bash
ssh -p 2222 -i "$HOME/.ssh/id_ed25519" cradsec@127.0.0.1
```

Forwarding is localhost-only; change it with --ssh-port 2223.
Without --ssh, no NIC is created and sshd's startup condition is false.
The dedicated /etc/ssh/sshd_config_qemu sets PermitRootLogin no, AuthenticationMethods publickey and PasswordAuthentication no.

## Launch option 2: Host sharing (9p, manual mount)

On the host:

```bash
bash scripts/run-ftpm-virt.sh --ssh --share /path/to/host/data
```

Inside the guest:

```bash
sudo qemu-mount-host
ls /mnt/host
sudo umount /mnt/host
```

9p tag: hostshare. Default read-only. Pass an absolute mountpoint to change /mnt/host.
Writes require explicit options on both sides:

On the host, choose this instead of the read-only launch:

```bash
bash scripts/run-ftpm-virt.sh --share /path/to/host/data --share-rw
```

After that boot, inside the guest:

```bash
sudo qemu-mount-host --rw /mnt/host
```

Writable mapped-xattr exports need host filesystem xattr support. Host permissions still apply.
Share only necessary directories, excluding private keys and CA secrets.

## Launch option 3: CPU count

Example combining two CPUs and SSH:

```bash
bash scripts/run-ftpm-virt.sh --cpus 2 --ssh
```

Range 1..8, default four. The launcher generates matching DTBs and requires dtc.
Old one-CPU/GICv2 firmware is rejected with a rebuild instruction. GICv3 uses the unchanged NVIDIA kernel.
Check online CPUs inside the guest with getconf _NPROCESSORS_ONLN.

## Launch option 4: QEMU console and monitor

```bash
bash scripts/run-ftpm-virt.sh --qemu-console
```

Ctrl-a c switches between serial and monitor. Monitor commands include info cpus, info registers and cont.
quit/Ctrl-a x terminate QEMU immediately; use guest sudo poweroff for normal shutdown.
For a separate terminal:

```bash
bash scripts/run-ftpm-virt.sh --monitor-socket "$PWD/work/qemu-monitor.sock"
```

After that launch, in another host terminal with socat installed:

```bash
socat -,raw,echo=0 UNIX-CONNECT:"$PWD/work/qemu-monitor.sock"
```

Existing socket paths are rejected. Remove a stale socket only after confirming QEMU has exited.
--qemu-console and --monitor-socket are mutually exclusive.

## Launch option 5: GDB

Launch with CPUs halted until GDB connects:

```bash
bash scripts/run-ftpm-virt.sh --gdb --wait-gdb
```

After that launch, in another host terminal with AArch64-capable GDB:

```bash
gdb-multiarch
```

Inside GDB:

```text
target remote 127.0.0.1:1234
info registers
continue
```

--gdb starts normally; --wait-gdb halts CPUs before firmware. --gdb-port 1235 changes the localhost port.
No boot output while waiting is expected. Normal mode has no timeout; for paused test modes explicitly use --timeout 0 if needed.
This is a guest CPU stub. Load matching ELF symbols at the correct ASLR-adjusted addresses; automatic kernel/OP-TEE relocation is not provided.
To debug QEMU's host process instead, use host GDB with gdb -p PID. Installed binaries are stripped; use the matching unstripped work/qemu-build binary for detailed symbols.

## Launch option 6: Test modes

These modes run automated tests instead of normal boot. Choose this example only at the second-test stage; it is not an additional step required for interactive use.

```bash
bash scripts/run-ftpm-virt.sh second --cpus 4
```

Select first/second/export/bound explicitly; never rerun first on a completed disk.
Tests exit automatically. Follow [test-guide.md](test-guide.md) for ordering, prerequisites and success criteria.

## View the man page

```bash
man -l docs/man/run-ftpm-virt.1
man -l docs/ja/man/run-ftpm-virt.1
MANPATH="$PWD/install/share/man:${MANPATH:-}" man run-ftpm-virt
```

Install host man/SSH client/socat/GDB only as needed. See [decision 0008](decisions/0008-interactive-runtime.md).

Orderly shutdown uses qemu-ftpm-shutdown.service to issue TPM2_Shutdown and detach the driver before stopping the supplicant, avoiding backend calls after its service exits.

The supported eight-CPU configuration uses a project-only TF-A MPIDR topology matching QEMU GICv3; other profiles retain their original topology. The launcher and offline updater share a lock to prevent concurrent use.

## Validation

On the developer existing disk, verified 4/8 CPU Linux, regular-user public-key SSH, root/password rejection, manual RO/RW 9p, monitor mux/UNIX access, GDB stop/register reads and orderly poweroff. Bound passed with four and eight CPUs.
A fresh privileged rootfs rebuild was not performed. See [results](../results/runtime.json) and [excerpts](../results/runtime-excerpt.txt).
