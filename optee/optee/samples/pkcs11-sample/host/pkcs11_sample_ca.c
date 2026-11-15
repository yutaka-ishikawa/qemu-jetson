/*
 * Copyright (c) 2024, NVIDIA Corporation & AFFILIATES. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#include <err.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <pkcs11.h>
#include <unistd.h>
#include <ck_debug.h>

/*
 * auth_type enumerates the types of user authentication
 *
 * PIN_AUTH  Pin authentication.
 * ACL_AUTH  ACL authentication.
 */
enum auth_type { PIN_AUTH, ACL_AUTH };

#define ARRAY_SIZE(array)	(sizeof(array) / sizeof(array[0]))

/*
 * Helpers for tests where we must log into the token.
 * These define the genuine PINs and label to be used with the test token.
 */
static CK_UTF8CHAR test_token_so_pin[] = { '1', '2', '3', '4', '5', '6', '7', '8' };
static CK_UTF8CHAR test_token_user_pin[] = { '1', '2', '3', '4', '5' };
static CK_UTF8CHAR test_token_label[] = "PKCS11 TA test token";

/*
 * Some PKCS#11 object resources used in the tests
 */

static CK_BYTE cktest_aes128_iv[16] = {0};

static CK_MECHANISM cktest_aes_cbc_mechanism = {
	CKM_AES_CBC,
	(CK_BYTE_PTR)cktest_aes128_iv, sizeof(cktest_aes128_iv),
};

static CK_MECHANISM cktest_aes_keygen_mechanism = {
	CKM_AES_KEY_GEN, NULL, 0,
};

/*
 * Util to find a slot on which to open a session
 */
static CK_RV close_lib(void)
{
	return C_Finalize(0);
}

/*
 * This function initialize the pkcs11 and find an empty slot.
 * If there are multiple slots available, the last one slot will be used.
 */
static CK_RV init_pkcs11_and_find_empty_slot(CK_SLOT_ID *slot, enum auth_type at)
{
	CK_RV rv = CKR_GENERAL_ERROR;
	CK_SLOT_ID_PTR slots = NULL;
	CK_ULONG count = 0;

	if (!slot)
		return CKR_GENERAL_ERROR;

	rv = C_Initialize(0);
	if (rv)
		return rv;

	rv = C_GetSlotList(CK_TRUE, NULL, &count);
	if (rv != CKR_OK)
		goto out;

	if (count < 1) {
		rv = CKR_GENERAL_ERROR;
		goto out;
	}

	slots = malloc(count * sizeof(CK_SLOT_ID));
	if (!slots) {
		rv = CKR_HOST_MEMORY;
		goto out;
	}

	rv = C_GetSlotList(CK_TRUE, slots, &count);
	if (rv)
		goto out;

	if (at == PIN_AUTH) {
		/* Use the last slot */
		*slot = slots[count - 1];
	} else { /* ACL_AUTH */
		/* Use the second to last slot */
		if (count >= 2)
			*slot = slots[count - 2];
		else
			rv = CKR_GENERAL_ERROR;
	}

out:
	if (slots)
		free(slots);
	if (rv)
		close_lib();

	return rv;
}

/* Login as user, eventually reset user PIN if needed */
static CK_RV init_user_test_token_pin_auth(CK_SLOT_ID slot)
{
	CK_FLAGS session_flags = CKF_SERIAL_SESSION | CKF_RW_SESSION;
	CK_SESSION_HANDLE session = CK_INVALID_HANDLE;
	CK_RV rv = CKR_GENERAL_ERROR;

	rv = C_OpenSession(slot, session_flags, NULL, 0, &session);
	if (rv)
		return rv;

	rv = C_Login(session, CKU_USER, test_token_user_pin,
		     sizeof(test_token_user_pin));
	if (rv == CKR_OK) {
		C_Logout(session);
		C_CloseSession(session);
		return rv;
	}

	rv = C_Login(session, CKU_SO, test_token_so_pin,
		     sizeof(test_token_so_pin));
	if (rv) {
		C_CloseSession(session);
		return rv;
	}

	rv = C_InitPIN(session, test_token_user_pin,
		       sizeof(test_token_user_pin));

	C_Logout(session);
	C_CloseSession(session);

	return rv;
}

#define WRAPPED_TEST_KEY_SIZE	48

