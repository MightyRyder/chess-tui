#!/usr/bin/env bash
# ============================================================================
#  ♞  chess-tui · portable installer
# ============================================================================
#  Downloads the prebuilt, size-optimized chess-tui binary (glibc 2.25+,
#  stripped, UPX-compressed) from GitHub releases and starts the game.
#
#  No compilers, no cargo, no crates.io — just a ~2 MB download.
#
#  Usage:   bash install-chess-tui.sh
#
#  Environment options:
#    CHESS_TUI_TAG=latest             release tag (default: latest, auto-resolved)
#    CHESS_TUI_DIR=$HOME/.local/bin   install directory (default)
#    CHESS_TUI_VARIANT=auto|sound|nosound
#                                     force a build variant (default: auto)
#    NO_LAUNCH=1                      install only, don't start the game
# ============================================================================
set -euo pipefail

REPO="MightyRyder/chess-tui"
DIR="${CHESS_TUI_DIR:-$HOME/.local/bin}"

# Optional pinned hashes (only used for releases that have no published .sha256)
SHA_SOUND=""
SHA_NOSOUND=""

# ---------------------------------------------------------------------------
# pretty output helpers
# ---------------------------------------------------------------------------
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ] && [ "${NO_COLOR:-}" = "" ]; then
  B=$'\033[1m'; D=$'\033[2m'; Z=$'\033[0m'
  CY=$'\033[36m'; GR=$'\033[32m'; YL=$'\033[33m'; RD=$'\033[31m'
else
  B=; D=; Z=; CY=; GR=; YL=; RD=
fi
say()  { printf '  %s\n' "$*"; }
info() { printf '  %s➜%s %s\n' "$CY" "$Z" "$*"; }
ok()   { printf '  %s✓%s %s\n' "$GR" "$Z" "$*"; }
warn() { printf '  %s!%s %s\n' "$YL" "$Z" "$*"; }
die()  { printf '\n  %s✗ %s%s\n\n' "$RD" "$*" "$Z"; exit 1; }

banner() {
  printf '\n'
  printf '   %s♞%s  %s%schess-tui%s  %s· portable installer%s\n' "$CY" "$Z" "$B" "$B" "$Z" "$D" "$Z"
  printf '  %s\n' "────────────────────────────────────────────────"
  say "${D}play chess in your terminal, no browser needed${Z}"
  say "${D}glibc 2.25+ · stripped · UPX-compressed · x86_64${Z}"
  printf '\n'
}

# ---------------------------------------------------------------------------
# 1/5 · environment
# ---------------------------------------------------------------------------
step=1
banner
printf '  %s[1/5]%s checking environment\n' "$CY" "$Z"

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) ARCH=x86_64 ;;
  *) die "unsupported architecture '$ARCH' — only x86_64 builds are published" ;;
esac

for need in tar; do
  command -v "$need" >/dev/null 2>&1 || die "'$need' is required but not found"
done
if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
  die "need 'curl' or 'wget' to download chess-tui"
fi

has_libasound() {
  local libs
  libs="$(ldconfig -p 2>/dev/null || true)"
  case "$libs" in *libasound.so.2*) return 0 ;; esac
  local d
  for d in /usr/lib/x86_64-linux-gnu /usr/lib64 /usr/lib /lib/x86_64-linux-gnu /lib64 /lib; do
    [ -e "$d/libasound.so.2" ] && return 0
  done
  return 1
}

VARIANT="${CHESS_TUI_VARIANT:-auto}"
case "$VARIANT" in
  auto)
    if has_libasound; then VARIANT=sound; else
      VARIANT=nosound
      warn "libasound.so.2 not found — using the no-sound build (game works, no move sounds)"
    fi ;;
  sound)
    has_libasound || die "CHESS_TUI_VARIANT=sound but libasound.so.2 is missing" ;;
  nosound) : ;;
  *) die "CHESS_TUI_VARIANT must be auto, sound or nosound" ;;
esac
ok "$ARCH · glibc target 2.25+ · ${VARIANT} build"

# ---------------------------------------------------------------------------
# resolve release tag: CHESS_TUI_TAG (default "latest") -> concrete tag
# ---------------------------------------------------------------------------
CHESS_TUI_TAG="${CHESS_TUI_TAG:-latest}"
TAG="$CHESS_TUI_TAG"
if [ "$TAG" = "latest" ]; then
  # prefer the releases/latest redirect header (no API rate limit), then the API
  if command -v curl >/dev/null 2>&1; then
    TAG="$(curl -fsSLI --max-time 15 "https://github.com/$REPO/releases/latest" 2>/dev/null \
      | tr -d '\r' | sed -n 's|^[Ll]ocation: .*/tag/\([^ ]*\)$|\1|p' | head -n1 || true)"
    [ -n "$TAG" ] || TAG="$(curl -fsSL --max-time 15 "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
      | grep -o '"tag_name": *"[^"]*"' | head -n1 | cut -d'"' -f4 || true)"
  else
    TAG="$(wget -qO- --timeout=15 "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
      | grep -o '"tag_name": *"[^"]*"' | head -n1 | cut -d'"' -f4 || true)"
  fi
  [ -n "$TAG" ] || { TAG="2.7.1"; warn "could not resolve the latest release — falling back to $TAG"; }
fi
info "release $TAG"

# ---------------------------------------------------------------------------
# fast path — already installed?
# ---------------------------------------------------------------------------
BIN="$DIR/chess-tui"
if [ -x "$BIN" ] && "$BIN" --version 2>/dev/null | grep -q "$TAG"; then
  ok "chess-tui $TAG already installed at $BIN"
  SKIP_INSTALL=1
