/*
 * Copyright (c) 2023-2024, NVIDIA Corporation & AFFILIATES. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#include <conf.h>
#include <tee_internal_api.h>
#ifdef CFG_JETSON_FTPM_HELPER_PTA
#include <ftpm_helper_ta.h>
#include <inttypes.h>
#include <pta_jetson_ftpm_helper.h>
#include <stdlib.h>
#include <string.h>
#include <tee_internal_api_extensions.h>
#include <utee_defines.h>
#include <mbedtls/asn1.h>
#include <mbedtls/asn1write.h>
#include <mbedtls/bignum.h>
#include <mbedtls/ecdsa.h>
#include <mbedtls/error.h>
#include <mbedtls/oid.h>

/* EK CSR structure */
typedef struct ek_csr_t {
	uint8_t *csr_head;
	uint32_t csr_total_len;
	uint8_t *tbs_ptr;
	uint32_t tbs_len;
	uint32_t sig_len;
} ek_csr_t;

static TEE_Result invoke_ftpm_helper_pta(uint32_t cmd_id,
					 uint32_t param_types,
					 TEE_Param params[TEE_NUM_PARAMS])
{
	static TEE_TASessionHandle pta_sess = TEE_HANDLE_NULL;
	const TEE_UUID uuid = FTPM_HELPER_PTA_UUID;

	if (TEE_HANDLE_NULL == pta_sess) {
		TEE_Result rc = TEE_OpenTASession(&uuid, TEE_TIMEOUT_INFINITE,
						   0, NULL, &pta_sess, NULL);

		if (rc)
			return rc;
	}

	return TEE_InvokeTACommand(pta_sess, TEE_TIMEOUT_INFINITE, cmd_id,
				   param_types, params, NULL);
}

static TEE_Result calc_csr_tbs_hash(const uint8_t *tbs_ptr, uint32_t tbs_len,
				   uint8_t *hash, size_t *hash_len)
{
	TEE_OperationHandle hash_op = TEE_HANDLE_NULL;
	TEE_Result rc = TEE_SUCCESS;

	/* Calculate the digest of the CSR TBS */
	rc = TEE_AllocateOperation(&hash_op, TEE_ALG_SHA256, TEE_MODE_DIGEST, 0);
	if (rc != TEE_SUCCESS)
		return rc;

	rc = TEE_DigestDoFinal(hash_op, tbs_ptr, tbs_len, hash, hash_len);
	TEE_FreeOperation(hash_op);

	return rc;
}

static TEE_Result sign_csr_digest(uint8_t *tbs_digest, uint32_t digest_len,
				  uint8_t *sig, uint32_t *sig_len)
{
	uint32_t pt;
	TEE_Param pta_params[TEE_NUM_PARAMS] = { };
	TEE_Result rc = TEE_SUCCESS;
	mbedtls_mpi r;
	mbedtls_mpi s;
	uint32_t r_len;
	uint8_t buf[MBEDTLS_ECDSA_MAX_LEN] = { 0 };
	uint8_t *p = buf + sizeof(buf);
	uint32_t len = 0;
	int ret = MBEDTLS_ERR_ERROR_CORRUPTION_DETECTED;

	/* The input parameters. */
	pt = TEE_PARAM_TYPES(TEE_PARAM_TYPE_MEMREF_INPUT,
			     TEE_PARAM_TYPE_MEMREF_OUTPUT,
			     TEE_PARAM_TYPE_NONE,
			     TEE_PARAM_TYPE_NONE);

	if ((TEE_SHA256_HASH_SIZE != digest_len) ||
	    (FTPM_EK_CSR_SIG_SIZE != *sig_len))
		return TEE_ERROR_BAD_PARAMETERS;

	pta_params[0].memref.buffer = tbs_digest;
	pta_params[0].memref.size = digest_len;
	pta_params[1].memref.buffer = sig;
	pta_params[1].memref.size = *sig_len;

	rc = invoke_ftpm_helper_pta(FTPM_HELPER_PTA_CMD_SIGN_EK_CSR,
				    pt, pta_params);
	if (rc != TEE_SUCCESS)
		return rc;

	/* Convert the signature to ASN1 format. */
	r_len = pta_params[1].memref.size / 2;
	mbedtls_mpi_init(&r);
	mbedtls_mpi_init(&s);

	mbedtls_mpi_read_binary(&r, sig, r_len);
	mbedtls_mpi_read_binary(&s, sig + r_len, r_len);

	MBEDTLS_ASN1_CHK_ADD(len, mbedtls_asn1_write_mpi(&p, buf, &s));
	MBEDTLS_ASN1_CHK_ADD(len, mbedtls_asn1_write_mpi(&p, buf, &r));

	MBEDTLS_ASN1_CHK_ADD(len, mbedtls_asn1_write_len(&p, buf, len));
	MBEDTLS_ASN1_CHK_ADD(len, mbedtls_asn1_write_tag(&p, buf, MBEDTLS_ASN1_CONSTRUCTED | MBEDTLS_ASN1_SEQUENCE));

	MBEDTLS_ASN1_CHK_ADD(len, mbedtls_asn1_write_len(&p, buf, 0)); // unused bits
	MBEDTLS_ASN1_CHK_ADD(len, mbedtls_asn1_write_len(&p, buf, len));
	MBEDTLS_ASN1_CHK_ADD(len, mbedtls_asn1_write_tag(&p, buf, MBEDTLS_ASN1_BIT_STRING));

	if (len <= FTPM_EK_CSR_SIG_SIZE) {
		memcpy(sig, p, len);
		*sig_len = len;
	} else {
		rc = TEE_ERROR_SHORT_BUFFER;
	}

	mbedtls_mpi_free(&r);
	mbedtls_mpi_free(&s);

	return rc;
}

