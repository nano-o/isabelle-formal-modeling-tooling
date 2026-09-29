SHELL := /bin/bash

SCRIPT_FILES := $(wildcard scripts/*.sh) extension/bin/iq-bridge.sh bin/isabelle-tooling
TEST_FILES := \
	tests/common_test.sh \
	tests/descriptor_test.sh \
	tests/ic2_test.sh \
	tests/new_project_test.sh \
	tests/start_ic2_test.sh \
	tests/model_runner_test.sh \
	tests/export_check_test.sh \
	tests/board_notifier_test.sh
ISABELLE_TEST_FILES := \
	tests/isabelle/export_check_test.sh \
	tests/isabelle/model_runner_test.sh
TEST_SUPPORT_FILES := tests/test_lib.sh tests/fixtures/isabelle
HOST_FIXTURE_FILES := tests/host/phase4-fixture.sh tests/host/phase4-check.sh
PYTHON_TEST_FILES := tests/extension_manifest_test.py tests/project_install_test.py
PYTHON_FILES := scripts/isabelle_tooling.py scripts/project_files.py $(PYTHON_TEST_FILES)

.PHONY: help validate render check-isabelle

render:
	./scripts/render-agents.sh

help:
	@echo "Targets:"
	@echo "  validate   Parse, lint, and test the shell tooling; check rendered agent profiles"
	@echo "  render     Re-render the host agent profiles from agents/ic2-prover.instructions.md"
	@echo "  check-isabelle  Run the tests that need a real Isabelle: export-check fixtures, model runner"

validate:
	./scripts/render-agents.sh --check
	python3 -c 'import json,sys; [json.load(open(f)) for f in sys.argv[1:]]' .claude-plugin/marketplace.json extension/.claude-plugin/plugin.json extension/.mcp.json extension/.codex-plugin/plugin.json extension/codex/.mcp.json .agents/plugins/marketplace.json extension/project/*.json
	python3 -c 'import ast,sys; [ast.parse(open(f).read(), f) for f in sys.argv[1:]]' $(PYTHON_FILES)
	@for test_file in $(PYTHON_TEST_FILES); do \
		PYTHONDONTWRITEBYTECODE=1 python3 "$$test_file" || exit 1; \
	done
	bash -n $(SCRIPT_FILES) $(TEST_FILES) $(TEST_SUPPORT_FILES) $(ISABELLE_TEST_FILES) $(HOST_FIXTURE_FILES)
	shellcheck $(SCRIPT_FILES) $(TEST_FILES) $(TEST_SUPPORT_FILES) $(ISABELLE_TEST_FILES) $(HOST_FIXTURE_FILES)
	@for test_file in $(TEST_FILES); do \
		bash "$$test_file" || exit 1; \
	done

check-isabelle:
	@for test_file in $(ISABELLE_TEST_FILES); do \
		bash "$$test_file" || exit 1; \
	done
