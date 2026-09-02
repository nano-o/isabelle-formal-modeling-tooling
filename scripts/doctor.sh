#!/usr/bin/env bash
set -uo pipefail

# shellcheck source=common.sh disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

TOKEN_FILE="${IQ_TOKEN_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/isabelle-iq/auth-token}"
ALLOW_DIRTY=false
requested_root=""
failures=0
notes=0

usage() {
  cat <<'EOF'
Usage: doctor.sh [--project-root DIR] [--allow-dirty]

Check the host Isabelle, the tooling clone and its pinned AutoCorrode
submodule, the single ic2 component registration and its JAR, the I/Q plugin
and token, the I/R virtual environment, and the project's descriptor. Reports
what it found and prints remediation commands; it never runs them.

  --project-root DIR  Checkout to diagnose (default: nearest descriptor above $PWD)
  --allow-dirty       Pass with a modified tooling clone or submodule, marking the report
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root) [[ -n "${2:-}" ]] || die "--project-root requires an argument"; requested_root="$2"; shift 2 ;;
    --project-root=*) requested_root="${1#--project-root=}"; shift ;;
    --allow-dirty) ALLOW_DIRTY=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

ok() { printf '[OK]   %s\n' "$*"; }
note() { printf '[NOTE] %s\n' "$*"; notes=$((notes + 1)); }
problem() { printf '[FAIL] %s\n' "$*"; failures=$((failures + 1)); }
file_mode() { stat -c '%a' "$1" 2>/dev/null; }

echo "Isabelle tooling doctor ($TOOLING_ROOT)"

# --- project descriptor -------------------------------------------------------

descriptor_ok=false
if resolve_project "$requested_root" 2>"$TOOLING_ROOT/.doctor-resolve.err"; then
  descriptor_ok=true
  ok "Project descriptor: $PROJECT_DESCRIPTOR"
  ok "Source root $PROJECT_SOURCE_ROOT; formal root $PROJECT_FORMAL_ROOT"
  session_dir="$PROJECT_FORMAL_ROOT/${PROJECT_CONF[session_dir]}"
  if [[ ! -f "$PROJECT_FORMAL_ROOT/ROOT" && ! -f "$PROJECT_FORMAL_ROOT/ROOTS" ]]; then
    problem "Formal root has no ROOT or ROOTS: $PROJECT_FORMAL_ROOT"
  elif [[ ! -d "$session_dir" ]]; then
    problem "session_dir does not exist: $session_dir"
  else
    ok "Session ${PROJECT_CONF[build_session]} in $session_dir (ic2 base ${PROJECT_CONF[ic2_base_session]})"
  fi
else
  problem "$(<"$TOOLING_ROOT/.doctor-resolve.err")"
fi
rm -f "$TOOLING_ROOT/.doctor-resolve.err"
expected_isabelle="${PROJECT_CONF[isabelle_version]:-Isabelle2025-2}"

# --- Isabelle -----------------------------------------------------------------------

isabelle_version=""
isabelle_home_user=""
if ISABELLE_CMD="$(find_isabelle)"; then
  isabelle_version="$("$ISABELLE_CMD" version 2>/dev/null || true)"
  if [[ "$isabelle_version" == "$expected_isabelle" ]]; then
    ok "$expected_isabelle: $ISABELLE_CMD"
    isabelle_home_user="$("$ISABELLE_CMD" getenv -b ISABELLE_HOME_USER 2>/dev/null || true)"
  else
    problem "Expected $expected_isabelle, found ${isabelle_version:-unusable} at $ISABELLE_CMD"
  fi
else
  problem "Isabelle not found. Install $expected_isabelle from https://isabelle.in.tum.de, then put its bin/ on PATH or set ISABELLE_TOOLING_ISABELLE."
fi

# --- tooling clone and AutoCorrode submodule ------------------------------------------

