#!/usr/bin/env bash
#
# sync-upstream.sh
#
# Pulls the latest openai/codex mainline into your fork while keeping your
# feature branch on top of it.
#
#   Layout it assumes:
#     origin   = your fork (SurajSharmaP/codex)
#     upstream = openai/codex
#     main     = clean mirror of upstream (NO local changes live here)
#     $FEATURE = your feature branch, rebased onto the refreshed main
#
#   Usage:   bash sync-upstream.sh [feature-branch]
#            FEATURE defaults to 'quiet-tool-activity'.

set -euo pipefail

REPO_ROOT="${CODEX_REPO:-/mnt/d/Projects/Other/codex}"
FEATURE="${1:-quiet-tool-activity}"

cd "$REPO_ROOT"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

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
    log "Rebase clean. Force-push with lease when ready:"
    echo "    git push --force-with-lease origin $FEATURE"
  else
    die "Rebase hit conflicts. Resolve them, 'git rebase --continue', then force-push with lease."
  fi
else
  log "No branch '$FEATURE' yet — skipping rebase. (Create it first; see the README notes.)"
fi

log "Done. main is now level with upstream/main."
