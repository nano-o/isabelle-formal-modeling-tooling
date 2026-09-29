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

# The coordination board moved to agent-board, which installs its own
# digest hook into a project; neither extension declares hooks.
assert "hooks" not in claude_manifest
assert "hooks" not in codex_manifest
assert not (REPO_ROOT / "extension/hooks").exists()

# The project delivery declares the same two shapes: a member of .mcp.json for
# Claude Code and a managed [mcp_servers.iq] block for Codex CLI, both naming
# the tooling only through ISABELLE_TOOLING_ROOT.
import tomllib

project = load("extension/project/manifest.json")
assert project["component"] == "isabelle-tooling" and project["format"] == 1
installed = sorted(s["name"] for s in project["skills"])
shipped = sorted(p.name for p in (REPO_ROOT / "extension/skills").iterdir() if (p / "SKILL.md").is_file())
assert installed == shipped, (installed, shipped)
for skill in project["skills"]:
    assert (REPO_ROOT / skill["source"] / "SKILL.md").is_file()
for item in project["files"] + project["json_entries"] + project["toml_blocks"]:
    assert (REPO_ROOT / item["source"]).is_file(), item
assert (REPO_ROOT / project["markdown_block"]).is_file()

project_claude = load("extension/project/mcp-iq.json")
assert project_claude["command"] == "${ISABELLE_TOOLING_ROOT}/extension/bin/iq-bridge.sh"
assert project_claude["env"] == claude_iq["env"]
codex_block = (REPO_ROOT / "extension/project/codex-config.toml").read_text(encoding="utf-8")
assert codex_block.splitlines()[0].startswith("# Managed by isabelle-tooling")
assert tomllib.loads(codex_block) == {"mcp_servers": {"iq": codex_iq}}

print("extension manifest host-parity checks passed")