autocorrode_rev=""
recorded_rev="$(git -C "$TOOLING_ROOT" ls-files --stage -- AutoCorrode 2>/dev/null | awk '$1 == "160000" {print $2; exit}')"
if [[ -z "$recorded_rev" ]]; then
  problem "AutoCorrode is not recorded as a submodule of the tooling clone."
elif [[ ! -f "$AUTOCORRODE_DIR/iq/iq_bridge.py" ]]; then
  problem "AutoCorrode is not populated; run: git -C $TOOLING_ROOT submodule update --init"
else
  autocorrode_rev="$(git -C "$AUTOCORRODE_DIR" rev-parse HEAD 2>/dev/null || true)"
  if [[ "$autocorrode_rev" == "$recorded_rev" ]]; then
    ok "AutoCorrode submodule matches the recorded revision: $autocorrode_rev"
  else
    problem "AutoCorrode HEAD (${autocorrode_rev:-unknown}) does not match the recorded gitlink ($recorded_rev); run: git -C $TOOLING_ROOT submodule update"
  fi
fi

tooling_head="$(git -C "$TOOLING_ROOT" rev-parse HEAD 2>/dev/null || true)"
# A clone checked out at a release commit carries extension/REVISION naming
# the source commit it was built from; that is the revision everything is
# compared against. A source checkout has no REVISION and HEAD is the source.
tooling_source_rev="$tooling_head"
if [[ -f "$TOOLING_ROOT/extension/REVISION" ]]; then
  tooling_source_rev="$(sed -n 's/^source_revision=//p' "$TOOLING_ROOT/extension/REVISION" | head -n 1)"
fi
dirty="$(git -C "$TOOLING_ROOT" status --porcelain --ignore-submodules=none 2>/dev/null; git -C "$AUTOCORRODE_DIR" status --porcelain 2>/dev/null | sed 's|^|AutoCorrode/|')"
if [[ -n "$dirty" ]]; then
  if [[ "$ALLOW_DIRTY" == true ]]; then
    note "Tooling clone or submodule is modified (--allow-dirty): $(printf '%s' "$dirty" | awk '{print $2}' | paste -sd' ')"
  else
    problem "Tooling clone or submodule is modified; scripts execute while HEAD still matches. Commit, or pass --allow-dirty: $(printf '%s' "$dirty" | awk '{print $2}' | paste -sd' ')"
  fi
else
  ok "Tooling clone and submodule are clean at $tooling_head"
fi
if [[ "$descriptor_ok" == true ]]; then
  if [[ -z "${PROJECT_CONF[tooling_revision]+set}" ]]; then
    problem "Descriptor has no tooling_revision; set it to the tooling clone revision the artifacts were validated against ($tooling_head)."
  elif [[ "${PROJECT_CONF[tooling_revision]}" == "$tooling_source_rev" ]]; then
    ok "Descriptor tooling_revision matches the tooling clone ($tooling_source_rev)"
  else
    problem "Descriptor tooling_revision ${PROJECT_CONF[tooling_revision]} differs from the tooling clone's source revision $tooling_source_rev; check out that revision or revalidate and update the descriptor."
  fi
fi

# --- installed agent-host extensions ------------------------------------------------
#
# Each host caches installed plugins under its own directory. A released
# extension carries REVISION; its source_revision must be the tooling clone's,
# or the skills an agent reads and the scripts it runs come from different
# revisions. A host with no installed extension is a note, not a failure.

