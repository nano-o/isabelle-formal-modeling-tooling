#!/usr/bin/env bash
set -euo pipefail

# Render the neutral worker instructions into the two host profiles. Run after
# editing agents/ic2-prover.instructions.md; `make validate` fails when either
# rendered file is stale. With --check, only compare.

# shellcheck source=common.sh disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

SOURCE="$TOOLING_ROOT/agents/ic2-prover.instructions.md"
CLAUDE_TARGET="$TOOLING_ROOT/extension/agents/ic2-prover.md"
CODEX_TARGET="$TOOLING_ROOT/extension/agents/ic2_prover.toml"
DESCRIPTION="Autonomous Isabelle proof worker for an already-created dedicated ic2 Git worktree. Delegate a proof target to it once a coordinating agent has created that worktree. Never use it for work in the main jEdit worktree."

render_claude() {
  cat <<EOF
---
name: ic2-prover
description: $DESCRIPTION
tools: Bash, Read, Write, Edit, Glob, Grep
disallowedTools: mcp__iq
---

EOF
  cat "$SOURCE"
}

render_codex() {
  cat <<EOF
# Rendered from agents/ic2-prover.instructions.md by scripts/render-agents.sh.
# Do not edit; edit the source and re-render.
name = "ic2_prover"
description = "$DESCRIPTION"
sandbox_mode = "workspace-write"
developer_instructions = '''
EOF
  # TOML multi-line literal strings cannot contain three consecutive quotes.
  grep -q "'''" "$SOURCE" && die "the instructions contain ''' which cannot appear in a TOML literal string"
  cat "$SOURCE"
  cat <<'EOF'
'''

# A proof worker must never attach to the human's live main-worktree jEdit.
# Agent files are parsed standalone, so the server is declared, disabled.
[mcp_servers.iq]
command = "python3"
args = ["${ISABELLE_TOOLING_ROOT}/AutoCorrode/iq/iq_bridge.py"]
enabled = false
required = false
startup_timeout_sec = 10
tool_timeout_sec = 7200

[mcp_servers.iq.env]
IQ_MCP_BRIDGE_PORT = "8765"
EOF
}

if [[ "${1:-}" == "--check" ]]; then
  diff -u "$CLAUDE_TARGET" <(render_claude) >/dev/null || die "stale: $CLAUDE_TARGET (run scripts/render-agents.sh)"
  diff -u "$CODEX_TARGET" <(render_codex) >/dev/null || die "stale: $CODEX_TARGET (run scripts/render-agents.sh)"
  echo "rendered agent profiles are current"
  exit 0
fi
render_claude >"$CLAUDE_TARGET"
render_codex >"$CODEX_TARGET"
echo "rendered: $CLAUDE_TARGET"
echo "rendered: $CODEX_TARGET"
