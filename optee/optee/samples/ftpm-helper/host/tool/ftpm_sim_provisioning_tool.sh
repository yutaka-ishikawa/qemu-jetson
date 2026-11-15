#!/bin/bash

# SPDX-FileCopyrightText: Copyright (c) 2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: BSD-2-Clause

# Depends on tpm2-tools, tpm2-tss
#  $ apt-get install tpm2-tools

set -e

export TPM2TOOLS_TCTI="device:/dev/tpmrm0"

RSA_EK_HANDLE="0x81010001"
EC_EK_HANDLE="0x81010002"
RSA_EK_CERT_HANDLE="0x01c00002"
EC_EK_CERT_HANDLE="0x01c0000a"

OWNER_PW="owner"

TEMP_DIR="./temp_ftpm_sim_prov"
TEMP_CERT_DIR="${TEMP_DIR}/cert"

FTPM_SIM_ROOT_CA_CONF="conf/ftpm_sim_root_ca_csr.config"
FTPM_SIM_I_CA_CONF="conf/ftpm_sim_i_ca_csr.config"
FTPM_SIM_EK_CSR_CONF="conf/ftpm_sim_ek_csr.config"

# TPM EK cert attribute
EK_CERT_ATTR="ppwrite|writedefine|ppread|ownerread|authread|no_da|platformcreate"

function check_config_file() {
    local conf_file="$1"

    if [ ! -f "${conf_file}" ]; then
        echo "[ERROR] Configuration file not found: ${conf_file}"
        return 1
    elif [ ! -r "${conf_file}" ]; then
        echo "[ERROR] Configuration file not readable: ${conf_file}"
        return 1
    elif [ ! -s "${conf_file}" ]; then
        echo "[ERROR] Configuration file is empty: ${conf_file}"
        return 1
    fi
    return 0
}

# Check if the configuration files exist
for conf_file in "${FTPM_SIM_ROOT_CA_CONF}" "${FTPM_SIM_I_CA_CONF}" "${FTPM_SIM_EK_CSR_CONF}"; do
    if ! check_config_file "${conf_file}"; then
        exit 1
    fi
done

function check_ftpm_provision_state() {
	ftpm_prov_st="$(nvftpm-helper-app -i 2>&1 | grep "Invalid provision mode!")"

	if [ -z "${ftpm_prov_st}" ]; then
		echo "Warning: fTPM is already provisioned."
		exit 1
	fi
}

function tpm_ek_prov() {
	local _rsa_ek_alg="rsa"
	local _ec_ek_alg="ecc"
	local _pub_rsa_ek_pem="${TEMP_DIR}/pub_rsa_ek.pem"
	local _pub_ec_ek_pem="${TEMP_DIR}/pub_ec_ek.pem"

	mkdir -p ${TEMP_DIR}

	echo "[fTPM SIM Provisioning][FOR DEV ONLY]: Creating EK."
	tpm2_createek -c ${RSA_EK_HANDLE} -G ${_rsa_ek_alg} -f pem -u ${_pub_rsa_ek_pem} -w ${OWNER_PW} -P ${OWNER_PW}
	tpm2_createek -c ${EC_EK_HANDLE} -G ${_ec_ek_alg} -f pem -u ${_pub_ec_ek_pem} -w ${OWNER_PW} -P ${OWNER_PW}
}

function create_self_signed_root_ca_cert() {
	local _root_ca_priv_key_pem="${TEMP_CERT_DIR}/ftpm_sim_root_ca_priv_key.pem"
	local _root_ca_cert="${TEMP_CERT_DIR}/ftpm_sim_root_ca_cert.pem"

	mkdir -p ${TEMP_CERT_DIR}

	echo "[fTPM SIM Provisioning][FOR DEV ONLY]: Creating self-signed Root CA Certificate."

	# Generate a root CA key pair
	openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out ${_root_ca_priv_key_pem} 2>/dev/null

	# Create self-signed CA cert
	openssl req -batch -verbose -new -sha256 -x509 -days 30 -config ${FTPM_SIM_ROOT_CA_CONF} -key ${_root_ca_priv_key_pem} -out ${_root_ca_cert} 2>/null
}

