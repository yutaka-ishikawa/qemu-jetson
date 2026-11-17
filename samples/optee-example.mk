# SPDX-License-Identifier: BSD-2-Clause
# Build imported examples without generating files in their source directories.
.DEFAULT_GOAL := all
REPO_DIR := $(abspath $(SAMPLE_DIR)/../..)
SAMPLE_NAME := $(notdir $(SAMPLE_DIR))
INSTALL_DIR ?= $(REPO_DIR)/install
CLIENT_INCLUDE ?= $(INSTALL_DIR)/include
CLIENT_LIB ?= $(INSTALL_DIR)/lib/aarch64-linux-gnu
TA_DEV_KIT_DIR ?= $(INSTALL_DIR)/lib/optee/ta-dev-kit-aarch64
TA_SIGN_KEY ?= $(REPO_DIR)/optee/optee/optee_os/keys/default_ta.pem
CROSS_COMPILE ?= aarch64-linux-gnu-
O ?= $(REPO_DIR)/work/samples/$(SAMPLE_NAME)
OUT := $(abspath $(O))

.PHONY: all host ta check clean
all: host ta
check:
	@test -f "$(CLIENT_INCLUDE)/tee_client_api.h" || { echo 'Missing OP-TEE client headers; build/install the client first.' >&2; exit 1; }
	@test -f "$(TA_DEV_KIT_DIR)/mk/ta_dev_kit.mk" || { echo 'Missing TA SDK; build/install the firmware first.' >&2; exit 1; }
	@test -f "$(TA_SIGN_KEY)" || { echo 'Set TA_SIGN_KEY to a development key accepted by this OP-TEE build.' >&2; exit 1; }
	@command -v "$(CROSS_COMPILE)gcc" >/dev/null || { echo 'Compiler missing; set CROSS_COMPILE (empty for native ARM64 gcc).' >&2; exit 1; }
host: check
	@mkdir -p "$(OUT)"
	$(CROSS_COMPILE)gcc $(CPPFLAGS) $(CFLAGS) -Wall -Wextra \
		-I"$(CLIENT_INCLUDE)" -I"$(SAMPLE_DIR)/ta/include" -I"$(SAMPLE_DIR)/host/include" \
		$(wildcard $(SAMPLE_DIR)/host/*.c) -L"$(CLIENT_LIB)" $(LDFLAGS) -lteec \
		-o "$(OUT)/optee_example_$(SAMPLE_NAME)"
ta: check
	@mkdir -p "$(OUT)/ta"
	$(MAKE) -C "$(SAMPLE_DIR)/ta" CROSS_COMPILE="$(CROSS_COMPILE)" \
		TA_DEV_KIT_DIR="$(abspath $(TA_DEV_KIT_DIR))" \
		TA_SIGN_KEY="$(abspath $(TA_SIGN_KEY))" O="$(OUT)/ta"
clean:
	$(RM) "$(OUT)/optee_example_$(SAMPLE_NAME)"
	@if test -d "$(OUT)/ta"; then \
		$(MAKE) -C "$(SAMPLE_DIR)/ta" clean TA_DEV_KIT_DIR="$(abspath $(TA_DEV_KIT_DIR))" O="$(OUT)/ta"; \
	fi
