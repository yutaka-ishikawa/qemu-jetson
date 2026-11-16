# 0007: udev and ttyAMA0 boot waits

[日本語](../../decisions/0007-boot-device-wait.md) | English

Status: observations and alternatives recorded. No persistent optimization implemented. Option A recommended.

## Confirmed cause and limits

These messages are systemd job progress, not a kernel halt.
The /dev/ttyAMA0 job waits for the udev-backed device unit needed by serial-getty.
The kernel already detects PL011/ttyAMA0 around 0.2 seconds; it is not waiting 90 seconds for physical UART hardware.
The 1min 30s value is a job deadline, not a mandatory fixed delay.
Coldplug All udev Devices represents systemd-udev-trigger.service.

The unit read from the actual guest disk sequentially executes udevadm trigger --action=add for subsystems and devices.
It orders Before=sysinit.target, delaying basic services/tests until completion.
B2 starts tee-supplicant before this trigger so the fTPM driver probe can use its backend.

Normal logs show coldplug completing in the twenties of boot seconds, followed by device-unit registration.
A diagnostic systemd debug boot confirmed this order and passed second.
The launcher uses software emulation with one virtual CPU; userland coldplug enumeration and processing can be costly.
However, per-rule/process/sysfs/CPU timing has not been measured; neither a particular rule nor CPU shortage alone is established as the bottleneck.
This differs from the earlier table-exhaustion panic and SELinux socket failures.

## Alternatives

| Option | Approach | Benefit | Limitation |
| --- | --- | --- | --- |
| A (recommended) | Retain normal Ubuntu services and udev; profile triggers/rules and tune unnecessary work or concurrency | Evaluate improvements while preserving services and TPM behavior | More profiling needed; speedup unknown |
| B | Design a separate minimal fTPM-test boot profile, limiting unnecessary login/device processing | Potential faster test-only startup | Changes normal service/device discovery behavior; removing the tty wait alone does not eliminate coldplug work |

Reducing deadlines or hiding systemd status is not a causal fix.
Do not disable all udev processing: TPM device discovery and access settings may depend on it.
Persistent changes require scope/impact review and second/bound regression checks.
Current [build](../build-install.md) and [test](../test-guide.md) workflows remain unchanged.
