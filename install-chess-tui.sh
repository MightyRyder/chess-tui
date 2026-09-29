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
#    LICHESS_TOKEN=<token>            save a Lichess API token non-interactively
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
printf '  %s[1/6]%s checking environment\n' "$CY" "$Z"

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

  printf '  %s[2/6]%s downloading  %s\n' "$CY" "$Z" "$ASSET"
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
  printf '  %s[3/6]%s verifying integrity\n' "$CY" "$Z"
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
  printf '  %s[4/6]%s installing to %s\n' "$CY" "$Z" "$DIR"
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
  printf '  %s[2/6]%s download skipped\n' "$CY" "$Z"
  printf '  %s[3/6]%s integrity skipped\n' "$CY" "$Z"
  printf '  %s[4/6]%s install skipped\n' "$CY" "$Z"
fi

# ---------------------------------------------------------------------------
# 5/6 · Lichess token (asked once, saved for every future run)
# ---------------------------------------------------------------------------
printf '  %s[5/6]%s Lichess setup\n' "$CY" "$Z"
LICHESS_CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/chess-tui"
LICHESS_CONF="$LICHESS_CONF_DIR/config.toml"

# test a token against the Lichess API:
#   prints "ok:<username>" when valid, "bad" when rejected, "offline" when unreachable
lichess_check() {
  local tok="$1" code tmpf
  tmpf="$(mktemp)"
  if command -v curl >/dev/null 2>&1; then
    code="$(curl -s -o "$tmpf" -w '%{http_code}' -m 10 -H "Authorization: Bearer $tok" \
      https://lichess.org/api/account 2>/dev/null || printf '000')"
  elif wget -qO- --timeout=10 --header="Authorization: Bearer $tok" \
      https://lichess.org/api/account > "$tmpf" 2>/dev/null; then
    code=200
  else
    code=000
  fi
  case "$code" in
    200) RES_USER="$(grep -o '"username"[[:space:]]*:[[:space:]]*"[^"]*"' "$tmpf" | head -n1 | cut -d'"' -f4)"
         rm -f "$tmpf"; printf 'ok:%s' "$RES_USER" ;;
    401|403) rm -f "$tmpf"; printf 'bad' ;;
    *) rm -f "$tmpf"; printf 'offline' ;;
  esac
}

TOKEN=""
if [ -n "${LICHESS_TOKEN:-}" ]; then
  RES="$(lichess_check "$LICHESS_TOKEN")"
  case "$RES" in
    ok:*) TOKEN="$LICHESS_TOKEN"; ok "token valid — welcome, ${RES#ok:}" ;;
    bad) warn "Lichess rejected the provided token — not saving it" ;;
    *) TOKEN="$LICHESS_TOKEN"; warn "couldn't reach lichess.org to test the token — saving it anyway" ;;
  esac
elif [ -f "$LICHESS_CONF" ] && grep -qE '^[[:space:]]*lichess_token[[:space:]]*=' "$LICHESS_CONF"; then
  EXISTING="$(sed -n 's/^[[:space:]]*lichess_token[[:space:]]*=[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}[[:space:]]*$/\1/p' "$LICHESS_CONF" | head -n1)"
  if [ -z "$EXISTING" ]; then
    ok "Lichess token already saved — keeping it"
  else
    RES="$(lichess_check "$EXISTING")"
    case "$RES" in
      ok:*) ok "Lichess token already saved — valid (${RES#ok:})" ;;
      bad) warn "the saved Lichess token is rejected by Lichess — re-run with a new one to replace it" ;;
      *) warn "Lichess token already saved (couldn't test it — lichess.org unreachable)" ;;
    esac
  fi
elif [ -t 0 ]; then
  TRIES=0
  while [ "$TRIES" -lt 3 ]; do
    printf '    optional: paste your Lichess API token (hidden input), Enter to skip\n'
    printf '    get one at %shttps://lichess.org/account/oauth/token%s\n' "$CY" "$Z"
    printf '    token: '
    IFS= read -rs TOKEN || TOKEN=""
    printf '\n'
    [ -z "$TOKEN" ] && break
    RES="$(lichess_check "$TOKEN")"
    case "$RES" in
      ok:*) ok "token valid — welcome, ${RES#ok:}"; break ;;
      bad) warn "Lichess rejected that token — try again, or press Enter to skip"; TOKEN=""; TRIES=$((TRIES + 1)) ;;
      *) warn "couldn't reach lichess.org to test the token — saving it anyway"; break ;;
    esac
  done
else
  warn "no terminal — skipping Lichess prompt (set LICHESS_TOKEN=... to save it unattended)"
fi

if [ -n "$TOKEN" ]; then
  mkdir -p "$LICHESS_CONF_DIR"
  ESC_TOKEN="$(printf '%s' "$TOKEN" | sed 's/[&"\\]/\\&/g')"
  LINE="lichess_token = \"$ESC_TOKEN\""
  if [ -f "$LICHESS_CONF" ] && grep -qE '^[[:space:]]*lichess_token[[:space:]]*=' "$LICHESS_CONF"; then
    TMP_CONF="$LICHESS_CONF.tmp.$$"
    sed "s#^[[:space:]]*lichess_token[[:space:]]*=.*#$LINE#" "$LICHESS_CONF" > "$TMP_CONF" && mv "$TMP_CONF" "$LICHESS_CONF"
  else
    printf '%s\n' "$LINE" >> "$LICHESS_CONF"
  fi
  chmod 600 "$LICHESS_CONF" 2>/dev/null || true
  ok "saved to $LICHESS_CONF — used automatically every time"
fi

# ---------------------------------------------------------------------------
# 6/6 · play
# ---------------------------------------------------------------------------
printf '  %s[6/6]%s ready to play\n' "$CY" "$Z"
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
