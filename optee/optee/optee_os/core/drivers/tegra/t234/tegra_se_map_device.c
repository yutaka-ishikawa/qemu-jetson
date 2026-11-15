// SPDX-License-Identifier: BSD-2-Clause
/*
 * Copyright (c) 2022, NVIDIA CORPORATION & AFFILIATES.
 */

#include <string.h>
#include <stdlib.h>
#include <types_ext.h>
#include <tee_api_types.h>
#include <trace.h>
#include <initcall.h>
#include <rng_support.h>
#include <utee_defines.h>
#include <tegra_se_ccc.h>
#include <tegra_se_ccc_errno.h>
#include <tegra_driver_se.h>
#include <tegra_driver_srv_intf.h>

#if defined(CFG_TEGRA_SE_RNG1)
#include <tegra_driver_rng1.h>
#endif

/* This function is called by tegra_init_crypto_devices to map devices */
status_t tegra_se_map_device(optee_tegra_se_cdev_id_t device_id, void **base_va)
{
	TEE_Result rc = TEE_SUCCESS;
	status_t ret = NO_ERROR;
	vaddr_t va = 0;

	if (base_va == NULL) {
		EMSG("tegra_se_map_device: base_va is NULL.");
		*base_va = NULL;
		return ERR_INVALID_ARGS;
	}

	switch (device_id) {
	case OPTEE_TEGRA_SE_CDEV_SE0:
		rc = tegra_se_map_regs(&va);
		if (rc != TEE_SUCCESS) {
			EMSG("Mapping SE0 regs failed: 0x%x", rc);
			*base_va = NULL;
			ret = ERR_GENERIC;
			goto out;
		}
		ret = tegra_se_ccc_configure_se0(va);
		if (ret != NO_ERROR) {
			EMSG("Configure SE0 failed: %d", ret);
			*base_va = NULL;
			goto out;
		}
		*base_va = (void *)va;
		break;
#if defined(CFG_TEGRA_SE_RNG1)
	case OPTEE_TEGRA_SE_CDEV_RNG1:
		/*
		 * Random numbers can be generated via SE engine as well,
		 * just mapping the RNG1 here too in case we need to use NVRNG
		 * in the future.
		 */
		rc = tegra_rng1_map_regs(&va);
		if (rc != TEE_SUCCESS) {
			EMSG("Mapping RNG1 regs failed: 0x%x", rc);
			*base_va = NULL;
			ret = ERR_GENERIC;
			goto out;
		}
		ret = tegra_se_ccc_configure_rng1(va);
		if (ret != NO_ERROR) {
			EMSG("Configure RNG1 failed: %d", ret);
			*base_va = NULL;
			goto out;
		}
		*base_va = (void *)va;
		break;
#endif
	default:
		/* CCC will disable the unsupported devices accordingly */
		DMSG("Mapping unsupported SE device: %d", device_id);
		*base_va = NULL;
		break;
	}

out:
	return ret;
}
