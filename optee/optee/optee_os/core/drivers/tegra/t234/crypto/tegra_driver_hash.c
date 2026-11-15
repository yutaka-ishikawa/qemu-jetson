// SPDX-License-Identifier: BSD-2-Clause
/*
 * Copyright (c) 2023, NVIDIA CORPORATION & AFFILIATES.
 */

#include <crypto/crypto.h>
#include <crypto/crypto_impl.h>
#include <drvcrypt.h>
#include <drvcrypt_hash.h>
#include <initcall.h>
#include <stdlib.h>
#include <tee_api_types.h>
#include <tegra_driver_se.h>
#include <tegra_driver_srv_intf.h>
#include <tegra_se_ccc.h>
#include <trace.h>
#include <types_ext.h>
#include <utee_defines.h>
#include <util.h>

static TEE_Result tegra_hash_initialize(struct crypto_hash_ctx *ctx)
{
	return tegra_ccc_hash_initialize(ctx);
}

static TEE_Result tegra_hash_update(
			struct crypto_hash_ctx *ctx,
			const uint8_t *data, size_t len)
{
	return tegra_ccc_hash_update(ctx, data, len);
}

static TEE_Result tegra_hash_final(
			struct crypto_hash_ctx *ctx,
			uint8_t *digest, size_t len)
{
	return tegra_ccc_hash_final(ctx, digest, len);
}

static void tegra_hash_free(struct crypto_hash_ctx *ctx)
{
	tegra_ccc_hash_free(ctx);
}

static void tegra_hash_copy_state(
			struct crypto_hash_ctx *dst_ctx,
			struct crypto_hash_ctx *src_ctx)
{
	tegra_ccc_hash_copy_state(dst_ctx, src_ctx);
}

static const struct crypto_hash_ops hash_ops = {
	.init = &tegra_hash_initialize,
	.update = &tegra_hash_update,
	.final = &tegra_hash_final,
	.free_ctx = &tegra_hash_free,
	.copy_state = &tegra_hash_copy_state,
};

static TEE_Result tegra_hash_allocate(
			struct crypto_hash_ctx **ctx,
			uint32_t algo)
{
	TEE_Result res = TEE_ERROR_NOT_IMPLEMENTED;

	switch (algo)
	{
		case TEE_ALG_SHA1:
			res = tegra_hash_alloc_ctx(ctx, TEGRA_ALG_SHA1);
			break;

		case TEE_ALG_SHA224:
			res = tegra_hash_alloc_ctx(ctx, TEGRA_ALG_SHA224);
			break;

		case TEE_ALG_SHA256:
			res = tegra_hash_alloc_ctx(ctx, TEGRA_ALG_SHA256);
			break;

		case TEE_ALG_SHA384:
			res = tegra_hash_alloc_ctx(ctx, TEGRA_ALG_SHA384);
			break;

		case TEE_ALG_SHA512:
			res = tegra_hash_alloc_ctx(ctx, TEGRA_ALG_SHA512);
			break;

		default:
			return TEE_ERROR_NOT_IMPLEMENTED;
	}

	(*ctx)->ops = &hash_ops;
	return res;
}

/* Register the Tegra SE hash processing driver in the crypto API.
 * During OP-TEE initialization this sets up "*crypt_algo" for
 * CRYPTO_HASH with Tegra SE.
 */
TEE_Result tegra_register_hash(void)
{
	return drvcrypt_register_hash(&tegra_hash_allocate);
}

driver_init_late(tegra_register_hash);
