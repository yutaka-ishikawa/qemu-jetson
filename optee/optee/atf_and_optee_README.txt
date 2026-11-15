**********************************************************************
NVIDIA Jetson Linux (L4T) OP-TEE Package
**********************************************************************

----------------------------------------------------------------------
Introduction
----------------------------------------------------------------------
This package contains the necessary files and instructions to build a
trusted OS image based on ATF and OP-TEE for these Jetson devices:
- Jetson AGX Orin series

----------------------------------------------------------------------
Prerequisites
----------------------------------------------------------------------
To install build prerequisites, for example, python3-pycryptodome and
python3-pyelftools, in your build machine, refer to:
https://optee.readthedocs.io/en/latest/building/prerequisites.html.

----------------------------------------------------------------------
The python cryptography issue
----------------------------------------------------------------------
When building OP-TEE sources, you may see a python error in sign_encrypt.py like:
"TypeError: public_key() missing 1 required positional argument: 'backend'"

This is because the "cryptography" python package in your build system is too old.
Running the following commands can fix the issue:

sudo apt remove python3-cryptography
pip3 install cryptography

----------------------------------------------------------------------
Placeholders in this document
----------------------------------------------------------------------
This document uses a placeholder, "<platform>", to indicate Jetson platforms.
Its possible value is:
- 234

To build different trusted OS images and DTBs, select the platform value
based on your Jetson board.

----------------------------------------------------------------------
Toolchain
----------------------------------------------------------------------
1. Go to https://developer.nvidia.com/embedded/jetson-linux-archive and download
   the toolchain from Jetson release page for your L4T version.

2. Set the CROSS_COMPILE_AARCH64_PATH environment variable to point to the aarch64
   toolchain.

   For example, if the aarch64 toolchain directory is
   /toolchain/aarch64--glibc--stable-2022.03-1/, set the CROSS_COMPILE_AARCH64_PATH
   with the following command:

   export CROSS_COMPILE_AARCH64_PATH=/toolchain/aarch64--glibc--stable-2022.03-1

3. Set the CROSS_COMPILE_AARCH64 environment variable with the following command:

   export CROSS_COMPILE_AARCH64=/toolchain/aarch64--glibc--stable-2022.03-1/bin/aarch64-buildroot-linux-gnu-

----------------------------------------------------------------------
UEFI StMM Image
----------------------------------------------------------------------
- To build OP-TEE, a UEFI StMM image is required.
  For the Jetson AGX Orin series, the image is usually in the following directory:

  <Linux_for_Tegra>/bootloader/standalonemm_optee_t234.bin

- To notify the OP-TEE build script about the location of the image, set the "UEFI_STMM_PATH"
  environment variable to the following path:

  export UEFI_STMM_PATH=<StMM image path>

----------------------------------------------------------------------
Building the OP-TEE Source Code
----------------------------------------------------------------------
To build the OP-TEE source package, run the the following command:

./optee_src_build.sh -p t<platform> -t

----------------------------------------------------------------------
Building the OP-TEE dtb
----------------------------------------------------------------------
To build OP-TEE dtb, run the following command:

dtc -I dts -O dtb -o ./optee/tegra<platform>-optee.dtb ./optee/tegra<platform>-optee.dts

----------------------------------------------------------------------
Building the ATF Source Code with OP-TEE SPD
----------------------------------------------------------------------
1. Extract the ATF source package.
   mkdir atf_build
   tar -I lbzip2 -C atf_build -xpf atf_src.tbz2

2. Build the ATF source code:
   cd atf_build
   export NV_TARGET_BOARD=generic
   ./nvbuild.sh
   cd ..

----------------------------------------------------------------------
Generating the tos.img with ATF and OP-TEE Images
----------------------------------------------------------------------
1. Get gen_tos_part_img.py file.
   This file is usually in the <Linux_for_Tegra>/nv_tegra/tos-scripts/ of BSP package.

2. Generate the tos.img with the following commands:
   ./gen_tos_part_img.py \
       --monitor ./atf_build/arm-trusted-firmware/generic-t<platform>/tegra/t<platform>/release/bl31.bin \
       --os ./optee/build/t<platform>/core/tee-raw.bin \
       --dtb ./optee/tegra<platform>-optee.dtb \
       --tostype optee \
       ./tos.img

----------------------------------------------------------------------
Verifying the Image
----------------------------------------------------------------------
To verify the image:
1. Replace the default TOS image file with the newly generated TOS
   image. The default TOS image file is located at:
   <Linux_for_Tegra>/bootloader/tos-optee_t<platform>.img

2. Complete one of the following tasks:
   - Flash the system as usual.
     This is useful for flashing a new system or replacing the
     entire operating system.
   - Flash the TOS image again using the following partition flash commands:
       sudo ./flash.sh -k <TOS partition name> <your_board_conf_file> mmcblk0p1
       For example:
       sudo ./flash.sh -k A_secure-os jetson-agx-orin-devkit mmcblk0p1

3. Copy all the files under ./optee/install/t<platform> to the target.
