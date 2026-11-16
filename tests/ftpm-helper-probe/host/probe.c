// SPDX-License-Identifier: BSD-2-Clause
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <tee_client_api.h>
#include <pta_jetson_ftpm_helper.h>

static TEEC_Session session;
static void require(TEEC_Result result, const char *where)
{
    if (result != TEEC_SUCCESS) {
        fprintf(stderr, "PTA_TEST: FAIL %s result=0x%x\n", where, result);
        exit(1);
    }
}
static void save(const char *name, const void *data, size_t len)
{
    FILE *f = fopen(name, "wb");
    if (!f || fwrite(data, 1, len, f) != len || fclose(f)) exit(1);
}
static void query(uint32_t cmd, const char *name, size_t size)
{
    unsigned char buffer[2048];
    TEEC_Operation op = { 0 };
    uint32_t origin;
    op.paramTypes = TEEC_PARAM_TYPES(TEEC_MEMREF_TEMP_OUTPUT, TEEC_NONE, TEEC_NONE, TEEC_NONE);
    op.params[0].tmpref.buffer = buffer;
    op.params[0].tmpref.size = size;
    require(TEEC_InvokeCommand(&session, cmd, &op, &origin), name);
    if (op.params[0].tmpref.size > sizeof(buffer)) exit(1);
    save(name, buffer, op.params[0].tmpref.size);
    printf("PTA_TEST: API %s PASS\n", name);
}
int main(void)
{
    TEEC_Context context;
    TEEC_UUID uuid = { 0x7fc1d460, 0x5a6c, 0x4a5f, {0x9b,0x9e,0x6c,0x29,0x8d,0x30,0x32,0xa0} };
    TEEC_Operation op = { 0 };
    uint32_t origin;
    unsigned char digest[32], signature[80];
    require(TEEC_InitializeContext(NULL, &context), "initialize");
    require(TEEC_OpenSession(&context, &session, &uuid, TEEC_LOGIN_PUBLIC, NULL, NULL, &origin), "open");
    op.paramTypes = TEEC_PARAM_TYPES(TEEC_VALUE_OUTPUT, TEEC_NONE, TEEC_NONE, TEEC_NONE);
    require(TEEC_InvokeCommand(&session, FTPM_HELPER_PTA_CMD_PING_NS, &op, &origin), "PING_NS");
    if (op.params[0].value.a != FTPM_HELPER_PTA_NS_STATE_READY) return 1;
    puts("PTA_TEST: PING_NS READY PASS");
    op.paramTypes = TEEC_PARAM_TYPES(TEEC_VALUE_OUTPUT, TEEC_VALUE_OUTPUT, TEEC_VALUE_OUTPUT, TEEC_NONE);
    require(TEEC_InvokeCommand(&session, FTPM_HELPER_PTA_CMD_QUERY_PROV_MODE, &op, &origin), "QUERY_PROV_MODE");
    if (op.params[0].value.a != FTPM_HELPER_PTA_ONLINE_PROV_MODE || op.params[1].value.a != 2 || op.params[2].value.a != 0) return 1;
    puts("PTA_TEST: online mode / version 2.0 PASS");
    query(FTPM_HELPER_PTA_CMD_QUERY_SN, "sn.bin", 10);
    query(FTPM_HELPER_PTA_CMD_QUERY_ECID, "ecid.bin", 8);
    query(FTPM_HELPER_PTA_CMD_GET_RSA_EK_CERT, "rsa-cert.der", 2048);
    query(FTPM_HELPER_PTA_CMD_GET_EC_EK_CERT, "ec-cert.der", 2048);
    query(FTPM_HELPER_PTA_CMD_GET_SID_CERT, "sid-cert.der", 2048);
    query(FTPM_HELPER_PTA_CMD_GET_FW_ID_CERT, "fw-cert.der", 2048);
    query(FTPM_HELPER_PTA_CMD_GET_RSA_EK_CSR, "rsa-csr.der", 2048);
    query(FTPM_HELPER_PTA_CMD_GET_EC_EK_CSR, "ec-csr.der", 2048);
    for (unsigned i = 0; i < sizeof(digest); i++) digest[i] = i;
    memset(&op, 0, sizeof(op));
    op.paramTypes = TEEC_PARAM_TYPES(TEEC_MEMREF_TEMP_INPUT, TEEC_MEMREF_TEMP_OUTPUT, TEEC_NONE, TEEC_NONE);
    op.params[0].tmpref.buffer = digest; op.params[0].tmpref.size = sizeof(digest);
    op.params[1].tmpref.buffer = signature; op.params[1].tmpref.size = sizeof(signature);
    require(TEEC_InvokeCommand(&session, FTPM_HELPER_PTA_CMD_SIGN_EK_CSR, &op, &origin), "SIGN_EK_CSR");
    if (op.params[1].tmpref.size != 64) return 1;
    save("signed-digest.bin", digest, sizeof(digest));
    save("signature.raw", signature, op.params[1].tmpref.size);
    {
        unsigned char der[72]; size_t pos = 2;
        for (size_t half = 0; half < 2; half++) {
            size_t start = half * 32, end = start + 32;
            while (start + 1 < end && signature[start] == 0) start++;
            size_t pad = (signature[start] & 0x80) != 0;
            der[pos++] = 2; der[pos++] = (unsigned char)(end - start + pad);
            if (pad) der[pos++] = 0;
            memcpy(der + pos, signature + start, end - start); pos += end - start;
        }
        der[0] = 0x30; der[1] = (unsigned char)(pos - 2);
        save("signature.der", der, pos);
    }
    puts("PTA_TEST: SIGN_EK_CSR raw signature received PASS");
    memset(&op, 0, sizeof(op));
    op.paramTypes = TEEC_PARAM_TYPES(TEEC_VALUE_OUTPUT, TEEC_NONE, TEEC_NONE, TEEC_NONE);
    if (TEEC_InvokeCommand(&session, FTPM_HELPER_PTA_CMD_SIGN_EK_CSR, &op, &origin) != TEEC_ERROR_BAD_PARAMETERS) return 1;
    if (TEEC_InvokeCommand(&session, FTPM_HELPER_PTA_CMD_INJECT_EPS, &op, &origin) != TEEC_ERROR_NOT_IMPLEMENTED) return 1;
    puts("PTA_TEST: invalid parameters and disabled INJECT_EPS rejected PASS");
    TEEC_CloseSession(&session); TEEC_FinalizeContext(&context);
    return 0;
}
