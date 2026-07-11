#!/usr/bin/env bash
#
# sync-upstream.sh
#
# Pulls the latest openai/codex mainline into your fork, rebases your feature
# branch on top, then rebuilds the release binary so the `codex-quiet` command
# reflects the freshly-synced code.
#
#   Layout it assumes:
#     origin   = your fork (SurajSharmaP/codex)
#     upstream = openai/codex
#     main     = mirror of upstream + the auto-sync workflow commit
#     $FEATURE = your feature branch, rebased onto the refreshed main
#
#   Usage:   bash sync-upstream.sh [feature-branch]
#            FEATURE defaults to 'quiet-tool-activity'.
#            SKIP_BUILD=1 to sync only and skip the (slow) cargo rebuild.

set -euo pipefail

REPO_ROOT="${CODEX_REPO:-/mnt/d/Projects/Other/codex}"
FEATURE="${1:-quiet-tool-activity}"
BIN_LINK_DIR="${BIN_DIR:-$HOME/.local/bin}"
LINK_NAME="codex-quiet"
BUILT_BIN="$REPO_ROOT/codex-rs/target/release/codex"

cd "$REPO_ROOT"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

# Rebuild the release binary and make sure the `codex-quiet` symlink resolves to
# it. The symlink normally auto-follows a rebuild; we (re)create it only if it is
# missing, and never clobber an unrelated file at that path.
rebuild_binary() {
  if [ "${SKIP_BUILD:-0}" = "1" ]; then
    log "SKIP_BUILD=1 set — leaving the existing binary in place."
    return 0
  fi
  log "Rebuilding release binary (first build after a big sync is slow) ..."
  ( cd "$REPO_ROOT/codex-rs" && cargo build --release -p codex-cli --bin codex )
  [ -x "$BUILT_BIN" ] || die "Build finished but $BUILT_BIN is missing."

  mkdir -p "$BIN_LINK_DIR"
  local link_path="$BIN_LINK_DIR/$LINK_NAME"
  if [ -L "$link_path" ] && [ "$(readlink "$link_path")" = "$BUILT_BIN" ]; then
    log "codex-quiet is up to date -> $BUILT_BIN"
  elif [ -e "$link_path" ]; then
    log "Left $link_path untouched (not our symlink). Point it yourself if intended:"
    echo "    ln -sfn \"$BUILT_BIN\" \"$link_path\""
  else
    ln -s "$BUILT_BIN" "$link_path"
    log "Linked $link_path -> $BUILT_BIN"
  fi
}

# Refuse to run with a dirty tree so nothing gets clobbered.
[ -z "$(git status --porcelain)" ] || die "Working tree is dirty. Commit or stash before syncing."

git remote get-url upstream >/dev/null 2>&1 || \
  die "No 'upstream' remote. Add it: git remote add upstream https://github.com/openai/codex.git"

log "Fetching upstream ..."
git fetch upstream --prune

log "Merging upstream/main into main ..."
git checkout main
# main carries one fork-only commit (the upstream-sync workflow), so a plain
# fast-forward won't apply. Merge is additive and never needs a force-push.
git merge --no-edit upstream/main

log "Pushing refreshed main to your fork ..."
git push origin main

if git show-ref --verify --quiet "refs/heads/$FEATURE"; then
  log "Rebasing '$FEATURE' onto the refreshed main ..."
  git checkout "$FEATURE"
  if git rebase main; then
    log "Rebase clean."
    rebuild_binary
    log "Publish the rebased branch when ready:"
    echo "    git push --force-with-lease origin $FEATURE"
  else
    die "Rebase hit conflicts. Resolve them, 'git rebase --continue', re-run this script (or 'cargo build --release -p codex-cli --bin codex'), then force-push with lease."
  fi
else
  log "No branch '$FEATURE' yet — skipping rebase and rebuild."
fi

log "Done. main is level with upstream/main; $FEATURE is rebased on top."
