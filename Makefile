SHELL := /bin/bash

SCRIPT_FILES := $(wildcard scripts/*.sh) extension/bin/iq-bridge.sh
TEST_FILES := \
	tests/common_test.sh \
	tests/descriptor_test.sh \
	tests/ic2_test.sh \
	tests/new_project_test.sh \
	tests/start_ic2_test.sh
TEST_SUPPORT_FILES := tests/test_lib.sh tests/fixtures/isabelle

.PHONY: help validate render

render:
	./scripts/render-agents.sh

help:
	@echo "Targets:"
	@echo "  validate   Parse, lint, and test the shell tooling; check rendered agent profiles"
	@echo "  render     Re-render the host agent profiles from agents/ic2-prover.instructions.md"

validate:
	./scripts/render-agents.sh --check
	python3 -c 'import json,sys; [json.load(open(f)) for f in sys.argv[1:]]' .claude-plugin/marketplace.json extension/.claude-plugin/plugin.json extension/.mcp.json extension/.codex-plugin/plugin.json extension/codex/.mcp.json .agents/plugins/marketplace.json
	bash -n $(SCRIPT_FILES) $(TEST_FILES) $(TEST_SUPPORT_FILES)
	shellcheck $(SCRIPT_FILES) $(TEST_FILES) $(TEST_SUPPORT_FILES)
	@for test_file in $(TEST_FILES); do \
		bash "$$test_file" || exit 1; \
	done
