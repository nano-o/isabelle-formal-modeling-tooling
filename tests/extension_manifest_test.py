#!/usr/bin/env python3
"""Keep the intentionally different Claude and Codex MCP declarations intact."""

from __future__ import annotations

import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def load(relative_path: str) -> dict[str, object]:
    payload = json.loads((REPO_ROOT / relative_path).read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise AssertionError(f"{relative_path} must contain an object")
    return payload


codex_manifest = load("extension/.codex-plugin/plugin.json")
claude_manifest = load("extension/.claude-plugin/plugin.json")
codex_mcp = load("extension/codex/.mcp.json")
claude_mcp = load("extension/.mcp.json")

assert codex_manifest.get("mcpServers") == "./codex/.mcp.json"
assert claude_manifest.get("mcpServers") == "./.mcp.json"

assert "iq" in codex_mcp
assert "mcpServers" not in codex_mcp
assert "mcp_servers" not in codex_mcp
codex_iq = codex_mcp["iq"]
assert isinstance(codex_iq, dict)
assert "ISABELLE_TOOLING_ROOT" in codex_iq.get("env_vars", [])
assert "ISABELLE_TOOLING_ROOT" in " ".join(codex_iq.get("args", []))

assert set(claude_mcp) == {"mcpServers"}
claude_servers = claude_mcp["mcpServers"]
assert isinstance(claude_servers, dict)
assert "iq" in claude_servers
claude_iq = claude_servers["iq"]
assert isinstance(claude_iq, dict)
assert "CLAUDE_PLUGIN_ROOT" in str(claude_iq.get("command"))

# The coordination-board hooks are Claude Code only; Codex CLI has no hook
# mechanism the extension relies on, and its agents read the board by
# instruction from the isabelle-coordination skill.
assert claude_manifest.get("hooks") == "./hooks/board-hooks.json"
assert "hooks" not in codex_manifest
board_hooks = load("extension/hooks/board-hooks.json")
assert set(board_hooks) == {"hooks"}
declared_events = board_hooks["hooks"]
assert isinstance(declared_events, dict)
assert set(declared_events) == {"SessionStart", "UserPromptSubmit"}
for event, groups in declared_events.items():
    assert isinstance(groups, list) and groups, event
    for group in groups:
        assert isinstance(group, dict)
        for hook in group.get("hooks", []):
            assert hook.get("type") == "command", event
            assert "CLAUDE_PLUGIN_ROOT" in str(hook.get("command")), event
            assert "board-hook.sh" in str(hook.get("command")), event
assert (REPO_ROOT / "extension/bin/board-hook.sh").exists()

print("extension manifest host-parity checks passed")