check_extension() {
  local host="$1" cache_root="$2" agent_file="$3"
  local revisions rev expected_sha install_dir src tag
  [[ -d "$cache_root" ]] || { note "$host: no plugin cache at $cache_root; extension not installed for this host"; return; }
  mapfile -t revisions < <(find "$cache_root" -mindepth 3 -maxdepth 4 -path '*/isabelle-formal-modeling/*' -name REVISION 2>/dev/null | sort)
  if [[ "${#revisions[@]}" -eq 0 ]]; then
    if find "$cache_root" -mindepth 2 -maxdepth 3 -type d -name isabelle-formal-modeling 2>/dev/null | grep -q .; then
      note "$host: the installed extension has no REVISION file (a development install, not a release); revision skew cannot be checked"
    else
      note "$host: extension not installed"
    fi
    return
  fi
  for rev in "${revisions[@]}"; do
    install_dir="$(dirname "$rev")"
    src="$(sed -n 's/^source_revision=//p' "$rev" | head -n 1)"
    tag="$(sed -n 's/^release_tag=//p' "$rev" | head -n 1)"
    if [[ "$src" == "$tooling_source_rev" ]]; then
      ok "$host: installed extension $tag matches the tooling clone ($install_dir)"
    else
      problem "$host: installed extension $tag was built from $src, but the tooling clone is at $tooling_source_rev; upgrade the extension or check out that revision ($install_dir)"
    fi
    if [[ -n "$agent_file" ]]; then
      expected_sha="$(sed -n 's/^codex_agent_sha256=//p' "$rev" | head -n 1)"
      if [[ ! -f "$agent_file" ]]; then
        problem "$host: proof-worker profile is not installed; run: install -m 0644 $install_dir/codex/ic2_prover.toml $agent_file"
      elif [[ "$(openssl dgst -sha256 "$agent_file" | awk '{print $NF}')" == "$expected_sha" ]]; then
        ok "$host: installed proof-worker profile matches the extension ($agent_file)"
      else
        problem "$host: installed proof-worker profile differs from the extension's; reinstall: install -m 0644 $install_dir/codex/ic2_prover.toml $agent_file"
      fi
    fi
  done
}

check_extension "Claude Code" "$HOME/.claude/plugins/cache" ""
check_extension "Codex CLI" "${CODEX_HOME:-$HOME/.codex}/plugins/cache" "${CODEX_HOME:-$HOME/.codex}/agents/ic2_prover.toml"

# --- ic2 component -----------------------------------------------------------------

if [[ -n "$isabelle_home_user" ]]; then
  mapfile -t ic2_components < <("$ISABELLE_CMD" components -l 2>/dev/null | awk '/^  \//{print $1}' | grep -E '/ic2$' || true)
  expected_component="$IC2_COMPONENT_DIR"
  if [[ "${#ic2_components[@]}" -eq 0 ]]; then
    problem "No ic2 component is registered; run: $TOOLING_ROOT/scripts/build-ic2.sh (isabelle components -u $expected_component)"
  elif [[ "${#ic2_components[@]}" -gt 1 ]]; then
    problem "${#ic2_components[@]} ic2 components are registered (Isabelle would load whichever comes first): ${ic2_components[*]}. Keep only $expected_component; remove others with: isabelle components -x DIR"
  elif [[ "$(canonical_dir "${ic2_components[0]}" 2>/dev/null)" != "$expected_component" ]]; then
    problem "The registered ic2 component is ${ic2_components[0]}, not the tooling clone's. Move it: isabelle components -x ${ic2_components[0]} && isabelle components -u $expected_component"
  elif [[ ! -f "$expected_component/lib/ic2.jar" ]]; then
    problem "The ic2 JAR is not built; run: $TOOLING_ROOT/scripts/build-ic2.sh"
  elif [[ -n "$autocorrode_rev" && "$expected_component/lib/ic2.jar" -ot "$expected_component/etc/build.props" ]]; then
    problem "The ic2 JAR predates the component sources; rebuild: $TOOLING_ROOT/scripts/build-ic2.sh"
  else
    ok "One ic2 component registered from the tooling clone, JAR built"
  fi
  if [[ -x "$(command -v systemd-run 2>/dev/null)" ]] && memory_bound_available; then
    ok "systemd user scopes are available for the prover memory bound"
  else
    note "systemd-run --user is unavailable; ic2 servers will start without a memory bound"
  fi
fi

# --- I/Q plugin and token -----------------------------------------------------------

