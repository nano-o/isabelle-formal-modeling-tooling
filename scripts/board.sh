#!/usr/bin/env bash
set -euo pipefail

# The coordination board: presence, posts and claims shared by every worktree
# of one repository, kept as plain files in the Git common directory. See
# docs/coordination-board.md for the design and the isabelle-coordination
# skill for when agents post and claim.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=common.sh disable=SC1091
source "$SCRIPT_DIR/common.sh"

BOARD_SUBDIR="isabelle-tooling/board"
HOOK_MARKER="isabelle-tooling board guard"
STALE_MINUTES="${ISABELLE_BOARD_STALE_MINUTES:-180}"
HANDLE_PATTERN='^[a-z0-9][a-z0-9._-]{0,63}$'
CURSOR_PATTERN='^[A-Za-z0-9][A-Za-z0-9._-]{0,80}$'
KIND_PATTERN='^[a-z][a-z-]{0,23}$'

usage() {
  cat <<'EOF'
Usage: board.sh [--project-root DIR] [--as HANDLE] [--if-board] ACTION [ARGS...]

The coordination board of a repository: presence, posts and claims shared by
the main checkout and every linked worktree. It lives in the Git common
directory (<common dir>/isabelle-tooling/board) or at $ISABELLE_BOARD_DIR.
Writing actions need an agent handle: --as HANDLE or $ISABELLE_BOARD_AGENT.
--if-board makes a writing action a silent success when the repository has
no board yet (used by ic2.sh).

Actions:
  path                          Print the board directory
  hello --task TEXT             Register presence: worktree, branch, task
  bye [MESSAGE]                 Release my claims, remove my presence, post a farewell
  who                           List agents with their worktree, task and last activity
  post [--kind KIND] [--re RESOURCE] MESSAGE...
                                Post a note; MESSAGE `-` reads the body from stdin
  show [--last N | --all]       Render agents, claims and recent posts (default last 20)
  digest [--cursor NAME] [--mark] [--full]
                                Print what is new since the cursor (--mark advances it);
                                silent when nothing is; --full ignores the cursor
  claim [--force] --reason TEXT RESOURCE...
                                Take a lease on files, directories, refs or tokens
  release RESOURCE... | --all   End leases
  claims                        List claims, marking stale ones
  guard [--staged] [PATH...]    Fail when a path, or the current branch, is claimed by
                                another agent (the pre-commit hook runs `guard --staged`)
  install-hook [--force]        Install the shared pre-commit guard for this repository
  uninstall-hook                Remove it

Resources: a path relative to the worktree root (an existing directory is
recorded with a trailing slash and covers what is below it), a ref such as
refs/heads/main, a token such as jedit, or path#fragment for a passage
(advisory: shown, never enforced). A claim is stale once its owner has shown
no board activity for $ISABELLE_BOARD_STALE_MINUTES minutes (default 180) or
has said bye; stale claims do not block and may be taken over.
EOF
}

HANDLE="${ISABELLE_BOARD_AGENT:-}"
IF_BOARD=false
requested_root=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root) [[ -n "${2:-}" ]] || die "--project-root requires an argument"; requested_root="$2"; shift 2 ;;
    --project-root=*) requested_root="${1#--project-root=}"; shift ;;
    --as) [[ -n "${2:-}" ]] || die "--as requires an argument"; HANDLE="$2"; shift 2 ;;
    --as=*) HANDLE="${1#--as=}"; shift ;;
    --if-board) IF_BOARD=true; shift ;;
    -h|--help|help) usage; exit 0 ;;
    --) shift; break ;;
    -*) die "unknown option: $1" ;;
    *) break ;;
  esac
