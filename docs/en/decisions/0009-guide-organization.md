# 0009: Separate fresh build, normal use, tests and upgrades

[日本語](../../decisions/0009-guide-organization.md) | English

Status: user selected option A.

| Option | Organization | Assessment |
| --- | --- | --- |
| A (selected) | Four guides: build-install, runtime-guide, test-guide, upgrade-guide | Fresh users avoid executing existing-disk repair steps |
| B | Keep build/test guides and combine normal use and upgrades as sections | Fewer files, but retains the fresh/existing workflow ambiguity |

Option A was proposed and approved. Option B is documented as a comparison, not a selected design.

- build-install.md: fresh clone, dependencies/toolchain, builds, initial data, rootfs/disk and DTBs.
- runtime-guide.md: initial user/key registration and normal use of an installed environment. Example username is cradsec, as requested.
- test-guide.md: test execution and PASS criteria from first to bound reboot.
- upgrade-guide.md: existing-environment rebuilding, overlays, missing packages and historical fixes/recovery.

Maintain both languages with the same roles, linked from README and man pages.
Do not reinstall runtime packages during fresh account setup: the new rootfs already contains them.
Upgrades preserve existing accounts, credentials and disks.