if [[ -n "$isabelle_home_user" ]]; then
  plugin_jar="$isabelle_home_user/jedit/jars/iq_plugin.jar"
  plugin_stamp="$plugin_jar.stamp"
  if [[ ! -f "$plugin_jar" ]]; then
    problem "I/Q plugin is missing; run $TOOLING_ROOT/scripts/install-iq-plugin.sh"
  elif [[ ! -f "$plugin_stamp" ]]; then
    problem "I/Q provenance stamp is missing; rerun $TOOLING_ROOT/scripts/install-iq-plugin.sh"
  elif [[ -z "$autocorrode_rev" ]]; then
    problem "Cannot verify the I/Q plugin until the AutoCorrode submodule is valid."
  else
    stamped_rev="$(sed -n 's/^autocorrode_revision=//p' "$plugin_stamp" | head -n 1)"
    stamped_version="$(sed -n 's/^isabelle_version=//p' "$plugin_stamp" | head -n 1)"
    if [[ "$stamped_rev" == "$autocorrode_rev" && "$stamped_version" == "$isabelle_version" ]]; then
      ok "I/Q plugin provenance matches AutoCorrode and Isabelle."
    else
      problem "I/Q plugin provenance is stale; rerun $TOOLING_ROOT/scripts/install-iq-plugin.sh"
    fi
  fi
fi

if [[ ! -f "$TOKEN_FILE" ]]; then
  problem "I/Q token is missing: $TOKEN_FILE (create: mkdir -p \$(dirname $TOKEN_FILE) && (umask 077; openssl rand -hex 32 > $TOKEN_FILE))"
elif [[ ! -s "$TOKEN_FILE" ]]; then
  problem "I/Q token is empty: $TOKEN_FILE"
elif [[ "$(file_mode "$TOKEN_FILE")" == "600" ]]; then
  ok "I/Q token exists with mode 600: $TOKEN_FILE"
else
  problem "I/Q token must have mode 600 (found $(file_mode "$TOKEN_FILE")): chmod 600 $TOKEN_FILE"
fi

# --- I/R virtual environment --------------------------------------------------------

if ! command -v python3 >/dev/null 2>&1; then
  problem "python3 is not on PATH."
elif ! python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)' >/dev/null 2>&1; then
  problem "Python 3.10 or newer is required."
elif ! command -v openssl >/dev/null 2>&1; then
  problem "OpenSSL is not on PATH."
elif [[ ! -x "$IR_VENV_DIR/bin/python3" ]]; then
  problem "I/R virtual environment is missing; run $TOOLING_ROOT/scripts/setup-ir-venv.sh"
elif [[ ! -f "$IR_VENV_DIR/.requirements-ir.sha256" ]]; then
  problem "I/R virtual environment has no lock fingerprint; rerun setup-ir-venv.sh"
elif [[ "$(<"$IR_VENV_DIR/.requirements-ir.sha256")" != "$(openssl dgst -sha256 "$IR_LOCK_FILE" | awk '{print $NF}')" ]]; then
  problem "I/R virtual environment is stale; rerun $TOOLING_ROOT/scripts/setup-ir-venv.sh"
elif "$IR_VENV_DIR/bin/python3" -c 'import mcp, prompt_toolkit; from mcp.server.fastmcp import Context, FastMCP' >/dev/null 2>&1 &&
     "$IR_VENV_DIR/bin/python3" -m pip check >/dev/null 2>&1; then
  ok "I/R imports succeed with $IR_VENV_DIR/bin/python3"
else
  problem "I/R imports fail in the tooling venv; rerun $TOOLING_ROOT/scripts/setup-ir-venv.sh"
fi

if ((failures == 0)); then
  if ((notes > 0)); then
    echo "All Isabelle tooling checks passed, with $notes note(s)."
  else
    echo "All Isabelle tooling checks passed."
  fi
  exit 0
fi
printf '%d tooling problem(s) found.\n' "$failures"
exit 1