static TEE_Result resign_ek_csr(uint8_t *ek_csr_ptr, size_t *ek_csr_len)
{
	ek_csr_t ek_csr;
	uint8_t *csr_ptr, *csr_end;
	size_t csr_len;
	uint8_t *hash_buf = NULL;
	size_t hash_len;
	uint8_t *oid_sig_buf = NULL;
	uint8_t *oid_sig_buf_update = NULL;
	uint32_t oid_sig_len = FTPM_EK_CSR_SIG_SIZE + 20;
	uint32_t final_oid_sig_len = 0;
	uint8_t *sig_buf = NULL;
	uint32_t sig_len[1];
	uint32_t len_diff = 0;
	char oid_sig_alg_ecdsa_sha256[] = MBEDTLS_OID_ECDSA_SHA256;
	TEE_Result rc = TEE_SUCCESS;
	int ret;

	if (!ek_csr_ptr || !ek_csr_len[0])
		return TEE_ERROR_NO_DATA;

	csr_len = *ek_csr_len;
	csr_ptr = ek_csr_ptr;
	csr_end = csr_ptr + csr_len;

	/* Allocate buffers. */
	hash_buf = calloc(1, TEE_SHA256_HASH_SIZE);
	if (!hash_buf) {
		rc = TEE_ERROR_OUT_OF_MEMORY;
		goto out;
	}

	oid_sig_buf = calloc(1, oid_sig_len);
	if (!oid_sig_buf) {
		rc = TEE_ERROR_OUT_OF_MEMORY;
		goto out;
	}

	sig_buf = calloc(1, FTPM_EK_CSR_SIG_SIZE);
	if (!sig_buf) {
		rc = TEE_ERROR_OUT_OF_MEMORY;
		goto out;
	}

	ek_csr.csr_head = csr_ptr;
	ek_csr.csr_total_len = csr_len;

	/* Certification Request */
	ret = mbedtls_asn1_get_tag(&csr_ptr, csr_end, &csr_len,
				   MBEDTLS_ASN1_CONSTRUCTED | MBEDTLS_ASN1_SEQUENCE);
	if (ret != 0) {
		rc = TEE_ERROR_BAD_FORMAT;
		goto out;
	}

	ek_csr.tbs_ptr = csr_ptr;

	/* Certificate Request Info */
	ret = mbedtls_asn1_get_tag(&csr_ptr, csr_end, &csr_len,
				   MBEDTLS_ASN1_CONSTRUCTED | MBEDTLS_ASN1_SEQUENCE);
	if (ret != 0) {
		rc = TEE_ERROR_BAD_FORMAT;
		goto out;
	}

	ek_csr.tbs_len = csr_len + 4;	// ASN1 SEQUENCE offset

	/* Calculate the hash of TBS */
	hash_len = TEE_SHA256_HASH_SIZE;
	rc = calc_csr_tbs_hash(ek_csr.tbs_ptr, ek_csr.tbs_len,
			      hash_buf, &hash_len);
	if (rc != TEE_SUCCESS)
		goto out;

	/* Sign EK CSR */
	sig_len[0] = FTPM_EK_CSR_SIG_SIZE;
	rc = sign_csr_digest(hash_buf, hash_len,
			     sig_buf, &sig_len[0]);

	/* Update Signature Algorithm and Signature. */
	csr_ptr += csr_len;
	ek_csr.sig_len = ek_csr.csr_total_len - ek_csr.tbs_len - 4;
	memset(csr_ptr, 0, ek_csr.sig_len);

	/* Len of Sig_alg and Sig = header len(4) + OID len of Ecdsa_sha256(8) + Sig_len */
	oid_sig_buf_update = oid_sig_buf + 4 + sizeof(oid_sig_alg_ecdsa_sha256) - 1 + sig_len[0];

	/* Update signature. */
	MBEDTLS_ASN1_CHK_ADD(final_oid_sig_len,
			     mbedtls_asn1_write_raw_buffer(&oid_sig_buf_update,
							   oid_sig_buf,
							   (const unsigned char *) sig_buf,
							   sig_len[0]));
	/* Update OID of Sig_alg (ECDSA_SHA256). */
	MBEDTLS_ASN1_CHK_ADD(final_oid_sig_len,
			     mbedtls_asn1_write_oid(&oid_sig_buf_update,
						    oid_sig_buf,
						    oid_sig_alg_ecdsa_sha256,
						    sizeof(oid_sig_alg_ecdsa_sha256) - 1));

	/* Update len of Sig_alg. */
	MBEDTLS_ASN1_CHK_ADD(final_oid_sig_len,
			     mbedtls_asn1_write_len(&oid_sig_buf_update,
						    oid_sig_buf,
						    sizeof(oid_sig_alg_ecdsa_sha256) - 1 + 2));

	/* Update header of ASN1 SEQ. */
	MBEDTLS_ASN1_CHK_ADD(final_oid_sig_len,
			     mbedtls_asn1_write_tag(&oid_sig_buf_update,
						    oid_sig_buf,
						    MBEDTLS_ASN1_CONSTRUCTED | MBEDTLS_ASN1_SEQUENCE));

	memcpy(csr_ptr, oid_sig_buf, final_oid_sig_len);

	/* Update the CSR length. */
	if (ek_csr.sig_len > final_oid_sig_len) {
		len_diff = ek_csr.sig_len - final_oid_sig_len;
		ek_csr.csr_total_len -= len_diff;
	} else if (ek_csr.sig_len < final_oid_sig_len) {
		len_diff = final_oid_sig_len - ek_csr.sig_len;
		ek_csr.csr_total_len += len_diff;
	}

	if (len_diff != 0) {
		/* Update the CSR length. */
		uint8_t *buf = ek_csr.csr_head;
		uint8_t *p = buf + 4;	// ASN1 SEQUENCE offset
		uint32_t len = 0;

		MBEDTLS_ASN1_CHK_ADD(len, mbedtls_asn1_write_len(&p, buf, ek_csr.csr_total_len - 4));
		MBEDTLS_ASN1_CHK_ADD(len, mbedtls_asn1_write_tag(&p, buf, MBEDTLS_ASN1_CONSTRUCTED | MBEDTLS_ASN1_SEQUENCE));

		if (len != 4) {
			rc = TEE_ERROR_SHORT_BUFFER;
			goto out;
		}
	}

	*ek_csr_len = ek_csr.csr_total_len;

out:
	if (!hash_buf)
		free(hash_buf);
	if (!oid_sig_buf)
		free(oid_sig_buf);
	if (!sig_buf)
		free(sig_buf);

	return rc;
}

