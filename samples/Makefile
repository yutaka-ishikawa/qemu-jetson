# SPDX-License-Identifier: BSD-2-Clause
.DEFAULT_GOAL := all
SAMPLES_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
O ?= $(SAMPLES_DIR)/../work/samples
OUT := $(abspath $(O))
SUBDIRS := ftpm-helper-probe hello_world random secure_storage aes sign_verify
.PHONY: all clean $(SUBDIRS)
all: $(SUBDIRS)
$(SUBDIRS):
	$(MAKE) -C "$(SAMPLES_DIR)/$@" O="$(OUT)/$@"
clean:
	@set -e; for name in $(SUBDIRS); do \
		$(MAKE) -C "$(SAMPLES_DIR)/$$name" O="$(OUT)/$$name" clean; \
	done
