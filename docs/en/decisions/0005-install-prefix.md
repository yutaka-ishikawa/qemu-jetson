# 0005: Consolidate built artifacts under install/

[日本語](../../decisions/0005-install-prefix.md) | English

Status: approved. The user specified install/ with bin/include/lib as the default artifact location.

| Alternative | Behavior | Limitation |
| --- | --- | --- |
| Previous | Run/read directly from work build directories | Intermediates and deployable outputs share locations |
| Selected | Install executables, headers, libraries and boot payloads after builds | Build and install locations must be distinguished |

Default to the repository's install/, overridable with INSTALL_DIR.
Place host QEMU in bin, public headers in include, ARM64 libraries in lib/aarch64-linux-gnu,
guest programs in libexec, and read-only boot payloads in share.
Private keys and NV disks remain work state and are not modified by installation.
Keep native host execution and direct main pushes. See the [layout](../install-layout.md).
