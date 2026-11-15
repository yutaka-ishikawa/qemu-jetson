#!/bin/bash

# Copyright (c) 2024, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: BSD-2-Clause

#
# Required Python modules:
#	sudo apt-get update
#	sudo apt-get install python3-pip
# 	python3 -m pip install asn1crypto (version 1.5.1)
#	python3 -m pip install oscrypto (version 1.3.0)
#

set -e

# Place to store local configuration files
CONF_PATH="./conf"

# Place to store the local output files (e.g. Silicon ID certificates)
CA_OUT_PATH="./ca_out"

# The prefix of the Silicon ID Cert file name: sid_cert-${SN}
SID_CERT_FILE_PREFIX="sid_cert"

CA_SIM_PYTHON_SCRIPT="./ftpm_manufacturer_ca_sign_sid_csr.py"

# fTPM Manufacturer CA certificates (optional)
#   This is for simulation purposes only.
ROOT_CA_PRIV_KEY="${CA_OUT_PATH}/root_ca_test_priv_key.pem"
ROOT_CA_CONF="${CONF_PATH}/ftpm_root_ca_sim.config"
ROOT_CA_CERT="${CA_OUT_PATH}/root_ca_test_cert.pem"
ROOT_CA_CERT_TXT="${CA_OUT_PATH}/root_ca_test_cert.txt"

I_CA_PRIV_KEY="${CA_OUT_PATH}/i_ca_test_priv_key.pem"
I_CA_CONF="${CONF_PATH}/ftpm_i_ca_sim.config"
I_CA_CSR="${CA_OUT_PATH}/i_ca_test_csr.pem"
I_CA_CERT="${CA_OUT_PATH}/i_ca_test_cert.pem"
I_CA_CERT_TXT="${CA_OUT_PATH}/i_ca_test_cert.txt"

SCRIPT_NAME="$(basename "${0}")"

function usage {
	cat << EOM
Usage: ./${SCRIPT_NAME} [OPTIONS]

This script simulates an fTPM manufacturer CA to sign the Device Silicon ID CSR and return the certificate.
The required options:
	-i	The Silicon ID CSR in hex string of DER format. (Must)
	-s	The Serial Number of the Silicon ID CSR. (Must)
	-h	Shows this help.
EOM
}

function gen_simulation_ca() {
	echo "[CA Sim]: === Creating self-signed Root CA Certificate. ==="
	# Generate the root CA private key
	openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 \
			-pkeyopt ec_param_enc:named_curve -out ${ROOT_CA_PRIV_KEY} 2>/dev/null
	# Generate the root CA certificate
	openssl req -batch -verbose -new -sha256 -x509 -days 365 \
			-config ${ROOT_CA_CONF} -key ${ROOT_CA_PRIV_KEY} -out ${ROOT_CA_CERT} 2>/dev/null
	openssl x509 -inform PEM -in ${ROOT_CA_CERT} -text -noout > ${ROOT_CA_CERT_TXT}

	echo "[CA Sim]: === Creating Intermediate CA Certificate. ==="
	# Generate the ICA private key

	# RSA2K key for the ICA
	openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out ${I_CA_PRIV_KEY} 2>/dev/null

	# EC P-256 key for the ICA
	#openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 \
	#		-pkeyopt ec_param_enc:named_curve -out ${I_CA_PRIV_KEY} 2>/dev/null

	# Generate the ICA CSR
	openssl req -sha256 -new -key ${I_CA_PRIV_KEY} -config ${I_CA_CONF} -out ${I_CA_CSR}
	# Sign the ICA CSR
	openssl x509 -in ${I_CA_CSR} -req -keyform PEM -CA ${ROOT_CA_CERT} -CAkey ${ROOT_CA_PRIV_KEY} \
			-CAcreateserial -sha256 -days 365 -extensions ca_ext -extfile ${I_CA_CONF} \
			-out ${I_CA_CERT} 2>/dev/null
	openssl x509 -inform PEM -in ${I_CA_CERT} -text -noout > ${I_CA_CERT_TXT}

	echo "[CA Sim]: === Verifying the CA Certificates ==="
	openssl verify -CAfile ${ROOT_CA_CERT} ${I_CA_CERT} 2>/dev/null

	# Empty separator line
	echo ""
}

function ca_sign_sid_csr() {
	_sid_csr="${1}"
	_prefix_sid_cert_file="${SID_CERT_FILE_PREFIX}-${SN}"

	echo "[CA Sim]: === fTPM Manufacturer CA simulation stage: Signing Silicon ID CSR ==="
	CA_SIGN_CSR_CMD="${CA_SIM_PYTHON_SCRIPT} --out_path ${CA_OUT_PATH} \
				--sid_csr ${_sid_csr} \
				--ca_cert ${I_CA_CERT} \
				--ca_private_key ${I_CA_PRIV_KEY} \
				--sid_cert ${_prefix_sid_cert_file}"

	_sid_cert_file=$(${CA_SIGN_CSR_CMD})

	echo "[CA Sim]: === fTPM Manufacturer CA simulation: The Silicon ID CSR verification passed!!"
	echo "[CA Sim]: === fTPM Manufacturer CA simulation: The Silicon ID Cert generation has done!!"
	# Dump the Silicon ID certificate
	openssl x509 -inform DER -text -noout -in "${_sid_cert_file}"

	# CA verifies the cert chain
	echo "[CA Sim]: === Verify the Silicon ID certificate chain: ${_sid_cert_file} ==="
	_temp_sid_cert_pem_file="${CA_OUT_PATH}/temp_sid_cert.pem"
	openssl x509 -inform DER -outform PEM -in "${_sid_cert_file}" -out "${_temp_sid_cert_pem_file}"
	openssl verify -CAfile ${ROOT_CA_CERT} -untrusted ${I_CA_CERT} -show_chain ${_temp_sid_cert_pem_file} 2>/dev/null

	echo ""
}

mkdir -p ${CA_OUT_PATH}

if [ "${1}" == "" ]; then
	usage
	exit 1
fi

while getopts "hi:s:" OPTION
do
	case $OPTION in
		h)
			usage
			exit 0
		;;
		i)
			SID_CSR_DER_HEX_STR="${OPTARG}"
		;;
		s)
			SN="${OPTARG}"
		;;
		*)
			usage
			exit 1
		;;
	esac
done

if [ "${SN}" == "" ]; then
	usage
	exit 1
fi

if [ ! -f ${ROOT_CA_CERT} ] || [ ! -f ${I_CA_CERT} ] || [ ! -f ${I_CA_PRIV_KEY} ]; then
	gen_simulation_ca
fi

ca_sign_sid_csr ${SID_CSR_DER_HEX_STR}
