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

# The bridge wrapper hands the bridge the token file launch_jedit.sh uses, so
# the project's iq server authenticates without the agent reading the token.
import os
import subprocess
import tempfile

with tempfile.TemporaryDirectory() as tmp:
    fake_bridge = Path(tmp) / "AutoCorrode/iq/iq_bridge.py"
    fake_bridge.parent.mkdir(parents=True)
    fake_bridge.write_text("import os; print(os.environ['IQ_TOKEN_FILE'])\n", encoding="utf-8")
    env = {k: v for k, v in os.environ.items() if k not in ("IQ_TOKEN_FILE", "XDG_CONFIG_HOME")}
    env.update(ISABELLE_TOOLING_ROOT=tmp, HOME="/home/someone")

    def token_file(**extra: str) -> str:
        return subprocess.run([str(REPO_ROOT / "extension/bin/iq-bridge.sh")], env={**env, **extra},
                              capture_output=True, text=True, check=True).stdout.strip()

    assert token_file() == "/home/someone/.config/isabelle-iq/auth-token", token_file()
    assert token_file(XDG_CONFIG_HOME="/xdg") == "/xdg/isabelle-iq/auth-token"
    assert token_file(IQ_TOKEN_FILE="/elsewhere/token") == "/elsewhere/token"
launcher = (REPO_ROOT / "scripts/launch_jedit.sh").read_text(encoding="utf-8")
assert 'IQ_TOKEN_FILE="${IQ_TOKEN_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/isabelle-iq/auth-token}"' in launcher
for name in ("IQ_TOKEN_FILE", "XDG_CONFIG_HOME"):
    assert name in codex_iq.get("env_vars", []), name

print("extension manifest host-parity checks passed")