done
[[ $# -gt 0 ]] || { usage >&2; exit 2; }
[[ "$STALE_MINUTES" =~ ^[0-9]+$ ]] ||
  die "ISABELLE_BOARD_STALE_MINUTES must be a non-negative integer, found: $STALE_MINUTES"
require_command git
require_command openssl

# ---------------------------------------------------------------------------
# Resolution: the worktree we act from and the board directory

if [[ -n "$requested_root" ]]; then
  START_DIR="$(canonical_dir "$requested_root")" || die "--project-root: not a directory: $requested_root"
else
  START_DIR="$(pwd -P)"
fi
WORKTREE_ROOT=""
COMMON_DIR=""
if WORKTREE_ROOT="$(git -C "$START_DIR" rev-parse --show-toplevel 2>/dev/null)"; then
  COMMON_DIR="$(git -C "$START_DIR" rev-parse --path-format=absolute --git-common-dir)"
fi
if [[ -n "${ISABELLE_BOARD_DIR:-}" ]]; then
  BOARD_DIR="${ISABELLE_BOARD_DIR%/}"
  [[ -n "$WORKTREE_ROOT" ]] || WORKTREE_ROOT="$START_DIR"
else
  [[ -n "$COMMON_DIR" ]] || die "not inside a Git worktree: $START_DIR
The board lives in the repository's Git common directory. Run from inside a
checkout, pass --project-root DIR, or set ISABELLE_BOARD_DIR."
  BOARD_DIR="$COMMON_DIR/$BOARD_SUBDIR"
fi

board_exists() { [[ -d "$BOARD_DIR/posts" ]]; }
ensure_board() { mkdir -p "$BOARD_DIR/agents" "$BOARD_DIR/posts" "$BOARD_DIR/claims" "$BOARD_DIR/cursors"; }

# A writing action with --if-board is a silent success without a board.
skip_without_board() {
  if [[ "$IF_BOARD" == true ]] && ! board_exists; then
    exit 0
  fi
}

# ---------------------------------------------------------------------------
# Small helpers

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
now_stamp() { date -u +%Y%m%dT%H%M%S.%6NZ; }
one_line() { printf '%s' "$1" | tr '\n\r' '  '; }
hash8() { printf '%s' "$1" | openssl dgst -sha256 | awk '{print substr($NF, 1, 8)}'; }
field() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -n 1; }
mtime_iso() { date -u -d "@$(stat -c %Y "$1")" +%Y-%m-%dT%H:%M:%SZ; }

require_handle() {
  [[ -n "$HANDLE" ]] || die "this action needs an agent handle: pass --as HANDLE or set ISABELLE_BOARD_AGENT"
  [[ "$HANDLE" =~ $HANDLE_PATTERN ]] || die "invalid handle: $HANDLE (lowercase letters, digits, '.', '_', '-'; at most 64 characters)"
}

branch_of() {
  git -C "$1" symbolic-ref -q --short HEAD 2>/dev/null || printf 'detached\n'
}

# ---------------------------------------------------------------------------
# Presence

presence_file() { printf '%s/agents/%s\n' "$BOARD_DIR" "$1"; }

write_presence() {
  local handle="$1" worktree="$2" task="$3" tmp
  tmp="$(mktemp "$BOARD_DIR/agents/.tmp.XXXXXX")"
  printf 'handle=%s\nworktree=%s\nbranch=%s\ntask=%s\nsince=%s\n' \
    "$handle" "$worktree" "$(branch_of "$worktree")" "$(one_line "$task")" "$(now_iso)" >"$tmp"
  mv -f "$tmp" "$(presence_file "$handle")"
}

# Any action by a handle counts as activity for staleness.
touch_presence() {
  local file
  file="$(presence_file "$HANDLE")"
  [[ ! -f "$file" ]] || touch "$file"
}

# A claim without presence would be stale at once, so claiming records a
# minimal presence when the agent skipped hello.
ensure_presence() {
  [[ -f "$(presence_file "$HANDLE")" ]] || write_presence "$HANDLE" "$WORKTREE_ROOT" "(no task recorded; use hello --task)"
}

is_stale() {
  local file age
  file="$(presence_file "$1")"
  [[ -f "$file" ]] || return 0
  age=$(( $(date +%s) - $(stat -c %Y "$file") ))
  [[ "$age" -gt $((STALE_MINUTES * 60)) ]]
}

list_agents() {
  [[ -d "$BOARD_DIR/agents" ]] || return 0
  find "$BOARD_DIR/agents" -maxdepth 1 -type f ! -name '.*' -printf '%f\n' | LC_ALL=C sort
}

# The one active agent whose presence names this worktree, or nothing.
infer_handle() {
  local handle candidate=""
  while IFS= read -r handle; do
    [[ -n "$handle" ]] || continue
    [[ "$(field "$(presence_file "$handle")" worktree)" == "$WORKTREE_ROOT" ]] || continue
    is_stale "$handle" && continue
    [[ -z "$candidate" ]] || { printf '\n'; return 0; }
    candidate="$handle"
  done < <(list_agents)
  printf '%s\n' "$candidate"
}

render_agents() {
  local handle file mark
  while IFS= read -r handle; do
    [[ -n "$handle" ]] || continue
    file="$(presence_file "$handle")"
    mark=""
    is_stale "$handle" && mark="  [stale]"
    printf '  %s  %s (%s)  last active %s%s\n    %s\n' "$handle" "$(field "$file" worktree)" \
      "$(field "$file" branch)" "$(mtime_iso "$file")" "$mark" "$(field "$file" task)"
  done < <(list_agents)
}

# ---------------------------------------------------------------------------
# Posts

write_post() {
  local kind="$1" re="$2" message="$3" name tmp
  name="$(now_stamp)-$HANDLE-$(printf '%05x' $(( (RANDOM << 15) | RANDOM )))"
  tmp="$BOARD_DIR/posts/.tmp.$name"
  printf 'time=%s\nfrom=%s\nkind=%s\nre=%s\n\n%s\n' "$(now_iso)" "$HANDLE" "$kind" "$re" "$message" >"$tmp"
  mv -f "$tmp" "$BOARD_DIR/posts/$name.md"
  printf '%s.md\n' "$name"
}

list_posts() {
  [[ -d "$BOARD_DIR/posts" ]] || return 0
  find "$BOARD_DIR/posts" -maxdepth 1 -type f -name '*.md' -printf '%f\n' | LC_ALL=C sort
}

render_post() {
  local file="$1" line key value time="" from="" kind="" re="" in_body=false
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$in_body" == true ]]; then
      printf '    %s\n' "$line"
    elif [[ -z "$line" ]]; then
      in_body=true
      printf -- '- %s  %s  [%s]%s\n' "$time" "$from" "$kind" "${re:+  re: $re}"
    else
      key="${line%%=*}"
      value="${line#*=}"
      case "$key" in
        time) time="$value" ;;
        from) from="$value" ;;
        kind) kind="$value" ;;
        re) re="$value" ;;
      esac
    fi
  done <"$file"
  [[ "$in_body" == true ]] || printf -- '- %s  %s  [%s]%s\n' "$time" "$from" "$kind" "${re:+  re: $re}"
}