else
  SKIP_INSTALL=0
fi

# ---------------------------------------------------------------------------
# 2/5 · download
# ---------------------------------------------------------------------------
if [ "$SKIP_INSTALL" = 0 ]; then
  SUFFIX=""
  [ "$VARIANT" = nosound ] && SUFFIX="-nosound"
  ASSET="chess-tui-$TAG-x86_64-unknown-linux-gnu-glibc2.25$SUFFIX.tar.xz"
  URL="https://github.com/$REPO/releases/download/$TAG/$ASSET"
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT

  printf '  %s[2/5]%s downloading  %s\n' "$CY" "$Z" "$ASSET"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --connect-timeout 15 --progress-bar -o "$TMP/$ASSET" "$URL" \
      || die "download failed — is github.com reachable from this machine?"
  else
    wget -q --show-progress -O "$TMP/$ASSET" "$URL" \
      || die "download failed — is github.com reachable from this machine?"
  fi
  ok "saved $(du -h "$TMP/$ASSET" | cut -f1 | tr -d ' ')"

  # -------------------------------------------------------------------------
  # 3/5 · integrity
  # -------------------------------------------------------------------------
  printf '  %s[3/5]%s verifying integrity\n' "$CY" "$Z"
  EXPECTED=""
  # 1) checksum published next to the release asset (preferred — always current)
  if command -v curl >/dev/null 2>&1; then
    EXPECTED="$(curl -fsSL --max-time 15 "$URL.sha256" 2>/dev/null | awk '{print $1}' | head -n1 || true)"
  else
    EXPECTED="$(wget -qO- --timeout=15 "$URL.sha256" 2>/dev/null | awk '{print $1}' | head -n1 || true)"
  fi
  # 2) pinned hashes for older releases that predate the .sha256 assets
  if [ -z "$EXPECTED" ] && [ "$TAG" = "2.7.1" ]; then
    if [ "$VARIANT" = nosound ]; then EXPECTED="$SHA_NOSOUND"; else EXPECTED="$SHA_SOUND"; fi
  fi
  if [ -z "$EXPECTED" ]; then
    warn "no checksum available for tag '$TAG' — skipping verification"
  else
    if command -v sha256sum >/dev/null 2>&1; then
      GOT="$(sha256sum "$TMP/$ASSET" | awk '{print $1}')"
    elif command -v shasum >/dev/null 2>&1; then
      GOT="$(shasum -a 256 "$TMP/$ASSET" | awk '{print $1}')"
    else
      GOT=""; warn "no sha256 tool found — skipping checksum"
    fi
    if [ -n "$GOT" ]; then
      if [ "$GOT" = "$EXPECTED" ]; then
        ok "sha256 verified"
      else
        warn "checksum differs from the published value (asset was likely rebuilt)"
        warn "expected $EXPECTED"
        warn "got      $GOT"
      fi
    fi
  fi

  # -------------------------------------------------------------------------
  # 4/5 · install
  # -------------------------------------------------------------------------
  printf '  %s[4/5]%s installing to %s\n' "$CY" "$Z" "$DIR"
  if command -v xz >/dev/null 2>&1; then
    tar -xJf "$TMP/$ASSET" -C "$TMP"
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$TMP/$ASSET" "$TMP" <<'PY'
import lzma, sys, tarfile
with lzma.open(sys.argv[1]) as f, tarfile.open(fileobj=f) as t:
    t.extractall(sys.argv[2])
PY
  else
    die "need 'xz' or 'python3' to extract the archive"
  fi
  mkdir -p "$DIR"
  install -m 0755 "$TMP/chess-tui" "$BIN" 2>/dev/null || { cp "$TMP/chess-tui" "$BIN"; chmod 0755 "$BIN"; }
  VER="$("$BIN" --version 2>&1)" || {
    if [ "$VARIANT" = sound ] && [ "${CHESS_TUI_RETRIED:-}" != "1" ] && [ -f "$0" ]; then
      warn "sound build failed to start — retrying with the no-sound build"
      export CHESS_TUI_RETRIED=1 CHESS_TUI_VARIANT=nosound
      exec bash "$0" "$@"
    fi
    die "installed binary failed to start:
      $VER"
  }
  ok "$VER ready"
else
  printf '  %s[2/5]%s download skipped\n' "$CY" "$Z"
  printf '  %s[3/5]%s integrity skipped\n' "$CY" "$Z"
  printf '  %s[4/5]%s install skipped\n' "$CY" "$Z"
fi

# ---------------------------------------------------------------------------
# 5/5 · play
# ---------------------------------------------------------------------------
printf '  %s[5/5]%s ready to play\n' "$CY" "$Z"
if command -v stockfish >/dev/null 2>&1; then
  ok "Stockfish found at $(command -v stockfish) — play vs. the computer!"
else
  warn "no Stockfish found — local 2-player works; add stockfish for a CPU opponent"
fi

printf '\n  %s' "$D"
printf '────────────────────────────────────────────────'; printf '%s\n\n' "$Z"

case ":$PATH:" in
  *":$DIR:"*) : ;;
  *) info "tip: add $DIR to your PATH to run 'chess-tui' directly" ;;
esac

if [ "${NO_LAUNCH:-}" = "1" ]; then
  info "run it any time:  $BIN"
  exit 0
fi

if [ -t 0 ] && [ -t 1 ]; then
  info "launching chess-tui ... ${D}(q to quit, when asked)${Z}"
  "$BIN" || true
  printf '\n'
  info "chess-tui exited — dropping you to a shell (type 'exit' to leave)"
  exec bash
else
  warn "no interactive terminal detected — installed only."
  info "run it from a terminal:  $BIN"
fi