function create_intermediate_ca_cert() {
	local _i_ca_priv_key_pem="${TEMP_CERT_DIR}/ftpm_sim_i_ca_priv_key.pem"
	local _i_ca_csr="${TEMP_CERT_DIR}/ftpm_sim_i_ca_csr.pem"
	local _i_ca_cert="${TEMP_CERT_DIR}/ftpm_sim_i_ca_cert.pem"
	local _root_ca_cert="${TEMP_CERT_DIR}/ftpm_sim_root_ca_cert.pem"
	local _root_ca_priv_key_pem="${TEMP_CERT_DIR}/ftpm_sim_root_ca_priv_key.pem"

	mkdir -p ${TEMP_CERT_DIR}

	echo "[fTPM SIM Provisioning][FOR DEV ONLY]: Creating Intermediate CA Certificate."

	# Generate an ICA key pair.
	openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out ${_i_ca_priv_key_pem} 2>/dev/null

	# Generate the intermediate CA CSR
	openssl req -sha256 -new -key ${_i_ca_priv_key_pem} -config ${FTPM_SIM_I_CA_CONF} -out ${_i_ca_csr} 2>/dev/null

	# Sign the intermediate CA CSR
	openssl x509 -in ${_i_ca_csr} -req -keyform PEM -CA ${_root_ca_cert} -CAkey ${_root_ca_priv_key_pem} -CAcreateserial -sha256 \
			-days 30 -extensions ca_ext -extfile ${FTPM_SIM_I_CA_CONF} -out ${_i_ca_cert} 2>/dev/null

	# Verify the intermediate CA certificate
	echo "[fTPM SIM Provisioning][FOR DEV ONLY]: Validating the Intermediate CA Certificate."
	openssl verify -CAfile ${_root_ca_cert} ${_i_ca_cert}
}

function create_tpm_ek_cert() {
	local _temp_priv_key="${TEMP_CERT_DIR}/temp_priv_key.pem"
	local _ek_csr="${TEMP_CERT_DIR}/ftpm_sim_${1}_ek_csr.pem"
	local _pub_ek_pem="${TEMP_DIR}/pub_${1}_ek.pem"
	local _i_ca_priv_key_pem="${TEMP_CERT_DIR}/ftpm_sim_i_ca_priv_key.pem"
	local _i_ca_cert="${TEMP_CERT_DIR}/ftpm_sim_i_ca_cert.pem"
	local _root_ca_cert="${TEMP_CERT_DIR}/ftpm_sim_root_ca_cert.pem"
	local _ek_cert="${TEMP_CERT_DIR}/ftpm_sim_${1}_ek_cert.der"
	local _ek_cert_pem="${TEMP_CERT_DIR}/ftpm_sim_${1}_ek_cert.pem"
	local _cert_file_size;
	local _ek_cert_handle;
	local _ek_handle;
	local _ossl_keygen_opt;

	echo "[fTPM SIM Provisioning][FOR DEV ONLY]: Creating TPM ${1} EK Certificates."

	case "${1}" in
	rsa)
	_ek_cert_handle="${RSA_EK_CERT_HANDLE}"
	_ek_handle="${RSA_EK_HANDLE}"
	_ossl_keygen_opt="-algorithm RSA -pkeyopt rsa_keygen_bits:2048"
	;;
	ec)
	_ek_cert_handle="${EC_EK_CERT_HANDLE}"
	_ek_handle="${EC_EK_HANDLE}"
	_ossl_keygen_opt="-algorithm EC -pkeyopt ec_paramgen_curve:P-256 -pkeyopt ec_param_enc:named_curve"
	;;
	esac

	# Create a temp key
	openssl genpkey ${_ossl_keygen_opt} -out ${_temp_priv_key} 2>/dev/null

	# Create CSR with the temp key
	openssl req -sha256 -new -key ${_temp_priv_key} -config ${FTPM_SIM_EK_CSR_CONF} -out ${_ek_csr}

	# Sign CSR and replace the temp key with TPM2 EK
	openssl x509 -in ${_ek_csr} -req -force_pubkey ${_pub_ek_pem} -keyform PEM -CA ${_i_ca_cert} -CAkey ${_i_ca_priv_key_pem} \
			-CAcreateserial -extensions req_ext -extfile ${FTPM_SIM_EK_CSR_CONF} -days 30 -sha256 -outform DER -out ${_ek_cert}

	# Verify the certificate
	echo "[fTPM SIM Provisioning][FOR DEV ONLY]: Verifying TPM ${1} EK Certificate."
	openssl x509 -inform DER -outform PEM -in ${_ek_cert} -out ${_ek_cert_pem}
	openssl verify -CAfile ${_root_ca_cert} -untrusted ${_i_ca_cert} -show_chain ${_ek_cert_pem}

	# Store the certificate into TPM
	echo "[fTPM SIM Provisioning][FOR DEV ONLY]: Writing TPM ${1} EK Certificate."
	_cert_file_size=$(wc -c < ${_ek_cert});
	tpm2_nvdefine ${_ek_cert_handle} -C p -a ${EK_CERT_ATTR} -s ${_cert_file_size}
	tpm2_nvwrite ${_ek_cert_handle} -C p -i ${_ek_cert}
}

