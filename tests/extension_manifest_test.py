#!/usr/bin/env python3
"""Keep the project manifest and the two hosts' intentionally different iq declarations intact."""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
import tomllib
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def load(relative_path: str) -> dict[str, object]:
    payload = json.loads((REPO_ROOT / relative_path).read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise AssertionError(f"{relative_path} must contain an object")
    return payload


# The project manifest installs every shipped skill and names only files
# that exist at this revision.
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

# Claude Code: a member of the project's .mcp.json. It expands ${VAR} in
# `command`, so the entry names the bridge through ISABELLE_TOOLING_ROOT.
claude_iq = load("extension/project/mcp-iq.json")
assert claude_iq == {"command": "${ISABELLE_TOOLING_ROOT}/extension/bin/iq-bridge.sh",
                     "args": [], "env": {"IQ_MCP_BRIDGE_PORT": "8765"}}, claude_iq

# Codex CLI: a managed [mcp_servers.iq] block. It expands no variable in a
# stdio `command` and passes only the variables `env_vars` names, so a shell
# expands ISABELLE_TOOLING_ROOT and the bridge's token variables are forwarded.
codex_block = (REPO_ROOT / "extension/project/codex-config.toml").read_text(encoding="utf-8")
assert codex_block.splitlines()[0].startswith("# Managed by isabelle-tooling")
codex_config = tomllib.loads(codex_block)
assert list(codex_config) == ["mcp_servers"] and list(codex_config["mcp_servers"]) == ["iq"]
codex_iq = codex_config["mcp_servers"]["iq"]
assert codex_iq["command"] == "bash"
assert codex_iq["args"] == ["-c", 'exec "$ISABELLE_TOOLING_ROOT/extension/bin/iq-bridge.sh"'], codex_iq["args"]
assert codex_iq["env_vars"] == ["ISABELLE_TOOLING_ROOT", "IQ_TOKEN_FILE", "XDG_CONFIG_HOME"], codex_iq["env_vars"]
assert codex_iq["env"] == claude_iq["env"]
assert set(codex_iq) == {"command", "args", "env_vars", "env"}, set(codex_iq)

# The plugin route ended with extension v0.7.1 (step 6 of the delivery plan);
# the board, which installs its own digest hook, is not part of the tooling.
for gone in (".claude-plugin", ".agents/plugins", "extension/.claude-plugin", "extension/.codex-plugin",
             "extension/.mcp.json", "extension/codex", "extension/hooks", "scripts/release.sh"):
    assert not (REPO_ROOT / gone).exists(), gone

# The bridge wrapper hands the bridge the token file launch_jedit.sh uses, so
# the project's iq server authenticates without the agent reading the token.
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
print("extension manifest host-parity checks passed")
