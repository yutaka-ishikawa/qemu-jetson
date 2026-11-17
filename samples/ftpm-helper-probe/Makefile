# SPDX-License-Identifier: BSD-2-Clause
.DEFAULT_GOAL := all
SAMPLE_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
REPO_DIR := $(abspath $(SAMPLE_DIR)/../..)
INSTALL_DIR ?= $(REPO_DIR)/install
CLIENT_INCLUDE ?= $(INSTALL_DIR)/include
CLIENT_LIB ?= $(INSTALL_DIR)/lib/aarch64-linux-gnu
TA_DEV_KIT_DIR ?= $(INSTALL_DIR)/lib/optee/ta-dev-kit-aarch64
TA_SIGN_KEY ?= $(REPO_DIR)/optee/optee/optee_os/keys/default_ta.pem
CROSS_COMPILE ?= aarch64-linux-gnu-
O ?= $(REPO_DIR)/work/samples/ftpm-helper-probe
OUT := $(abspath $(O))
TA_UUID := 7fc1d460-5a6c-4a5f-9b9e-6c298d3032a0

.PHONY: all host ta check clean
all: host ta

check:
	@test -f "$(CLIENT_INCLUDE)/tee_client_api.h" || { echo 'Missing client headers; build/install the OP-TEE client first.' >&2; exit 1; }
	@test -f "$(TA_DEV_KIT_DIR)/mk/ta_dev_kit.mk" || { echo 'Missing TA SDK; build/install the firmware first.' >&2; exit 1; }
	@test -f "$(TA_SIGN_KEY)" || { echo 'Set TA_SIGN_KEY to a development TA signing key accepted by this OP-TEE build.' >&2; exit 1; }
	@command -v "$(CROSS_COMPILE)gcc" >/dev/null || { echo 'Compiler missing; set CROSS_COMPILE (empty for native ARM64 gcc).' >&2; exit 1; }

host: check
	@mkdir -p "$(OUT)"
	$(CROSS_COMPILE)gcc $(CPPFLAGS) $(CFLAGS) -Wall -Wextra -Werror \
		-I"$(CLIENT_INCLUDE)" "$(SAMPLE_DIR)/host/probe.c" \
		-L"$(CLIENT_LIB)" $(LDFLAGS) -lteec -o "$(OUT)/ftpm-helper-probe"

ta: check
	@mkdir -p "$(OUT)/ta"
	$(MAKE) -C "$(SAMPLE_DIR)/ta" CROSS_COMPILE="$(CROSS_COMPILE)" \
		TA_DEV_KIT_DIR="$(abspath $(TA_DEV_KIT_DIR))" \
		TA_SIGN_KEY="$(abspath $(TA_SIGN_KEY))" O="$(OUT)/ta"
	@echo "TA: $(OUT)/ta/$(TA_UUID).ta"

# Remove only known generated files. Never recursively delete a caller's O path.
clean:
	$(RM) "$(OUT)/ftpm-helper-probe"
	@if test -d "$(OUT)/ta"; then \
		$(MAKE) -C "$(SAMPLE_DIR)/ta" clean \
		TA_DEV_KIT_DIR="$(abspath $(TA_DEV_KIT_DIR))" O="$(OUT)/ta"; \
	fi
