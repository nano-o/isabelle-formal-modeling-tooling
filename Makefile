SHELL := /bin/bash

SCRIPT_FILES := $(wildcard scripts/*.sh)
TEST_FILES := \
	tests/common_test.sh \
	tests/descriptor_test.sh \
	tests/ic2_test.sh \
	tests/start_ic2_test.sh
TEST_SUPPORT_FILES := tests/test_lib.sh tests/fixtures/isabelle

.PHONY: help validate

help:
	@echo "Targets:"
	@echo "  validate   Parse, lint, and test the shell tooling"

validate:
	bash -n $(SCRIPT_FILES) $(TEST_FILES) $(TEST_SUPPORT_FILES)
	shellcheck $(SCRIPT_FILES) $(TEST_FILES) $(TEST_SUPPORT_FILES)
	@for test_file in $(TEST_FILES); do \
		bash "$$test_file" || exit 1; \
	done
