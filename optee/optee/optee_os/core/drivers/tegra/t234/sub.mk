incdirs-y += include
incdirs-y += ../common/include

srcs-$(CFG_CRYPTO_DRV_HASH_TEGRA_SE) += crypto/tegra_driver_hash.c
srcs-$(CFG_TEGRA_SE) += tegra_se_aes_rng.c
srcs-$(CFG_TEGRA_SE) += tegra_se_map_device.c
srcs-$(CFG_TEGRA_FUSE) += tegra_fuse.c
srcs-$(CFG_RPMB_FS) += tegra_rpmb.c
