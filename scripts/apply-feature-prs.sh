#!/usr/bin/env bash
# ============================================================================
#  apply-feature-prs.sh — pull selected upstream feature PRs into a build
# ============================================================================
#  Used by the release workflow: after checking out a tag, it merges the
#  listed upstream PRs on top, then applies fork-held patch files, so
#  releases include features that aren't merged (or released) upstream yet.
#
#  Safe by design:
#    - skips a PR that is already merged into the checkout (ancestry check)
#    - skips a PR whose changes are already present (reverse-patch check,
#      covers squash merges)
#    - skips a patch file whose changes are already present
#    - aborts loudly on a real conflict/apply failure so a broken build is
#      never shipped
#
#  Configuration:
#    CHESS_TUI_FEATURE_PRS="342 330 ..."   PR numbers (default: 342)
#    CHESS_TUI_PATCHES="patches/x.patch"   fork-held patches (default below)
#    CHESS_TUI_UPSTREAM=<git url>          upstream repo (default below)
#    CHESS_TUI_RAW_BASE=<url>              raw base for fetching patches
#                                          that are not in the checkout
#
#  Usage: bash apply-feature-prs.sh   (run from the repo checkout)
# ============================================================================
set -euo pipefail

UPSTREAM_URL="${CHESS_TUI_UPSTREAM:-https://github.com/thomas-mauran/chess-tui.git}"
PRS="${CHESS_TUI_FEATURE_PRS:-342}"
PATCHES="${CHESS_TUI_PATCHES:-patches/lichess-features.patch}"
RAW_BASE="${CHESS_TUI_RAW_BASE:-https://raw.githubusercontent.com/MightyRyder/chess-tui/main}"

if [ ! -d .git ]; then
  echo "error: must be run from a git checkout" >&2
  exit 1
fi

for pr in $PRS; do
  echo "==> feature PR #$pr"
  git fetch --no-tags "$UPSTREAM_URL" "refs/pull/$pr/head"
  pr_sha="$(git rev-parse FETCH_HEAD)"

  if git merge-base --is-ancestor "$pr_sha" HEAD 2>/dev/null; then
    echo "    already merged into this checkout — skipping"
    continue
  fi

  # content-based check (covers PRs merged upstream via squash)
  if curl -fsSL "https://github.com/thomas-mauran/chess-tui/pull/$pr.diff" -o "/tmp/pr-${pr}.diff" \
     && git apply --reverse --check "/tmp/pr-${pr}.diff" 2>/dev/null; then
    echo "    changes already present in this checkout — skipping"
    continue
  fi

  if git -c user.name="chess-tui build" -c user.email="build@localhost" \
        merge --no-edit "$pr_sha"; then
    echo "    merged ($pr_sha -> $(git rev-parse --short HEAD))"
  else
    git merge --abort 2>/dev/null || true
    echo "error: PR #$pr does not merge cleanly onto this commit — needs manual rebasing" >&2
    exit 1
  fi
done

for patch_path in $PATCHES; do
  echo "==> fork patch $patch_path"

  if [ -f "$patch_path" ]; then
    patch_file="$patch_path"
  else
    patch_file="/tmp/fork-patch-$(basename "$patch_path")"
    if ! curl -fsSL "$RAW_BASE/$patch_path" -o "$patch_file"; then
      echo "error: patch $patch_path not in checkout and not fetchable from $RAW_BASE" >&2
      exit 1
    fi
  fi

  # content-based check: does the patch already apply in reverse?
  if git apply --reverse --check "$patch_file" 2>/dev/null; then
    echo "    changes already present in this checkout — skipping"
    continue
  fi

  if git apply --check "$patch_file" 2>/dev/null; then
    git apply "$patch_file"
    echo "    applied"
  else
    echo "error: $patch_path does not apply onto this commit — needs rebasing" >&2
    exit 1
  fi
done

echo "feature PRs and fork patches applied"
