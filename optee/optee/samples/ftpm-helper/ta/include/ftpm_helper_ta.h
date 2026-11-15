/*
 * Copyright (c) 2023-2024, NVIDIA Corporation & AFFILIATES. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef __FTPM_HELPER_TA_H__
#define __FTPM_HELPER_TA_H__

/*
 * Each trusted app UUID should have a unique UUID that is
 * generated from a UUID generator such as
 * https://www.uuidgenerator.net/
 *
 * UUID : {a6a3a74a-77cb-433a-990c-1dfb8a3fbc4c}
 */
#define FTPM_HELPER_TA_UUID \
	{ 0xa6a3a74a, 0x77cb, 0x433a, \
		{ 0x99, 0x0c, 0x1d, 0xfb, 0x8a, 0x3f, 0xbc, 0x4c} }

#define FTPM_HELPER_TA_ECID_LENGTH	8U
#define FTPM_HELPER_TA_SN_LENGTH	10U
#define FTPM_HELPER_TA_EPS_BITS		512U
#define FTPM_HELPER_TA_EPS_BYTES	(FTPM_HELPER_TA_EPS_BITS / 8U)

/* EK Certificate buffer size */
#define FTPM_EK_CERT_BUF_SIZE			2048U
/* EK CSR buffer size */
#define FTPM_EK_CSR_BUF_SIZE			2048U

/* fTPM Provisioning mode */
#define FTPM_PROV_MODE_OFFLINE			0xff00000a
#define FTPM_PROV_MODE_ONLINE			0xff00000b
#define FTPM_PROV_MODE_UNKNOWN			0xff00000c

/*
 * FTPM_HELPER_TA_CMD_QUERY_SN - Query the device serial number
 * param[0] out (memref) data buffer and size
 * param[1] unused
 * param[2] unused
 * param[3] unused
 */
#define FTPM_HELPER_TA_CMD_QUERY_SN		0xff000001

/*
 * FTPM_HELPER_TA_CMD_QUERY_ECID - Query the device ECID
 * param[0] out (memref) data buffer and size
 * param[1] unused
 * param[2] unused
 * param[3] unused
 */
#define FTPM_HELPER_TA_CMD_QUERY_ECID		0xff000002

/*
 * FTPM_HELPER_TA_CMD_QUERY_PROV_MODE - Query the provisioning mode
 * param[0] out (value) a: The defined value of provisioning scheme.
 * param[1] out (value) a: The version major number.
 * param[2] out (value) a: The version minor number.
 * param[3] unused
 */
#define FTPM_HELPER_TA_CMD_QUERY_PROV_MODE	0xff000003

/*
 * FTPM_HELPER_TA_CMD_GET_RSA_EK_CERT - Get the fTPM RSA EK Certificate
 * param[0] out (memref) data buffer and size
 * param[1] unused
 * param[2] unused
 * param[3] unused
 */
#define FTPM_HELPER_TA_CMD_GET_RSA_EK_CERT	0xff000004

/*
 * FTPM_HELPER_TA_CMD_GET_EC_EK_CERT - Get the fTPM EC EK Certificate
 * param[0] out (memref) data buffer and size
 * param[1] unused
 * param[2] unused
 * param[3] unused
 */
#define FTPM_HELPER_TA_CMD_GET_EC_EK_CERT	0xff000005

/*
 * FTPM_HELPER_TA_CMD_GET_SID_CERT - Get the Silicon ID Certificate
 * param[0] out (memref) data buffer and size
 * param[1] unused
 * param[2] unused
 * param[3] unused
 */
#define FTPM_HELPER_TA_CMD_GET_SID_CERT		0xffff0006

/*
 * FTPM_HELPER_TA_CMD_GET_FW_ID_CERT - Get the Firmware ID Certificate
 * param[0] out (memref) data buffer and size
 * param[1] unused
 * param[2] unused
 * param[3] unused
 */
#define FTPM_HELPER_TA_CMD_GET_FW_ID_CERT	0xffff0007

/*
 * FTPM_HELPER_TA_CMD_GET_RSA_EK_CSR - Get the fTPM RSA EK CSR
 * param[0] out (memref) data buffer and size
 * param[1] unused
 * param[2] unused
 * param[3] unused
 */
#define FTPM_HELPER_TA_CMD_GET_RSA_EK_CSR	0xffff0008

/*
 * FTPM_HELPER_TA_CMD_GET_EC_EK_CSR - Get the fTPM EC EK CSR
 * param[0] out (memref) data buffer and size
 * param[1] unused
 * param[2] unused
 * param[3] unused
 */
#define FTPM_HELPER_TA_CMD_GET_EC_EK_CSR	0xffff0009

/*
 * FTPM_HELPER_TA_CMD_SIGN_EK_CSR - Receive the EK CSR and sign it
 * param[0] in/out (memref) data buffer and size
 * param[1] unused
 * param[2] unused
 * param[3] unused
 */
#define FTPM_HELPER_TA_CMD_SIGN_EK_CSR		0xffff000a

/*
 * FTPM_HELPER_TA_CMD_INJECT_EPS - Inject an EPS into fTPM
 * param[0] in  (memref) the buffer contains EPS
 * param[1] unused
 * param[2] unused
 * param[3] unused
 */
#define FTPM_HELPER_TA_CMD_INJECT_EPS		0xff00000b

#endif /* __FTPM_HELPER_TA_H__ */
