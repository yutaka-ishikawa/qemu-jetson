// SPDX-License-Identifier: BSD-2-Clause
/* Test-only virtual device identity. Host protection replaces physical fuses. */
#include <kernel/tee_common_otp.h>
#include <mm/core_memprot.h>
#include <mm/core_mmu.h>

#define IDENTITY_BASE 0x0c200000
register_phys_mem_pgdir(MEM_AREA_IO_SEC, IDENTITY_BASE, 4096);

static const uint8_t *identity(void)
{
    const uint8_t *p = phys_to_virt(IDENTITY_BASE, MEM_AREA_IO_SEC, 72);

    if (!p || memcmp(p, "JFTPM001", 8))
        return NULL;
    return p;
}

TEE_Result tee_otp_get_hw_unique_key(struct tee_hw_unique_key *key)
{
    const uint8_t *p = identity();

    if (!p || sizeof(key->data) > 32)
        return TEE_ERROR_BAD_STATE;
    memcpy(key->data, p + 8, sizeof(key->data));
    return TEE_SUCCESS;
}

int tee_otp_get_die_id(uint8_t *buffer, size_t len)
{
    const uint8_t *p = identity();

    if (!p || len > 32)
        return -1;
    memcpy(buffer, p + 40, len);
    return 0;
}
