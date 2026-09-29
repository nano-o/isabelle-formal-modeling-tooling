#!/usr/bin/env bash
# Launch the I/Q MCP stdio bridge from the tooling clone. Both agent hosts run
# this; it is the one place the extension resolves the tooling clone.
set -euo pipefail
root="${ISABELLE_TOOLING_ROOT:-}"
if [[ -z "$root" ]]; then
  echo "iq-bridge: ISABELLE_TOOLING_ROOT is not set; point it at the isabelle-formal-modeling-tooling clone" >&2
  exit 2
fi
bridge="$root/AutoCorrode/iq/iq_bridge.py"
if [[ ! -f "$bridge" ]]; then
  echo "iq-bridge: $bridge not found; populate the submodule with: git -C $root submodule update --init" >&2
  exit 2
fi
# The bridge authenticates with the I/Q token itself, so that agents never
# read it; launch_jedit.sh gives jEdit the same file.
export IQ_TOKEN_FILE="${IQ_TOKEN_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/isabelle-iq/auth-token}"
exec python3 "$bridge" "$@"