render_posts() {
  local name
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    render_post "$BOARD_DIR/posts/$name"
  done
}

# ---------------------------------------------------------------------------
# Resources and claims

# normalize_resource RAW: a ref stays as written; an existing path becomes
# relative to the worktree root (a directory gets a trailing slash); anything
# else, a token or a path that does not exist yet, is kept minus a leading
# "./". A "#fragment" suffix is carried through.
normalize_resource() {
  local raw="$1" fragment="" candidate path
  [[ -n "$raw" ]] || die "empty resource"
  if [[ "$raw" == *'#'* ]]; then
    fragment="#${raw#*#}"
    raw="${raw%%#*}"
  fi
  case "$raw" in
    refs/*)
      printf '%s%s\n' "$raw" "$fragment"
      return 0
      ;;
  esac
  candidate="$raw"
  [[ "$candidate" == /* ]] || candidate="$START_DIR/$candidate"
  if [[ -e "$candidate" ]]; then
    path="$(realpath --relative-to="$WORKTREE_ROOT" "$candidate")"
    [[ "$path" != ".." && "$path" != ../* ]] || die "resource lies outside the worktree $WORKTREE_ROOT: $raw"
    if [[ -d "$candidate" ]]; then
      [[ "$path" == "." ]] && path=""
      path="${path%/}/"
    fi
    printf '%s%s\n' "$path" "$fragment"
    return 0
  fi
  printf '%s%s\n' "${raw#./}" "$fragment"
}

claim_dir() { printf '%s/claims/%s-%s\n' "$BOARD_DIR" "$(sanitize_name "$1")" "$(hash8 "$1")"; }

list_claim_dirs() {
  [[ -d "$BOARD_DIR/claims" ]] || return 0
  find "$BOARD_DIR/claims" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | LC_ALL=C sort
}

write_claim_fields() {
  local dir="$1" resource="$2" reason="$3"
  printf '%s\n' "$resource" >"$dir/resource"
  printf '%s\n' "$HANDLE" >"$dir/owner"
  printf '%s\n' "$(one_line "$reason")" >"$dir/reason"
  now_iso >"$dir/since"
}

read_claim() {
  # Sets CLAIM_RESOURCE, CLAIM_OWNER, CLAIM_REASON, CLAIM_SINCE; fails on a
  # directory another process is still filling.
  local dir="$1"
  [[ -f "$dir/resource" && -f "$dir/owner" ]] || return 1
  CLAIM_RESOURCE="$(<"$dir/resource")"
  CLAIM_OWNER="$(<"$dir/owner")"
  CLAIM_REASON="$(cat "$dir/reason" 2>/dev/null || true)"
  CLAIM_SINCE="$(cat "$dir/since" 2>/dev/null || true)"
}

render_claims() {
  local dir mark
  while IFS= read -r dir; do
    [[ -n "$dir" ]] || continue
    read_claim "$dir" || continue
    mark=""
    is_stale "$CLAIM_OWNER" && mark="  [stale]"
    printf '  %s  held by %s since %s%s\n    %s\n' "$CLAIM_RESOURCE" "$CLAIM_OWNER" "$CLAIM_SINCE" "$mark" "$CLAIM_REASON"
  done < <(list_claim_dirs)
}

# resource_covers CLAIMED TARGET: exact match, or either side is a directory
# prefix of the other.
resource_covers() {
  local claimed="$1" target="$2"
  [[ "$claimed" == "$target" ]] && return 0
  [[ "$claimed" == */ && "$target" == "$claimed"* ]] && return 0
  [[ "$target" == */ && "$claimed" == "$target"* ]] && return 0
  return 1
}

