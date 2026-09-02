#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=common.sh disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

DRY_RUN=false
case "${1:-}" in
  --dry-run) DRY_RUN=true ;;
  -h|--help)
    cat <<'EOF'
Usage: build-ic2.sh [--dry-run]

Register the tooling clone's AutoCorrode ic2 component with the host Isabelle
and build its JAR. This is the one persistent step the ic2 workflow needs and
the only one it takes in the home directory:

  isabelle components -u <clone>/AutoCorrode/ic2

adds one line to $ISABELLE_HOME_USER/etc/components (Isabelle discovers
components only through that file). Undo it with

  isabelle components -x <clone>/AutoCorrode/ic2

The JAR is written inside the clone, at AutoCorrode/ic2/lib/ic2.jar.
EOF
    exit 0
    ;;
  "") ;;
  *) die "unknown option: $1" ;;
esac

[[ -f "$IC2_COMPONENT_DIR/etc/build.props" ]] ||
  die "AutoCorrode submodule is not populated; run: git -C $TOOLING_ROOT submodule update --init"
require_isabelle
home_user="$("$ISABELLE_CMD" getenv -b ISABELLE_HOME_USER)"

echo "Register component (writes one line to $home_user/etc/components):"
print_command isabelle components -u "$IC2_COMPONENT_DIR"
echo "Build the ic2 JAR ($IC2_COMPONENT_DIR/lib/ic2.jar):"
print_command isabelle scala_build
[[ "$DRY_RUN" == false ]] || exit 0

"$ISABELLE_CMD" components -u "$IC2_COMPONENT_DIR"
"$ISABELLE_CMD" scala_build
"$ISABELLE_CMD" ic2 >/dev/null 2>&1 || [[ $? -ne 127 ]]
echo "ic2 is available as: $ISABELLE_CMD ic2"
echo "Undo the registration with: isabelle components -x $IC2_COMPONENT_DIR"
