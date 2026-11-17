// SPDX-License-Identifier: BSD-2-Clause
/* Test-only relay: exercise the real NVIDIA PTA from a user TA. */
#include <tee_internal_api.h>
#include <pta_jetson_ftpm_helper.h>

static TEE_TASessionHandle helper = TEE_HANDLE_NULL;
TEE_Result TA_CreateEntryPoint(void) { return TEE_SUCCESS; }
void TA_DestroyEntryPoint(void)
{
    if (helper != TEE_HANDLE_NULL)
        TEE_CloseTASession(helper);
}
TEE_Result TA_OpenSessionEntryPoint(uint32_t types, TEE_Param p[4], void **ctx)
{
    const TEE_UUID uuid = FTPM_HELPER_PTA_UUID;
    (void)types; (void)p; (void)ctx;
    return TEE_OpenTASession(&uuid, TEE_TIMEOUT_INFINITE, 0, NULL, &helper, NULL);
}
void TA_CloseSessionEntryPoint(void *ctx) { (void)ctx; }
TEE_Result TA_InvokeCommandEntryPoint(void *ctx, uint32_t cmd, uint32_t types, TEE_Param p[4])
{
    (void)ctx;
    return TEE_InvokeTACommand(helper, TEE_TIMEOUT_INFINITE, cmd, types, p, NULL);
}