static TEE_Result sign_ek_csr(uint32_t ptypes,
			      TEE_Param params[TEE_NUM_PARAMS])
{
	TEE_Result rc = TEE_SUCCESS;
	uint32_t exp_pt;

	/* Validate the input parameters. */
	exp_pt = TEE_PARAM_TYPES(TEE_PARAM_TYPE_MEMREF_INOUT,
				 TEE_PARAM_TYPE_NONE,
				 TEE_PARAM_TYPE_NONE,
				 TEE_PARAM_TYPE_NONE);
	if (exp_pt != ptypes)
		return TEE_ERROR_BAD_PARAMETERS;

	if (FTPM_EK_CSR_BUF_SIZE < params[0].memref.size)
		return TEE_ERROR_BAD_PARAMETERS;

	resign_ek_csr(params[0].memref.buffer, &params[0].memref.size);

	return rc;
}

static TEE_Result query_pta(uint32_t cmd_id,
			    uint32_t data_len,
			    uint32_t ptypes,
			    TEE_Param params[TEE_NUM_PARAMS])
{
	uint32_t exp_pt;
	uint32_t data_out_pt0, data_out_pt1, data_out_pt2;
	TEE_Param pta_params[TEE_NUM_PARAMS] = { };
	TEE_Result rc = TEE_SUCCESS;

	if (cmd_id == FTPM_HELPER_PTA_CMD_QUERY_PROV_MODE) {
		data_out_pt0 = TEE_PARAM_TYPE_VALUE_OUTPUT;
		data_out_pt1 = TEE_PARAM_TYPE_VALUE_OUTPUT;
		data_out_pt2 = TEE_PARAM_TYPE_VALUE_OUTPUT;
	} else {
		data_out_pt0 = TEE_PARAM_TYPE_MEMREF_OUTPUT;
		data_out_pt1 = TEE_PARAM_TYPE_NONE;
		data_out_pt2 = TEE_PARAM_TYPE_NONE;
	}

	/* Validate the input parameters. */
	exp_pt = TEE_PARAM_TYPES(data_out_pt0,
				 data_out_pt1,
				 data_out_pt2,
				 TEE_PARAM_TYPE_NONE);

	if (exp_pt != ptypes)
		return TEE_ERROR_BAD_PARAMETERS;

	if (data_out_pt0 == TEE_PARAM_TYPE_MEMREF_OUTPUT &&
	    data_len != params[0].memref.size)
		return TEE_ERROR_BAD_PARAMETERS;

	if (data_out_pt0 == TEE_PARAM_TYPE_MEMREF_OUTPUT) {
		pta_params[0].memref.buffer = params[0].memref.buffer;
		pta_params[0].memref.size = params[0].memref.size;
	}

	rc = invoke_ftpm_helper_pta(cmd_id,
				    exp_pt, pta_params);
	if (rc != TEE_SUCCESS)
		return rc;

	if (data_out_pt0 == TEE_PARAM_TYPE_MEMREF_OUTPUT) {
		params[0].memref.size = pta_params[0].memref.size;
	} else {
		params[0].value.a = pta_params[0].value.a;
		params[1].value.a = pta_params[1].value.a;
		params[2].value.a = pta_params[2].value.a;
	}

	return rc;
}

