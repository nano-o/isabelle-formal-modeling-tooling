#!/usr/bin/env bash
set -euo pipefail

# Cut a release of the agent-host extension.
#
# A committed manifest cannot contain its own commit hash, so a release is a
# separate commit on the moving `release` branch: the source tree at the
# tagged source commit plus a generated extension/REVISION that records the
# tag, the source commit, and the hash of the Codex worker profile. The
# release commit is tagged vX.Y.Z. Marketplaces follow either the `release`
# channel (upgradable in place) or an immutable vX.Y.Z tag (remove and re-add
# to move). Nothing is pushed unless --push is given.

# shellcheck source=common.sh disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

RELEASE_BRANCH="release"
PUSH=false
REMOTE="origin"
TAG=""

usage() {
  cat <<'EOF'
Usage: release.sh vX.Y.Z [--push] [--remote NAME]

Requires a clean clone whose HEAD is the source commit to release, with
"X.Y.Z" as the version in both extension manifests and no existing tag vX.Y.Z.
Creates the release commit on the `release` branch, tags it, and prints (or
with --push runs) the push of the source branch, `release`, and the tag.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --push) PUSH=true; shift ;;
    --remote) [[ -n "${2:-}" ]] || die "--remote requires an argument"; REMOTE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    v*) TAG="$1"; shift ;;
    *) die "unknown argument: $1" ;;
  esac
done
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "release tag must look like vX.Y.Z, got: ${TAG:-nothing}"
VERSION="${TAG#v}"

cd "$TOOLING_ROOT"
[[ -z "$(git status --porcelain --ignore-submodules=none)" ]] || die "the clone is not clean; commit or stash first"
! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || die "tag already exists: $TAG"
source_branch="$(git symbolic-ref --short -q HEAD || true)"
[[ -n "$source_branch" && "$source_branch" != "$RELEASE_BRANCH" ]] || die "release from a source branch (detached HEAD or '$RELEASE_BRANCH' is not one)"
source_rev="$(git rev-parse HEAD)"

for manifest in extension/.claude-plugin/plugin.json extension/.codex-plugin/plugin.json; do
  declared="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("version",""))' "$manifest")"
  [[ "$declared" == "$VERSION" ]] || die "$manifest declares version '$declared', expected $VERSION"
done
./scripts/render-agents.sh --check >/dev/null
codex_agent_sha256="$(openssl dgst -sha256 extension/codex/ic2_prover.toml | awk '{print $NF}')"

work="$(mktemp -d "${TMPDIR:-/tmp}/isabelle-tooling-release.XXXXXX")"
trap 'git worktree remove --force "$work" 2>/dev/null || true; rm -rf -- "$work"' EXIT

if git rev-parse -q --verify "refs/heads/$RELEASE_BRANCH" >/dev/null; then
  git worktree add -q "$work" "$RELEASE_BRANCH"
  git -C "$work" rm -rq --ignore-unmatch .
else
  git worktree add -q --detach "$work" "$source_rev"
  git -C "$work" checkout -q --orphan "$RELEASE_BRANCH"
  git -C "$work" rm -rq --cached .
  find "$work" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
fi

git archive "$source_rev" | tar -x -C "$work"
# git archive turns the submodule into an empty directory; restore the gitlink.
autocorrode_rev="$(git ls-tree "$source_rev" AutoCorrode | awk '{print $3}')"
rmdir "$work/AutoCorrode" 2>/dev/null || true
cat >"$work/extension/REVISION" <<EOF
release_tag=$TAG
source_revision=$source_rev
codex_agent_sha256=$codex_agent_sha256
EOF
git -C "$work" add -A .
git -C "$work" update-index --add --cacheinfo "160000,$autocorrode_rev,AutoCorrode"
git -C "$work" -c commit.gpgsign=false commit -q -m "Release $TAG (source $source_rev)"
release_rev="$(git -C "$work" rev-parse HEAD)"
git tag -a -m "Release $TAG" "$TAG" "$release_rev" 2>/dev/null || git -c tag.gpgsign=false tag -a -m "Release $TAG" "$TAG" "$release_rev"

echo "Release $TAG: $release_rev on branch $RELEASE_BRANCH (source $source_rev)"
echo "Push with:"
print_command git push "$REMOTE" "$source_branch" "$RELEASE_BRANCH" "$TAG"
if [[ "$PUSH" == true ]]; then
  git push -q "$REMOTE" "$source_branch" "$RELEASE_BRANCH" "$TAG"
  echo "Pushed."
fi
