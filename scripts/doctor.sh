#!/usr/bin/env bash
set -uo pipefail

# shellcheck source=common.sh disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

# Doctor only reads: no bytecode caches, no index refreshes, no scratch files.
export PYTHONDONTWRITEBYTECODE=1 GIT_OPTIONAL_LOCKS=0
TOKEN_FILE="${IQ_TOKEN_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/isabelle-iq/auth-token}"
ALLOW_DIRTY=false
requested_root=""
failures=0
notes=0

usage() {
  cat <<'EOF'
Usage: doctor.sh [--project-root DIR] [--allow-dirty]

Check the project's descriptor and project files, ISABELLE_TOOLING_ROOT, the
host Isabelle, the tooling clone and its pinned AutoCorrode submodule, the host
configuration of both agent hosts, the single ic2 component registration and
its JAR, the I/Q plugin and token, the I/R virtual environment, and, when the
project has agent-board.conf, the coordination board. Reports what it found
and prints remediation commands; it never runs them, and it writes nothing.

  --project-root DIR  Checkout to diagnose (default: nearest descriptor above $PWD)
  --allow-dirty       Pass with a modified tooling clone or submodule, or skills
                      in link mode, marking the report
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
if resolve_error="$( (resolve_project "$requested_root") 2>&1 >/dev/null)"; then
  resolve_project "$requested_root"
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
  problem "${resolve_error#ERROR: }"
fi
expected_isabelle="${PROJECT_CONF[isabelle_version]:-Isabelle2025-2}"

# --- ISABELLE_TOOLING_ROOT ------------------------------------------------------------
#
# The project's .mcp.json, .codex/config.toml and worker profiles name the
# tooling only through this variable.

if [[ -z "${ISABELLE_TOOLING_ROOT:-}" ]]; then
  problem "ISABELLE_TOOLING_ROOT is not set; the project's I/Q server and proof worker need it. Set it in your shell profile: export ISABELLE_TOOLING_ROOT=$TOOLING_ROOT, then restart the host session."
elif [[ "$(canonical_dir "$ISABELLE_TOOLING_ROOT" 2>/dev/null)" != "$TOOLING_ROOT" ]]; then
  problem "ISABELLE_TOOLING_ROOT names $ISABELLE_TOOLING_ROOT, but this doctor runs from $TOOLING_ROOT; point it at the runtime checkout, or run that checkout's doctor."
else
  ok "ISABELLE_TOOLING_ROOT names this tooling checkout"
fi

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
dirty="$(git -C "$TOOLING_ROOT" --no-optional-locks status --porcelain --ignore-submodules=none 2>/dev/null; git -C "$AUTOCORRODE_DIR" --no-optional-locks status --porcelain 2>/dev/null | sed 's|^|AutoCorrode/|')"
if [[ -n "$dirty" ]]; then
  if [[ "$ALLOW_DIRTY" == true ]]; then
    note "Tooling clone or submodule is modified (--allow-dirty): $(printf '%s' "$dirty" | awk '{print $2}' | paste -sd' ')"
  else
    problem "Tooling clone or submodule is modified; scripts execute while HEAD still matches. Commit, or pass --allow-dirty: $(printf '%s' "$dirty" | awk '{print $2}' | paste -sd' ')"
  fi
else
  ok "Tooling clone and submodule are clean at $tooling_head"
fi
# --- project files ----------------------------------------------------------------------
#
# sync --check compares the skills, worker profiles, MCP declarations and the
# instruction block with the pinned Git object, and the runtime checkout with
# the pin: the one-active-runtime rule.

# relay PREFIX: pass [OK]/[NOTE]/[FAIL] lines from stdin through ok/note/problem.
relay() {
  local prefix="$1" line
  while IFS= read -r line; do
    case "$line" in
      "[OK]"*) ok "$prefix${line#"[OK]   "}" ;;
      "[NOTE]"*) note "$prefix${line#"[NOTE] "}" ;;
      "[FAIL]"*) problem "$prefix${line#"[FAIL] "}" ;;
      *) [[ -z "$line" ]] || problem "$prefix$line" ;;
    esac
  done
}

if [[ "$descriptor_ok" == true ]]; then
  check_args=(sync --check --project-root "$PROJECT_CHECKOUT_ROOT")
  [[ "$ALLOW_DIRTY" == true ]] && check_args+=(--allow-dirty)
  relay "Project files: " < <("$TOOLING_ROOT/bin/isabelle-tooling" "${check_args[@]}" 2>&1)
fi

# --- host configuration ------------------------------------------------------------------
#
# The project's files are the only delivery: an installed Isabelle plugin or
# its marketplace, a user-level iq server or a user-level proof-worker profile
# would duplicate them. CLAUDE_CONFIG_DIR and CODEX_HOME isolate fixtures.