# ---------------------------------------------------------------------------
# Actions

do_path() {
  [[ $# -eq 0 ]] || die "path takes no arguments"
  printf '%s\n' "$BOARD_DIR"
}

do_hello() {
  local task="" worktree="$WORKTREE_ROOT"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --task) [[ -n "${2:-}" ]] || die "--task requires an argument"; task="$2"; shift 2 ;;
      --task=*) task="${1#--task=}"; shift ;;
      --worktree) [[ -n "${2:-}" ]] || die "--worktree requires an argument"
        worktree="$(canonical_dir "$2")" || die "--worktree: not a directory: $2"; shift 2 ;;
      *) die "hello: unexpected argument: $1" ;;
    esac
  done
  [[ -n "$task" ]] || die "hello needs --task TEXT: one line saying what you are doing"
  require_handle
  skip_without_board
  ensure_board
  write_presence "$HANDLE" "$worktree" "$task"
  write_post hello "" "$(one_line "$task") (worktree $worktree, branch $(branch_of "$worktree"))" >/dev/null
  printf 'hello %s: %s (%s, branch %s)\n' "$HANDLE" "$(one_line "$task")" "$worktree" "$(branch_of "$worktree")"
}

release_all_mine() {
  # Prints the released resources, one per line.
  local dir
  while IFS= read -r dir; do
    [[ -n "$dir" ]] || continue
    read_claim "$dir" || continue
    [[ "$CLAIM_OWNER" == "$HANDLE" ]] || continue
    rm -rf -- "$dir"
    printf '%s\n' "$CLAIM_RESOURCE"
  done < <(list_claim_dirs)
}

