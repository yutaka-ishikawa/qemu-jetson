// SPDX-License-Identifier: BSD-2-Clause
/* Virtual platform providers for the unmodified NVIDIA fTPM helper PTA.
 * This is NOT the Tegra encrypted EKB/SE implementation.
 */
#include <drivers/tegra/tegra_fuse.h>
#include <io.h>
#include <jetson_user_key_pta_ftpm.h>
#include <kernel/tee_common_otp.h>
#include <mm/core_memprot.h>
#include <mm/core_mmu.h>

#define PROVISION_BASE 0x0c400000
#define PROVISION_SIZE 0x10000
#define PROVISION_MAX_ENTRIES 16
#define PROVISION_HEADER_SIZE (16 + PROVISION_MAX_ENTRIES * 16)

register_phys_mem(MEM_AREA_RAM_SEC, PROVISION_BASE, PROVISION_SIZE);

TEE_Result tegra_fuse_get_sn(uint8_t **sn, uint32_t *size)
{
	static uint8_t serial[10];

	if (!sn || !size)
		return TEE_ERROR_BAD_PARAMETERS;
	if (tee_otp_get_die_id(serial, sizeof(serial)))
		return TEE_ERROR_BAD_STATE;
	*sn = serial;
	*size = sizeof(serial);
	return TEE_SUCCESS;
}

TEE_Result tegra_fuse_get_64bit_ecid(uint64_t *val)
{
	uint8_t device_id[32] = { 0 };

	if (!val)
		return TEE_ERROR_BAD_PARAMETERS;
	if (tee_otp_get_die_id(device_id, sizeof(device_id)))
		return TEE_ERROR_BAD_STATE;
	memcpy(val, device_id + 10, sizeof(*val));
	return TEE_SUCCESS;
}

TEE_Result jetson_user_key_pta_query_ftpm_prop(uint32_t id, uint8_t **data,
					   uint32_t *len)
{
	const uint8_t *p = phys_to_virt(PROVISION_BASE, MEM_AREA_RAM_SEC,
				      PROVISION_SIZE);
	uint32_t total = 0;
	uint32_t count = 0;
	uint32_t i = 0;

	if (!data || !len)
		return TEE_ERROR_BAD_PARAMETERS;
	*data = NULL;
	*len = 0;
	if (id < EKB_FTPM_SN || id >= EKB_FTPM_ID_MAX)
		return TEE_ERROR_ITEM_NOT_FOUND;
	if (!p || memcmp(p, "JFPRV001", 8))
		return TEE_ERROR_ITEM_NOT_FOUND;
	total = get_unaligned_le32(p + 8);
	count = get_unaligned_le32(p + 12);
	if (total < PROVISION_HEADER_SIZE || total > PROVISION_SIZE ||
	    count > PROVISION_MAX_ENTRIES)
		return TEE_ERROR_BAD_FORMAT;
	for (i = 0; i < count; i++) {
		const uint8_t *entry = p + 16 + i * 16;
		uint32_t off = get_unaligned_le32(entry + 4);
		uint32_t size = get_unaligned_le32(entry + 8);

		if (get_unaligned_le32(entry + 12) ||
		    off < PROVISION_HEADER_SIZE || off > total ||
		    !size || size > total - off)
			return TEE_ERROR_BAD_FORMAT;
		if (get_unaligned_le32(entry) == id) {
			if ((id == EKB_FTPM_SN && size != 10) ||
			    (id == EKB_FTPM_EPS_SEED && size != 32) ||
			    (id >= EKB_FTPM_RSA_EK_CERT && size > 2048))
				return TEE_ERROR_BAD_FORMAT;
			*data = (uint8_t *)p + off;
			*len = size;
			return TEE_SUCCESS;
		}
	}
	return TEE_ERROR_ITEM_NOT_FOUND;
}