relay "Host configuration: " < <(python3 - "${PROJECT_CHECKOUT_ROOT:-}" <<'PYEOF'
import json, os, sys, tomllib
from pathlib import Path
home = Path.home()
claude = Path(os.environ['CLAUDE_CONFIG_DIR']) if os.environ.get('CLAUDE_CONFIG_DIR') else home / '.claude'
claude_json = claude / '.claude.json' if os.environ.get('CLAUDE_CONFIG_DIR') else home / '.claude.json'
codex = Path(os.environ.get('CODEX_HOME') or home / '.codex')
project = sys.argv[1]
found = []


def load_json(path):
    try:
        return json.loads(path.read_text()) if path.is_file() else {}
    except (OSError, ValueError):
        print(f'[NOTE] cannot read {path}; its contents were not checked')
        return {}


def keys(data, *path):
    for key in path:
        data = data.get(key, {}) if isinstance(data, dict) else {}
    return list(data) if isinstance(data, dict) else []


plugin = lambda k: k.startswith('isabelle-formal-modeling@')
market = lambda k: k.startswith('isabelle-formal-modeling')
installed = load_json(claude / 'plugins/installed_plugins.json')
settings = load_json(claude / 'settings.json')
for key in sorted(set(keys(installed, 'plugins') + keys(settings, 'enabledPlugins'))):
    if plugin(key):
        found.append(f'Claude Code has the plugin {key} ({claude}); uninstall it: claude plugin uninstall {key}')
for key in sorted(set(keys(load_json(claude / 'plugins/known_marketplaces.json')) +
                      keys(settings, 'extraKnownMarketplaces'))):
    if market(key):
        found.append(f'Claude Code knows the marketplace {key} ({claude}); remove it: '
                     f'claude plugin marketplace remove {key}')
user = load_json(claude_json)
if 'iq' in keys(user, 'mcpServers'):
    found.append(f'Claude Code declares a user-level iq MCP server in {claude_json}; remove it: '
                 'claude mcp remove --scope user iq')
if project and 'iq' in keys(user, 'projects', project, 'mcpServers'):
    found.append(f'Claude Code declares a local iq MCP server for {project} in {claude_json}; remove it: '
                 'claude mcp remove --scope local iq')
config = codex / 'config.toml'
try:
    codex_config = tomllib.loads(config.read_text()) if config.is_file() else {}
except (OSError, tomllib.TOMLDecodeError):
    print(f'[NOTE] cannot read {config}; its contents were not checked')
    codex_config = {}
for key in keys(codex_config, 'plugins'):
    if plugin(key):
        found.append(f'Codex CLI has the plugin {key} in {config}; uninstall it and remove its [plugins] table')
for key in keys(codex_config, 'marketplaces'):
    if market(key):
        found.append(f'Codex CLI knows the marketplace {key} in {config}; remove its [marketplaces] table')
if 'iq' in keys(codex_config, 'mcp_servers'):
    found.append(f'Codex CLI declares a user-level iq MCP server in {config}; remove [mcp_servers.iq] there')
for path in sorted((claude / 'agents').glob('*.md')) if (claude / 'agents').is_dir() else []:
    if path.stem == 'ic2-prover' or '\nname: ic2-prover\n' in path.read_text(errors='replace'):
        found.append(f'a user-level Claude Code proof-worker profile duplicates the project one: move {path} aside')
for path in sorted((codex / 'agents').glob('*.toml')) if (codex / 'agents').is_dir() else []:
    if path.stem == 'ic2_prover' or '\nname = "ic2_prover"' in '\n' + path.read_text(errors='replace'):
        found.append(f'a user-level Codex CLI proof-worker profile duplicates the project one: move {path} aside')
for message in found:
    print(f'[FAIL] {message}')
if not found:
    print(f'[OK]   no Isabelle plugin, marketplace, user-level iq server or proof-worker profile ({claude}, {codex})')
PYEOF
)

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

# --- agent-board, optional ----------------------------------------------------------------
#
# Only when the project has agent-board.conf. The tooling never reads the
# board's storage or descriptor: it checks the interface and runs board doctor.

if [[ "$descriptor_ok" == true ]] && board_configured "$PROJECT_CHECKOUT_ROOT"; then
  board_interface=""
  board_missing=""
  if ! board="$(resolve_agent_board)"; then
    problem "board: this project has agent-board.conf, but agent-board does not resolve; put it on PATH or set AGENT_BOARD_COMMAND to its absolute path"
  elif ! board_version="$(timeout 10 "$board" version --json 2>/dev/null)" ||
       ! { read -r board_interface && read -r board_missing; } < <(printf '%s' "$board_version" | python3 -c '
import json, sys
data = json.load(sys.stdin)
print(data["interface"])
print(" ".join(sorted({"doctor", "project"} - set(data["capabilities"]))) or "-")' 2>/dev/null); then
    problem "board: $board version --json failed or printed no valid object"
  elif [[ "$board_interface" != "$AGENT_BOARD_INTERFACE" ]]; then
    problem "board: $board has interface $board_interface; this tooling supports interface $AGENT_BOARD_INTERFACE"
  elif [[ "$board_missing" != "-" ]]; then
    problem "board: $board lacks the capabilities: $board_missing"
  else
    board_args=(doctor --json --project-root "$PROJECT_CHECKOUT_ROOT")
    [[ "$ALLOW_DIRTY" == true ]] && board_args+=(--allow-dirty)
    board_rc=0
    board_report="$(timeout 60 "$board" "${board_args[@]}" 2>/dev/null)" || board_rc=$?
    if [[ "$board_rc" -ne 0 && "$board_rc" -ne 1 ]] ||
       ! board_lines="$(printf '%s' "$board_report" | python3 -c '
import json, sys
data = json.load(sys.stdin)
tags = {"ok": "[OK]  ", "note": "[NOTE]", "fail": "[FAIL]"}
for check in data["checks"]:
    print(tags[check["status"]], check["id"] + ":", " ".join(check["message"].split()))' 2>/dev/null)"; then
      problem "board: $board doctor could not run (exit $board_rc); run it yourself for details"
    else
      relay "board: " <<<"$board_lines"
    fi
  fi
elif [[ "$descriptor_ok" == true ]]; then
  ok "No agent-board.conf: this project does not use the coordination board"
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