do_bye() {
  local message="${*:-leaving}" released
  require_handle
  skip_without_board
  board_exists || die "no board at $BOARD_DIR"
  released="$(release_all_mine | paste -sd, -)"
  rm -f -- "$(presence_file "$HANDLE")"
  write_post bye "" "$(one_line "$message")${released:+ (released: $released)}" >/dev/null
  printf 'bye %s%s\n' "$HANDLE" "${released:+; released: $released}"
}

do_who() {
  [[ $# -eq 0 ]] || die "who takes no arguments"
  board_exists || { printf 'no board yet at %s\n' "$BOARD_DIR"; return 0; }
  render_agents
}

do_post() {
  local kind="note" re="" message
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --kind) [[ -n "${2:-}" ]] || die "--kind requires an argument"; kind="$2"; shift 2 ;;
      --kind=*) kind="${1#--kind=}"; shift ;;
      --re) [[ -n "${2:-}" ]] || die "--re requires an argument"; re="$2"; shift 2 ;;
      --re=*) re="${1#--re=}"; shift ;;
      --) shift; break ;;
      -) break ;;
      -*) die "post: unknown option: $1" ;;
      *) break ;;
    esac
  done
  [[ "$kind" =~ $KIND_PATTERN ]] || die "invalid kind: $kind (lowercase letters and '-')"
  if [[ $# -eq 1 && "$1" == "-" ]]; then
    message="$(cat)"
  else
    message="$*"
  fi
  [[ -n "${message//[[:space:]]/}" ]] || die "post needs a message (or - to read it from stdin)"
  require_handle
  skip_without_board
  ensure_board
  [[ -z "$re" ]] || re="$(normalize_resource "$re")"
  touch_presence
  printf 'posted %s\n' "$(write_post "$kind" "$re" "$message")"
}

do_show() {
  local last=20 all=false total shown
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --last) [[ "${2:-}" =~ ^[0-9]+$ ]] || die "--last requires a number"; last="$2"; shift 2 ;;
      --last=*) last="${1#--last=}"; [[ "$last" =~ ^[0-9]+$ ]] || die "--last requires a number"; shift ;;
      --all) all=true; shift ;;
      *) die "show: unexpected argument: $1" ;;
    esac
  done
  board_exists || { printf 'no board yet at %s\n' "$BOARD_DIR"; return 0; }
  [[ -z "$HANDLE" ]] || touch_presence
  printf 'Coordination board: %s\n' "$BOARD_DIR"
  printf '\nAgents (%s)\n' "$(list_agents | grep -c . || true)"
  render_agents
  printf '\nClaims (%s)\n' "$(list_claim_dirs | grep -c . || true)"
  render_claims
  total="$(list_posts | grep -c . || true)"
  if [[ "$all" == true || "$total" -le "$last" ]]; then
    shown="$total"
  else
    shown="$last"
  fi
  printf '\nPosts (%s of %s)\n' "$shown" "$total"
  list_posts | tail -n "$shown" | render_posts
}