#if defined(CFG_JETSON_FTPM_HELPER_INJECT_EPS)
static TEE_Result ta_inject_eps(uint32_t ptypes, TEE_Param params[TEE_NUM_PARAMS])
{
	uint32_t exp_pt;

	/* Validate the input parameters. */
	exp_pt = TEE_PARAM_TYPES(TEE_PARAM_TYPE_MEMREF_INPUT,
				 TEE_PARAM_TYPE_NONE,
				 TEE_PARAM_TYPE_NONE,
				 TEE_PARAM_TYPE_NONE);
	if (exp_pt != ptypes)
		return TEE_ERROR_BAD_PARAMETERS;

	if (params[0].memref.size != FTPM_HELPER_TA_EPS_BYTES)
		return TEE_ERROR_BAD_PARAMETERS;

	return invoke_ftpm_helper_pta(FTPM_HELPER_PTA_CMD_INJECT_EPS, exp_pt, params);
}
#else
static TEE_Result ta_inject_eps(uint32_t __unused ptypes,
				TEE_Param __unused params[TEE_NUM_PARAMS])
{
	return TEE_ERROR_NOT_SUPPORTED;
}
#endif

TEE_Result TA_CreateEntryPoint(void)
{
	TEE_Result rc = TEE_SUCCESS;

	return rc;
}