function sign_ek_cert () {
	create_self_signed_root_ca_cert
	create_intermediate_ca_cert
	create_tpm_ek_cert "rsa"
	create_tpm_ek_cert "ec"
}

function tpm_take_ownership () {
	echo "[fTPM SIM Provisioning][FOR DEV ONLY]: Taking TPM ownership."

	tpm2_changeauth -c o ${OWNER_PW};
	tpm2_changeauth -c e ${OWNER_PW};
}

function tpm_clear () {
	echo "[fTPM SIM Provisioning][FOR DEV ONLY]: Deprovisioning the fTPM & changing EPS."

	tpm2_changeeps;
	tpm2_clear;

	tpm2_nvundefine -C p ${RSA_EK_CERT_HANDLE}
	tpm2_nvundefine -C p ${EC_EK_CERT_HANDLE}
}

function tpm_dump_caps() {
	local _caps=("persistent" "transient" "nv-index" "loaded-session" "saved-session");

	tpm2_getcap properties-variable;

	for i in "${_caps[@]}"
	do
		echo "-- ${i} --"
		tpm2_getcap handles-${i};
	done
}

case "${1}" in
	ek_prov)
	check_ftpm_provision_state;
	tpm_take_ownership;
	tpm_ek_prov;
	sign_ek_cert;
	;;
	clear)
	check_ftpm_provision_state;
	tpm_clear;
	;;
	dump)
	tpm_dump_caps;
	;;
	*)
	echo "Usage ${0} {ek_prov | clear | dump}"
	echo ""
	echo "Description:"
	echo "  This tool is for fTPM simulation only. It provides the fTPM SIM provisioning"
	echo "  for development only. After the fTPM is provisioned, it can be used as a TPM"
	echo "  simulator for local environment testing and development purpose."
	echo ""
	echo "Warning:"
	echo "  1. This is not a production tool. It shouldn't be used in production environment."
	echo "     The fTPM SIM CA and EK certificates are not signed by a real authority."
	echo "     You shouldn't use them for any business purpose."
	echo "  2. Don't use this script on a fTPM provisioned device. It could cause damages of"
	echo "     the fTPM functionality."
	echo ""
	echo "How to use:"
	echo "  1. Provision the fTPM with the following command:"
	echo "     >./ftpm_sim_provisioning_too.sh ek_prov"
	echo ""
	echo "     The fTPM SIM CA certificates can be found in the file:"
	echo "       fTPM SIM Root CA: temp_ftpm_sim_prov/cert/ftpm_sim_root_ca_cert.pem"
	echo "       fTPM SIM ICA: temp_ftpm_sim_prov/cert/ftpm_sim_i_ca_cert.pem"
	echo ""
	echo "  2. To clear the fTPM contents, use the following command:"
	echo "     >./ftpm_sim_provisioning_tool.sh clear"
	echo ""
	echo "  3. To dump fTPM capabilities:"
	echo "     >./ftpm_sim_provisioning_tool.sh dump"
	echo ""
	echo "Options:"
	echo ""
	echo "* ek_prov: the fTPM SIM provisioning for development only."
	echo ""
	echo "* clear: Clear fTPM contents."
	echo ""
	echo "* dump: Dump fTPM capabilities."
	;;
esac