do_digest() {
  local cursor="" mark=false full=false cursor_file last_seen="" new_posts newest count tmp
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cursor) [[ -n "${2:-}" ]] || die "--cursor requires an argument"; cursor="$2"; shift 2 ;;
      --cursor=*) cursor="${1#--cursor=}"; shift ;;
      --mark) mark=true; shift ;;
      --full) full=true; shift ;;
      *) die "digest: unexpected argument: $1" ;;
    esac
  done
  [[ -n "$cursor" ]] || cursor="$HANDLE"
  [[ -n "$cursor" ]] || die "digest needs --cursor NAME or an agent handle"
  [[ "$cursor" =~ $CURSOR_PATTERN ]] || die "invalid cursor name: $cursor"
  board_exists || return 0
  [[ -z "$HANDLE" ]] || touch_presence
  cursor_file="$BOARD_DIR/cursors/$cursor"
  [[ ! -f "$cursor_file" || "$full" == true ]] || last_seen="$(<"$cursor_file")"
  if [[ -z "$last_seen" ]]; then
    new_posts="$(list_posts | tail -n 10)"
  else
    new_posts="$(list_posts | awk -v seen="$last_seen" '$0 > seen')"
  fi
  count="$(printf '%s' "$new_posts" | grep -c . || true)"
  # Advance the cursor before printing, so a consumer that stops reading early
  # does not get the same posts again next time.
  if [[ "$mark" == true ]]; then
    newest="$(list_posts | tail -n 1)"
    mkdir -p "$BOARD_DIR/cursors"
    tmp="$(mktemp "$BOARD_DIR/cursors/.tmp.XXXXXX")"
    printf '%s\n' "${newest:-$last_seen}" >"$tmp"
    mv -f "$tmp" "$cursor_file"
  fi
  [[ "$count" -gt 0 || -z "$last_seen" ]] || return 0
  printf 'Coordination board (%s): %s new post(s)\n' "$BOARD_DIR" "$count"
  printf '\nAgents\n'
  render_agents
  printf '\nClaims\n'
  render_claims
  if [[ "$count" -gt 0 ]]; then
    printf '\nPosts\n'
    printf '%s\n' "$new_posts" | render_posts
  fi
}