static CK_RV pkcs11_wrap_key()
{
	CK_RV rv = CKR_GENERAL_ERROR;
	CK_SLOT_ID slot = 0;
	CK_SESSION_HANDLE session = CK_INVALID_HANDLE;
	CK_FLAGS session_flags = CKF_SERIAL_SESSION | CKF_RW_SESSION;
	CK_OBJECT_HANDLE wrapping_key = CK_INVALID_HANDLE;
	CK_OBJECT_HANDLE key = CK_INVALID_HANDLE;
	CK_OBJECT_HANDLE unwrapped_key = CK_INVALID_HANDLE;
	CK_ATTRIBUTE wrapping_key_template[] = {
		{ CKA_VALUE_LEN, &(CK_ULONG){ 16 }, sizeof(CK_ULONG) },
		{ CKA_WRAP, &(CK_BBOOL){ CK_TRUE }, sizeof(CK_BBOOL) },
		{ CKA_UNWRAP, &(CK_BBOOL){ CK_TRUE }, sizeof(CK_BBOOL) },
		{ CKA_SENSITIVE, &(CK_BBOOL){ CK_TRUE }, sizeof(CK_BBOOL) },
		{ CKA_EXTRACTABLE, &(CK_BBOOL){ CK_FALSE }, sizeof(CK_BBOOL) },
	};
	CK_ATTRIBUTE key_template[] = {
		{ CKA_VALUE_LEN, &(CK_ULONG){ 16 }, sizeof(CK_ULONG) },
		{ CKA_ENCRYPT, &(CK_BBOOL){ CK_TRUE }, sizeof(CK_BBOOL) },
		{ CKA_DECRYPT, &(CK_BBOOL){ CK_TRUE }, sizeof(CK_BBOOL) },
		{ CKA_EXTRACTABLE, &(CK_BBOOL){ CK_TRUE }, sizeof(CK_BBOOL) },
	};
	CK_ATTRIBUTE new_key_template[] = {
		{ CKA_CLASS, &(CK_OBJECT_CLASS){ CKO_SECRET_KEY },
		  sizeof(CK_OBJECT_CLASS) },
		{ CKA_KEY_TYPE,	&(CK_KEY_TYPE){ CKK_GENERIC_SECRET },
		  sizeof(CK_KEY_TYPE) },
		{ CKA_ENCRYPT, &(CK_BBOOL){ CK_TRUE }, sizeof(CK_BBOOL) },
		{ CKA_DECRYPT, &(CK_BBOOL){ CK_TRUE }, sizeof(CK_BBOOL) },
		{ CKA_EXTRACTABLE, &(CK_BBOOL){ CK_TRUE }, sizeof(CK_BBOOL) },
		{ CKA_SENSITIVE, &(CK_BBOOL){ CK_FALSE}, sizeof(CK_BBOOL) },
	};
	CK_BBOOL g_extract = CK_FALSE;
	CK_BBOOL g_sensitive = CK_TRUE;
	CK_BBOOL g_nextract = CK_TRUE;
	CK_BBOOL g_asensitive = CK_TRUE;
	CK_BBOOL g_local = CK_TRUE;
	CK_BBOOL g_token = CK_FALSE;
	CK_BBOOL g_derive = CK_FALSE;
	CK_OBJECT_CLASS g_class = CKO_VENDOR_DEFINED;
	CK_KEY_TYPE g_key_type = CKK_VENDOR_DEFINED;
	uint8_t g_val[WRAPPED_TEST_KEY_SIZE] = { 0 };
	CK_ULONG key_len = 0;
	uint8_t g_unwrapped_val[WRAPPED_TEST_KEY_SIZE] = { 0 };
	CK_ULONG unwrapped_key_len = 0;
	/* Keep last attribute as CKA_VALUE */
	CK_ATTRIBUTE get_template_unwrapped[] = {
		{ CKA_CLASS, &g_class, sizeof(g_class) },
		{ CKA_KEY_TYPE,	&g_key_type, sizeof(g_key_type) },
		{ CKA_EXTRACTABLE, &g_extract, sizeof(g_extract) },
		{ CKA_SENSITIVE, &g_sensitive, sizeof(g_sensitive) },
		{ CKA_NEVER_EXTRACTABLE, &g_nextract, sizeof(g_nextract) },
		{ CKA_ALWAYS_SENSITIVE, &g_asensitive, sizeof(g_asensitive) },
		{ CKA_LOCAL, &g_local, sizeof(g_local) },
		{ CKA_TOKEN, &g_token, sizeof(g_token) },
		{ CKA_DERIVE, &g_derive, sizeof(g_derive) },
		{ CKA_VALUE_LEN, &unwrapped_key_len, sizeof(unwrapped_key_len) },
		{ CKA_VALUE, g_unwrapped_val, sizeof(g_unwrapped_val) },
	};
	CK_ATTRIBUTE get_template[] = {
		{ CKA_VALUE_LEN, &key_len, sizeof(key_len) },
		{ CKA_VALUE, g_val, sizeof(g_val) },
	};
	uint8_t buf[WRAPPED_TEST_KEY_SIZE] = { 0 };
	CK_ULONG size = 0;

	rv = init_pkcs11_and_find_empty_slot(&slot, PIN_AUTH);
	if (rv != CKR_OK) {
		printf("init_pkcs11_and_find_empty_slot failed with rv = 0x%08lx\n", rv);
		return rv;
	}

	rv = C_InitToken(slot, test_token_so_pin, sizeof(test_token_so_pin), test_token_label);
	if (rv != CKR_OK) {
		printf("C_InitToken failed with rv = 0x%08lx\n", rv);
		goto close_lib;
	}

	rv = init_user_test_token_pin_auth(slot);
	if (rv != CKR_OK) {
		printf("init_user_test_token_pin_auth failed with rv = 0x%08lx\n", rv);
		goto close_lib;
	}

	rv = C_OpenSession(slot, session_flags, NULL, 0, &session);
	if (rv != CKR_OK) {
		printf("C_OpenSession failed with rv = 0x%08lx\n", rv);
		goto close_lib;
	}

	/* Generate a wrapping Key */
	rv = C_GenerateKey(session, &cktest_aes_keygen_mechanism,
			   wrapping_key_template,
			   ARRAY_SIZE(wrapping_key_template), &wrapping_key);
	if (rv != CKR_OK) {
		printf("C_GenerateKey generate wrapping key failed with rv = 0x%08lx\n", rv);
		goto close_session;
	}

	/* Generate a application key */
	rv = C_GenerateKey(session, &cktest_aes_keygen_mechanism,
			   key_template, ARRAY_SIZE(key_template),
			   &key);
	if (rv != CKR_OK) {
		printf("C_GenerateKey generate application key failed with rv = 0x%08lx\n", rv);
		goto close_session;
	}

	printf("Test key wrap with AES CBC\n");

	/* Generate random IV */
	rv = C_GenerateRandom(session, cktest_aes128_iv, sizeof(cktest_aes128_iv));
	if (rv != CKR_OK) {
		printf("C_GenerateRandom failed with rv = 0x%08lx\n", rv);
		goto out;
	}

	size = 16;
	/* Warp application key with wrapping key */
	rv = C_WrapKey(session, &cktest_aes_cbc_mechanism, wrapping_key, key,
		       buf, &size);
	if (rv != CKR_OK) {
		printf("C_WrapKey failed with rv = 0x%08lx\n", rv);
		goto out;
	}

	/*
	 * Get the size of the original key which was wrapped in key_len.
	 * This will be compared to the length of the key after unwrapping.
	 */
	rv = C_GetAttributeValue(session, key, get_template,
				 ARRAY_SIZE(get_template));
	if (rv != CKR_OK) {
		printf("C_GetAttributeValue (original key) failed with rv = 0x%08lx\n", rv);
		goto out;
	}

	printf("Test key unwrap with AES CBC\n");

	rv = C_UnwrapKey(session, &cktest_aes_cbc_mechanism, wrapping_key, buf,
			 size, new_key_template, ARRAY_SIZE(new_key_template),
			 &unwrapped_key);
	if (rv != CKR_OK) {
		printf("C_UnwrapKey failed with rv = 0x%08lx\n", rv);
		goto out;
	}

	/*
	 * The key created after unwrapping should have CKA_LOCAL = FALSE,
	 * CKA_ALWAYS_SENSITIVE and CKA_NEVER_EXTRACTABLE as FALSE.
	 * Default value of CKA_EXTRACTABLE if not specified in the template
	 * is TRUE. We have deliberately set CKA_SENSITIVE to false for
	 * both original key and unwrapped_key. This is done to be able to
	 * extract the value of keys and compare them. This is done mainly
	 * for testing. In actual examples, we expect CKA_SENSITIVE of keys
	 * to be wrapped to be TRUE.
	 */
	rv = C_GetAttributeValue(session, unwrapped_key, get_template_unwrapped,
				 ARRAY_SIZE(get_template_unwrapped));
	if ((rv != CKR_OK) ||
	    (unwrapped_key_len !=  key_len) ||
	    (memcmp(g_unwrapped_val, g_val, key_len)) ||
	    (g_class != CKO_SECRET_KEY) ||
	    (g_key_type != CKK_GENERIC_SECRET) ||
	    (g_local != CK_FALSE) ||
	    (g_sensitive != CK_FALSE) ||
	    (g_extract != CK_TRUE) ||
	    (g_asensitive != CK_FALSE) ||
	    (g_nextract != CK_FALSE)) {
		printf("C_GetAttributeValue (unwrapped key) failed with rv = 0x%08lx\n", rv);
		goto out;
	}

	/*
	 * Developers are responsible for the confidentiality of their own keys
	 * and destroy the key object after the key is used. The following shows
	 * how to destroy application key, wrapping key and unwrapped key.
	 */

	rv = C_DestroyObject(session, key);
	if (rv != CKR_OK) {
		printf("C_DestroyObject key failed with rv = 0x%08lx\n", rv);
		goto out;
	}

	rv = C_DestroyObject(session, wrapping_key);
	if (rv != CKR_OK) {
		printf("C_DestroyObject wrapping key failed with rv = 0x%08lx\n", rv);
		goto out;
	}

	rv = C_DestroyObject(session, unwrapped_key);
	if (rv != CKR_OK) {
		printf("C_DestroyObject unwrapped key failed with rv = 0x%08lx\n", rv);
		goto out;
	}

	printf("Test key wrap/unwrap with AES CBC success\n");

out:
close_session:
	C_CloseSession(session);
close_lib:
	close_lib();
	return rv;
}

int main(int argc, char *argv[])
{
	CK_RV rv = CKR_GENERAL_ERROR;

	rv = pkcs11_wrap_key();
	if (rv != CKR_OK)
		printf("PKCS#11 sample code went wrong with rv = 0x%08lx\n", rv);

	return rv;
}
