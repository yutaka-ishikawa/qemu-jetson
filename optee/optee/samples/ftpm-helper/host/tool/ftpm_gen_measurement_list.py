#!/usr/bin/env python3

# SPDX-FileCopyrightText: Copyright (c) 2025, NVIDIA Corporation.  All Rights Reserved.
# SPDX-License-Identifier: BSD-2-Clause

"""
ftpm_gen_measurement_list.py:
    Generate measurement list of PCR to be monitored in measured boot flow.
    PCR0 only for now.

Usage:
    python ftpm_gen_measurement_list.py \
        --platform <platform> \
        --mb2_image <MB2_image> \
        --secure_os_image <TOS_image> \
        --uefi_image <UEFI_image>

Example:
    python ftpm_gen_measurement_list.py \
        --platform t234 \
        --mb2_image mb2_t234_with_mb2_cold_boot_bct_MB2_sigheader_encrypt.bin.signed \
        --secure_os_image tos-optee_t234_sigheader_encrypt.img.signed \
        --uefi_image uefi_jetson_with_dtb_aligned_blob_w_bin_sigheader_encrypt.bin.signed

    output:
    INFO:
    SHA256 PCR value: <SHA 256 value>
    INFO:
    SHA384 PCR value: <SHA 384 value>
    INFO:
    SHA512 PCR value: <SHA 512 value>
"""

import hashlib
import sys
from typing import List
import binascii
import os
import logging
import argparse

# Configure global constants
PLATFORM_OFFSETS = {
    "t234": {
        "magic": 0x1400,
        "hash": 0x1460
    }
}

BINARY_MAGIC_ORDER = ["MB2B", "TOSB", "CPBL"]  # Expected order of binary magic strings
SUPPORTED_ALGORITHMS = ["sha256", "sha384", "sha512"]  # Supported hashing algorithms
UEFI_SUPPORTED_MEASUREMENT = ["sha256", "sha384"]  # UEFI-supported hash measurements
EV_SEPARATOR_DATA = bytes.fromhex("00000000")  # Defined by TCG PC Client Platform Firmware Profile Spec

def configure_logging() -> None:
    """
    Configure logging.
    """
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")

def validate_files(files: List[str], platform: str) -> None:
    """
    Validates the existence and order of specified files.

    Args:
        files (List[str]): List of file paths to validate.
        platform (str): Target platform.

    Raises:
        ValueError: If any file doesn't exist or is not accessible.
    """
    for i, f in enumerate(files):
        if not os.path.isfile(f):
            raise ValueError(f"File '{f}' does not exist or is not accessible.")
        magic = read_magic_from_file(f, platform)
        if magic != BINARY_MAGIC_ORDER[i]:
            raise ValueError(f"'{f}' should have magic '{BINARY_MAGIC_ORDER[i]}', but found '{magic}'")

def read_magic_from_file(file: str, platform: str) -> str:
    """
    Read the magic string from a file at a specified offset.

    Args:
        file (str): Path to the file.
        platform (str): Target platform.

    Returns:
        str: The magic string.
    """
    with open(file, 'rb') as f:
        f.seek(PLATFORM_OFFSETS[platform]["magic"])
        magic = f.read(4).decode("utf-8")
        logging.debug(f"Read magic '{magic}' from file '{file}'.")
        return magic

def read_hash_from_file(file: str, platform: str) -> bytes:
    """
    Read the SHA-512 hash from a file at a specified offset.

    Args:
        file (str): Path to the file.
        platform (str): Target platform.

    Returns:
        bytes: SHA-512 hash.
    """
    with open(file, 'rb') as f:
        f.seek(PLATFORM_OFFSETS[platform]["hash"])
        raw_data = f.read(hashlib.sha512().digest_size)
        if len(raw_data) != hashlib.sha512().digest_size:
            raise ValueError(f"File '{file}' has insufficient data for hash calculation.")
        logging.debug(f"Read SHA-512 hash from file '{file}'.")
        return raw_data

def calculate_pcr(files: List[str], algorithm: str, platform: str) -> str:
    """
    Calculate the PCR value by hashing measurement of binary files with a specified algorithm.

    Args:
        files (List[str]): List of binary file paths.
        algorithm (str): Supported hash algorithm.
        platform (str): Target platform.

    Returns:
        str: The PCR value.
    """
    if algorithm not in SUPPORTED_ALGORITHMS:
        raise ValueError(f"Unsupported hash algorithm '{algorithm}'")

    pcr_result = bytearray(hashlib.new(algorithm).digest_size)  # Initialize PCR buffer to 0

    for f in files:
        try:
            hash_value = read_hash_from_file(f, platform)
            # If UEFI-supported hash algorithm, hash the SHA-512 value
            # This is to ensure the hash value is the same as the one calculated by MB2
            if algorithm in UEFI_SUPPORTED_MEASUREMENT:
                hash_value = hashlib.new(algorithm, hash_value).digest()

            pcr_result = hashlib.new(algorithm, pcr_result + hash_value).digest()

        except Exception as e:
            raise ValueError(f"Error processing file '{f}': {e}")

    if algorithm in UEFI_SUPPORTED_MEASUREMENT:
        separator_event = hashlib.new(algorithm, EV_SEPARATOR_DATA).digest()
        pcr_result = hashlib.new(algorithm, pcr_result + separator_event).digest()

    return binascii.hexlify(pcr_result).upper().decode()

def main() -> None:
    """
    Main function to orchestrate the PCR generation process.
    """
    parser = argparse.ArgumentParser(
        description='Generate measured boot list of PCR to be monitored in measured boot flow'
    )

    # Add platform argument
    parser.add_argument(
        '--platform',
        required=True,
        choices=['t234'],
        help='Target platform.'
    )

    # Add arguments for MB2, Secure OS, and UEFI images
    parser.add_argument(
        '--mb2_image',
        required=True,
        help='MB2 image name.'
    )
    parser.add_argument(
        '--secure_os_image',
        required=True,
        help='The image includes ATF, OPTEE, pseudo TAs, and all early TAs such as fTPM.'
    )
    parser.add_argument(
        '--uefi_image',
        required=True,
        help='UEFI image name.'
    )

    args = parser.parse_args()

    # Get platform
    platform = args.platform

    # Collect files into a list
    mb2_image = args.mb2_image
    secure_os_image = args.secure_os_image
    uefi_image = args.uefi_image
    files = [mb2_image, secure_os_image, uefi_image]

    # Configure logging settings for the tool
    configure_logging()

    # Validate the existence and order of all image files
    validate_files(files, platform)

    # Calculate PCR values for all supported hash algorithms
    for algorithm in SUPPORTED_ALGORITHMS:
        try:
            pcr_value = calculate_pcr(files, algorithm, platform)
            logging.info(f"\n{algorithm.upper()} PCR value: {pcr_value}")
        except ValueError as e:
            logging.error(f"Error calculating PCR: {e}")

if __name__ == "__main__":
    main()

