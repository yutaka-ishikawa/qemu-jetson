# 0004: Build and run without Docker

[日本語](../../decisions/0004-native-host.md) | English

Status: approved. The user explicitly requested removing Docker usage.

| Alternative | Benefits | Limitations |
| --- | --- | --- |
| Previous Docker setup | Builder image fixes tool versions | Requires Docker, daemon access and image storage |
| Direct host execution (selected) | No Docker/buildx; build and launch directly | Host dependencies must be installed; rootfs ownership-preserving assembly requires administrator privileges |

Build QEMU as an ordinary user into work/qemu-build/ by default, without make install.
Provide a separate explicitly invoked dependency installer rather than installing packages during builds.
Retain Ubuntu Base/PRoot and NVIDIA PTA/TA sources while removing Docker calls from build, launch and disk operations.
Preserve keys, certificates and the existing NV disk.
See [native host setup](../native-host.md) for instructions and validation scope.
