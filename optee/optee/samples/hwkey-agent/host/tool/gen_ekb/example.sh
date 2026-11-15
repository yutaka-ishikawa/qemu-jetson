#!/bin/bash

# Copyright (c) 2023-2024, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: BSD-2-Clause

# [T234 example]
# Fill your OEM_K1 fuse key value
# echo "0000000000000000000000000000000000000000000000000000000000000000" > oem_k1.key

# Generate user-defined symmetric key files
# A random generate key is recommended for production, and a specified key is recommended for testing
# For each key, there are reference examples for generating random key and specifying keys.
# openssl rand -rand /dev/urandom -hex 32 > sym_t234.key    # kernel/kernel-dtb encryption key
# echo "0000000000000000000000000000000000000000000000000000000000000000" > sym_t234.key
# openssl rand -rand /dev/urandom -hex 16 > sym2_t234.key   # disk encryption key
# echo "00000000000000000000000000000000" > sym2_t234.key
# openssl rand -rand /dev/urandom -hex 16 > auth_t234.key   # uefi variables authentication key
# echo "00000000000000000000000000000000" > auth_t234.key

python3 gen_ekb.py -chip t234 -oem_k1_key oem_k1.key \
        -in_sym_key sym_t234.key \
        -in_sym_key2 sym2_t234.key \
        -in_auth_key auth_t234.key \
        -in_ftpm_sn 00000000000000000000 \
        -in_ftpm_eps_seed ftpm_eps_seed_file \
        -in_ftpm_rsa_ek_cert ftpm_rsa_ek_cert.der \
        -in_ftpm_ec_ek_cert ftpm_ec_ek_cert.der \
        -in_sid_cert sid_cert.der \
        -in_ftpm_rsa_ek_csr ftpm_rsa_ek_csr.der \
        -in_ftpm_ec_ek_csr ftpm_ec_ek_csr.der \
        -out eks_t234.img
