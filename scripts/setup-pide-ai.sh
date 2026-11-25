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

home_user="$("$ISABELLE_CMD" getenv -b ISABELLE_HOME_USER)" ||
  die "Cannot read ISABELLE_HOME_USER from Isabelle2026."
components_file="$home_user/etc/components"

# registered_components: print the component directories registered in the
# Isabelle2026 user home, trimmed as Isabelle reads them.
registered_components() {
  local entry
  [[ -f "$components_file" ]] || return 0
  while read -r entry || [[ -n "$entry" ]]; do
    [[ -z "$entry" || "$entry" == '#'* ]] || printf '%s\n' "$entry"
  done <"$components_file"
}

# replaced_pin DIR: succeed if DIR is a pin that setup replaces instead of
# refusing: an earlier pin of this clone, or a pin of any tooling clone whose
# directory is gone, as after moving the clone.
replaced_pin() {
  local pin_pattern='/\.pide-ai/[0-9a-f]{40}$'
  [[ "$1" != "$PIDE_AI_DIR" && "$1" =~ $pin_pattern ]] || return 1
  [[ "$1" == "$TOOLING_ROOT/.pide-ai/"* || ! -e "$1" ]]
}

# registration_holding PATH: print the registered component directory that is
# PATH or contains it.
registration_holding() {
  local entry
  while IFS= read -r entry; do
    if [[ "$1" == "$entry" || "$1" == "$entry/"* ]]; then
      printf '%s\n' "$entry"
      return 0
    fi
  done < <(registered_components)
  return 1
}

# components -x matches the registered line as given, so it also removes the
# registration of a directory that no longer exists.
while IFS= read -r entry; do
  replaced_pin "$entry" || continue
  echo "Unregistering the earlier PIDE AI pin $entry"
  "$ISABELLE_CMD" components -x "$entry"
done < <(registered_components)

for variable in PIDE_AI_HOME PIDE_MCP_HOME SYMBOLS_HOME; do
  path="$("$ISABELLE_CMD" getenv -b "$variable")" || die "Cannot read $variable from Isabelle2026."
  [[ -z "$path" || "$path" == "$PIDE_AI_DIR/"* ]] && continue
  root="$(registration_holding "$path")" ||
    die "Isabelle2026 loads another PIDE AI component from $path, which $components_file does not register. Remove it from the settings that add it, then rerun setup."
  die "Another PIDE AI component is registered at $root. Unregister it, then rerun setup:
$(print_command "$ISABELLE_CMD" components -x "$root")"
done

echo "Registering $PIDE_AI_DIR in $home_user"
"$ISABELLE_CMD" components -u "$PIDE_AI_DIR"
"$ISABELLE_CMD" scala_build
pide_ai_ready
echo "PIDE AI $PIDE_AI_REVISION is ready. To unregister it, run:"
print_command "$ISABELLE_CMD" components -x "$PIDE_AI_DIR"
