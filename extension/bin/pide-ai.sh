#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=../../scripts/common.sh disable=SC1091
source "$SCRIPT_DIR/../../scripts/common.sh"
# shellcheck source=../../scripts/pide-ai-common.sh disable=SC1091
source "$SCRIPT_DIR/../../scripts/pide-ai-common.sh"

{ read -r requested_root; read -r consumed; } < <(parse_project_root_option "$@")
shift "$consumed"
[[ $# -eq 0 ]] || die "usage: pide-ai.sh [--project-root DIR]"
resolve_project "$requested_root"
[[ "${PROJECT_CONF[isabelle_version]}" == Isabelle2026 ]] ||
  die "PIDE AI requires isabelle_version=Isabelle2026 in $PROJECT_DESCRIPTOR."
require_isabelle2026
pide_ai_ready

cd "$PROJECT_CHECKOUT_ROOT"
exec "$ISABELLE_CMD" pide_mcp -d "$PROJECT_FORMAL_ROOT" -R "${PROJECT_CONF[build_session]}" \
  -o pide_ai_unicode_symbols_disk=false