do_claim() {
  local force=false reason="" resources=() resource dir failed=0 how
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force) force=true; shift ;;
      --reason) [[ -n "${2:-}" ]] || die "--reason requires an argument"; reason="$2"; shift 2 ;;
      --reason=*) reason="${1#--reason=}"; shift ;;
      --) shift; resources+=("$@"); break ;;
      -*) die "claim: unknown option: $1" ;;
      *) resources+=("$1"); shift ;;
    esac
  done
  [[ -n "$reason" ]] || die "claim needs --reason TEXT: one line saying why and for how long"
  [[ ${#resources[@]} -gt 0 ]] || die "claim needs at least one RESOURCE"
  require_handle
  skip_without_board
  ensure_board
  ensure_presence
  touch_presence
  for resource in "${resources[@]}"; do
    resource="$(normalize_resource "$resource")"
    dir="$(claim_dir "$resource")"
    if mkdir "$dir" 2>/dev/null; then
      write_claim_fields "$dir" "$resource" "$reason"
      write_post claim "$resource" "$(one_line "$reason")" >/dev/null
      printf 'claimed %s\n' "$resource"
      continue
    fi
    if ! read_claim "$dir"; then
      printf 'CONTESTED: %s is being claimed by another agent right now; retry\n' "$resource" >&2
      failed=1
      continue
    fi
    if [[ "$CLAIM_OWNER" == "$HANDLE" ]]; then
      printf '%s\n' "$(one_line "$reason")" >"$dir/reason"
      printf 'already held by you: %s (reason updated)\n' "$resource"
      continue
    fi
    if is_stale "$CLAIM_OWNER"; then
      how="stale since $(is_stale_reason "$CLAIM_OWNER")"
    elif [[ "$force" == true ]]; then
      how="forced"
    else
      printf 'HELD: %s is held by %s since %s: %s\n' "$resource" "$CLAIM_OWNER" "$CLAIM_SINCE" "$CLAIM_REASON" >&2
      failed=1
      continue
    fi
    write_claim_fields "$dir" "$resource" "$reason"
    write_post claim "$resource" "took over from $CLAIM_OWNER ($how): $(one_line "$reason")" >/dev/null
    printf 'took over %s from %s (%s)\n' "$resource" "$CLAIM_OWNER" "$how"
  done
  [[ "$failed" -eq 0 ]] || { printf 'board: wait for the release, coordinate with a post, or take over with --force and a reason.\n' >&2; exit 1; }
}

is_stale_reason() {
  local file
  file="$(presence_file "$1")"
  if [[ -f "$file" ]]; then
    printf 'last activity %s' "$(mtime_iso "$file")"
  else
    printf 'the owner left the board'
  fi
}

do_release() {
  local all=false resources=() resource dir released
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --all) all=true; shift ;;
      --) shift; resources+=("$@"); break ;;
      -*) die "release: unknown option: $1" ;;
      *) resources+=("$1"); shift ;;
    esac
  done
  require_handle
  skip_without_board
  board_exists || die "no board at $BOARD_DIR"
  touch_presence
  if [[ "$all" == true ]]; then
    [[ ${#resources[@]} -eq 0 ]] || die "release: --all takes no resources"
    released="$(release_all_mine | paste -sd, -)"
    [[ -z "$released" ]] || write_post release "" "released all: $released" >/dev/null
    printf 'released: %s\n' "${released:-nothing held}"
    return 0
  fi
  [[ ${#resources[@]} -gt 0 ]] || die "release needs RESOURCE... or --all"
  for resource in "${resources[@]}"; do
    resource="$(normalize_resource "$resource")"
    dir="$(claim_dir "$resource")"
    if [[ ! -d "$dir" ]] || ! read_claim "$dir"; then
      printf 'not claimed: %s\n' "$resource"
      continue
    fi
    [[ "$CLAIM_OWNER" == "$HANDLE" ]] || die "$resource is held by $CLAIM_OWNER, not by you; take it over with claim --force first"
    rm -rf -- "$dir"
    write_post release "$resource" "released" >/dev/null
    printf 'released %s\n' "$resource"
  done
}

do_claims() {
  [[ $# -eq 0 ]] || die "claims takes no arguments"
  board_exists || { printf 'no board yet at %s\n' "$BOARD_DIR"; return 0; }
  render_claims
}

do_guard() {
  local staged=false targets=() target dir blocked=0 me inferred=false ref path advisory
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --staged) staged=true; shift ;;
      --) shift; targets+=("$@"); break ;;
      -*) die "guard: unknown option: $1" ;;
      *) targets+=("$(normalize_resource "$1")"); shift ;;
    esac
  done
  board_exists || return 0
  if [[ "$staged" == true ]]; then
    while IFS= read -r -d '' path; do
      [[ -n "$path" ]] || continue
      targets+=("$path")
    done < <(git -C "$WORKTREE_ROOT" diff --cached --name-only --no-renames -z)
    ref="$(git -C "$WORKTREE_ROOT" symbolic-ref -q HEAD 2>/dev/null || true)"
    [[ -z "$ref" ]] || targets+=("$ref")
  fi
  [[ ${#targets[@]} -gt 0 ]] || return 0
  me="$HANDLE"
  if [[ -z "$me" ]]; then
    me="$(infer_handle)"
    inferred=true
  fi
  while IFS= read -r dir; do
    [[ -n "$dir" ]] || continue
    read_claim "$dir" || continue
    [[ "$CLAIM_OWNER" != "$me" ]] || continue
    advisory=false
    [[ "$CLAIM_RESOURCE" != *'#'* ]] || advisory=true
    for target in "${targets[@]}"; do
      resource_covers "${CLAIM_RESOURCE%%#*}" "$target" || continue
      if [[ "$advisory" == true ]]; then
        printf 'board: note: %s holds a passage of %s (%s): %s\n' "$CLAIM_OWNER" "$target" "${CLAIM_RESOURCE#*#}" "$CLAIM_REASON" >&2
      elif is_stale "$CLAIM_OWNER"; then
        printf 'board: ignoring stale claim on %s by %s (%s)\n' "$CLAIM_RESOURCE" "$CLAIM_OWNER" "$(is_stale_reason "$CLAIM_OWNER")" >&2
      else
        printf 'board: refusing: %s is claimed by %s since %s: %s\n' "$CLAIM_RESOURCE" "$CLAIM_OWNER" "$CLAIM_SINCE" "$CLAIM_REASON" >&2
        blocked=1
      fi
      break
    done
  done < <(list_claim_dirs)
  [[ "$blocked" -eq 0 ]] && return 0
  if [[ -z "$me" ]]; then
    printf 'board: your handle is unknown (no single active agent registered this worktree); if one of these claims is yours, set ISABELLE_BOARD_AGENT=<handle> or pass --as\n' >&2
  elif [[ "$inferred" == true ]]; then
    printf 'board: you are taken to be %s, the agent registered for this worktree\n' "$me" >&2
  fi
  printf 'board: wait for the release, coordinate with a post (board.sh show), or bypass with --no-verify and post why.\n' >&2
  return 1
}

hooks_dir() { git -C "$WORKTREE_ROOT" rev-parse --path-format=absolute --git-path hooks; }

do_install_hook() {
  local force=false dir hook tmp
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force) force=true; shift ;;
      *) die "install-hook: unexpected argument: $1" ;;
    esac
  done
  [[ -n "$COMMON_DIR" ]] || die "install-hook needs a Git repository"
  dir="$(hooks_dir)"
  hook="$dir/pre-commit"
  mkdir -p "$dir"
  if [[ -e "$hook" ]] && ! grep -Fq "$HOOK_MARKER" "$hook"; then
    [[ "$force" == true ]] || die "a pre-commit hook already exists at $hook; re-run with --force to keep it as pre-commit.pre-board and chain it"
    [[ ! -e "$dir/pre-commit.pre-board" ]] || die "cannot chain: $dir/pre-commit.pre-board already exists"
    mv -- "$hook" "$dir/pre-commit.pre-board"
  fi
  tmp="$(mktemp "$dir/.tmp.XXXXXX")"
  cat >"$tmp" <<EOF
#!/usr/bin/env bash
# $HOOK_MARKER: installed by board.sh install-hook; remove with board.sh uninstall-hook.
# Refuses a commit that touches a path, or moves a branch, another agent has
# claimed on the coordination board. Silent when the repository has no board.
hook_dir="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd -P)"
if [[ -x "\$hook_dir/pre-commit.pre-board" ]]; then
  "\$hook_dir/pre-commit.pre-board" "\$@" || exit \$?
fi
exec $(printf '%q' "$SCRIPT_DIR/board.sh") guard --staged
EOF
  chmod 0755 "$tmp"
  mv -f "$tmp" "$hook"
  printf 'installed %s\n' "$hook"
  [[ ! -x "$dir/pre-commit.pre-board" ]] || printf 'chained the previous hook as %s\n' "$dir/pre-commit.pre-board"
}

do_uninstall_hook() {
  local dir hook
  [[ $# -eq 0 ]] || die "uninstall-hook takes no arguments"
  [[ -n "$COMMON_DIR" ]] || die "uninstall-hook needs a Git repository"
  dir="$(hooks_dir)"
  hook="$dir/pre-commit"
  if [[ ! -e "$hook" ]] || ! grep -Fq "$HOOK_MARKER" "$hook"; then
    printf 'no board hook installed at %s\n' "$hook"
    return 0
  fi
  rm -f -- "$hook"
  if [[ -e "$dir/pre-commit.pre-board" ]]; then
    mv -- "$dir/pre-commit.pre-board" "$hook"
    printf 'removed the board hook and restored the previous %s\n' "$hook"
  else
    printf 'removed %s\n' "$hook"
  fi
}

action="$1"
shift
case "$action" in
  path) do_path "$@" ;;
  hello) do_hello "$@" ;;
  bye) do_bye "$@" ;;
  who) do_who "$@" ;;
  post) do_post "$@" ;;
  show) do_show "$@" ;;
  digest) do_digest "$@" ;;
  claim) do_claim "$@" ;;
  release) do_release "$@" ;;
  claims) do_claims "$@" ;;
  guard) do_guard "$@" ;;
  install-hook) do_install_hook "$@" ;;
  uninstall-hook) do_uninstall_hook "$@" ;;
  *) die "unknown action: $action (see board.sh --help)" ;;
esac