void TA_DestroyEntryPoint(void)
{
}

TEE_Result TA_OpenSessionEntryPoint(uint32_t __unused param_types,
				    TEE_Param __unused params[TEE_NUM_PARAMS],
				    void __unused **session)
{
	return TEE_SUCCESS;
}

void TA_CloseSessionEntryPoint(void __unused *session)
{
}

TEE_Result TA_InvokeCommandEntryPoint(void __unused *session,
				      uint32_t __unused cmd,
				      uint32_t __unused param_types,
				      TEE_Param __unused params[TEE_NUM_PARAMS])
{
	switch (cmd) {
	case FTPM_HELPER_TA_CMD_QUERY_SN:
		return query_pta(FTPM_HELPER_PTA_CMD_QUERY_SN,
				 FTPM_HELPER_TA_SN_LENGTH,
				 param_types, params);
	case FTPM_HELPER_TA_CMD_QUERY_ECID:
		return query_pta(FTPM_HELPER_PTA_CMD_QUERY_ECID,
				 FTPM_HELPER_TA_ECID_LENGTH,
				 param_types, params);
	case FTPM_HELPER_TA_CMD_QUERY_PROV_MODE:
		return query_pta(FTPM_HELPER_PTA_CMD_QUERY_PROV_MODE,
				 0, param_types, params);
	case FTPM_HELPER_TA_CMD_GET_RSA_EK_CERT:
		return query_pta(FTPM_HELPER_PTA_CMD_GET_RSA_EK_CERT,
				 FTPM_EK_CERT_BUF_SIZE, param_types, params);
	case FTPM_HELPER_TA_CMD_GET_EC_EK_CERT:
		return query_pta(FTPM_HELPER_PTA_CMD_GET_EC_EK_CERT,
				 FTPM_EK_CERT_BUF_SIZE, param_types, params);
	case FTPM_HELPER_TA_CMD_GET_SID_CERT:
		return query_pta(FTPM_HELPER_PTA_CMD_GET_SID_CERT,
				 FTPM_EK_CERT_BUF_SIZE, param_types, params);
	case FTPM_HELPER_TA_CMD_GET_FW_ID_CERT:
		return query_pta(FTPM_HELPER_PTA_CMD_GET_FW_ID_CERT,
				 FTPM_EK_CERT_BUF_SIZE, param_types, params);
	case FTPM_HELPER_TA_CMD_GET_RSA_EK_CSR:
		return query_pta(FTPM_HELPER_PTA_CMD_GET_RSA_EK_CSR,
				 FTPM_EK_CERT_BUF_SIZE, param_types, params);
	case FTPM_HELPER_TA_CMD_GET_EC_EK_CSR:
		return query_pta(FTPM_HELPER_PTA_CMD_GET_EC_EK_CSR,
				 FTPM_EK_CERT_BUF_SIZE, param_types, params);
	case FTPM_HELPER_TA_CMD_SIGN_EK_CSR:
		return sign_ek_csr(param_types, params);
	case FTPM_HELPER_TA_CMD_INJECT_EPS:
		return ta_inject_eps(param_types, params);
	default:
		return TEE_ERROR_NOT_SUPPORTED;
	}
}
#else /* CFG_JETSON_FTPM_HELPER_PTA */
TEE_Result TA_CreateEntryPoint(void)
{
	return TEE_ERROR_NOT_SUPPORTED;
}

void TA_DestroyEntryPoint(void)
{
}

TEE_Result TA_OpenSessionEntryPoint(uint32_t __unused param_types,
				    TEE_Param __unused params[TEE_NUM_PARAMS],
				    void __unused **session)
{
	return TEE_ERROR_NOT_SUPPORTED;
}

void TA_CloseSessionEntryPoint(void __unused *session)
{
}

TEE_Result TA_InvokeCommandEntryPoint(void __unused *session,
				      uint32_t __unused cmd,
				      uint32_t __unused param_types,
				      TEE_Param __unused params[TEE_NUM_PARAMS])
{
	return TEE_ERROR_NOT_SUPPORTED;
}
#endif /* CFG_JETSON_FTPM_HELPER_PTA */
