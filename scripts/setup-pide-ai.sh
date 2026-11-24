#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=common.sh disable=SC1091
source "$SCRIPT_DIR/common.sh"
# shellcheck source=pide-ai-common.sh disable=SC1091
source "$SCRIPT_DIR/pide-ai-common.sh"

PIDE_AI_URL=https://github.com/kappelmann/isabelle-pide-ai.git

case "${1:-}" in
  --help|-h)
    cat <<'EOF'
Usage: setup-pide-ai.sh

Fetch the pinned PIDE AI source into the tooling clone, register it in the
Isabelle2026 user home, and build its Scala JARs. Set
ISABELLE_TOOLING_ISABELLE2026 if Isabelle2026 is not on PATH.
EOF
    exit 0 ;;
  "") ;;
  *) die "unknown argument: $1" ;;
esac

require_isabelle2026
require_command git
require_command flock

cache_dir="$(dirname "$PIDE_AI_DIR")"
mkdir -p -- "$cache_dir"
exec 9>"$cache_dir/setup.lock"
flock 9

if [[ ! -e "$PIDE_AI_DIR" ]]; then
  stage="$(mktemp -d "$cache_dir/checkout.XXXXXXXX")"
  trap 'rm -rf -- "$stage"' EXIT
  git -C "$stage" init -q
  git -C "$stage" fetch --depth=1 "$PIDE_AI_URL" "$PIDE_AI_REVISION"
  git -C "$stage" checkout --quiet --detach FETCH_HEAD
  [[ "$(git -C "$stage" rev-parse HEAD)" == "$PIDE_AI_REVISION" ]] ||
    die "Unexpected PIDE AI revision fetched."
  mv -T -- "$stage" "$PIDE_AI_DIR"
fi
pide_ai_checkout_ok ||
  die "PIDE AI checkout at $PIDE_AI_DIR differs from $PIDE_AI_REVISION. Move it aside and rerun setup."

expected_id="$(<"$PIDE_AI_DIR/ISABELLE_VERSION")"
actual_id="$("$ISABELLE_CMD" version -i)" || die "Cannot identify the Isabelle2026 distribution."
[[ "$actual_id" == "$expected_id" ]] ||
  die "This PIDE AI pin requires Isabelle2026 build $expected_id, found ${actual_id:-unknown}."

for variable in PIDE_AI_HOME PIDE_MCP_HOME SYMBOLS_HOME; do
  path="$("$ISABELLE_CMD" getenv -b "$variable")" || die "Cannot read $variable from Isabelle2026."
  [[ -z "$path" || "$path" == "$PIDE_AI_DIR/"* ]] ||
    die "Another PIDE AI component is active at $path. Unregister its root with Isabelle2026 components -x DIR."
done

echo "Registering $PIDE_AI_DIR in $("$ISABELLE_CMD" getenv -b ISABELLE_HOME_USER)"
"$ISABELLE_CMD" components -u "$PIDE_AI_DIR"
"$ISABELLE_CMD" scala_build
pide_ai_ready
echo "PIDE AI $PIDE_AI_REVISION is ready. To unregister it, run:"
print_command "$ISABELLE_CMD" components -x "$PIDE_AI_DIR"
