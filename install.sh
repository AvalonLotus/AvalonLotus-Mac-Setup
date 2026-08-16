#!/usr/bin/env bash
#
# AvalonLotus Mac Setup — bootstrap a new Mac in one command.
#
# Usage:
#   Recommended (verify-then-run):
#     git clone https://github.com/AvalonLotus/AvalonLotus-Mac-Setup.git "$HOME/AvalonLotus Mac-Setup"
#     bash "$HOME/AvalonLotus Mac-Setup/install.sh"
#
#   One-liner (faster but YOU MUST trust the source):
#     curl -fsSL avalonlotus.com/mac | bash
#
# What it does:
#   1. Installs Homebrew + git + jq if missing
#   2. Clones (or pulls) all your AvalonLotus repos
#   3. Runs each repo's setup script (git-autosync, Obsidian Vault, etc.)
#   4. Reports what worked vs failed at the end
#
# Idempotent — safe to re-run. Re-running pulls the latest of each repo
# and re-runs its setup. Setup scripts themselves should be idempotent
# (Homebrew, pip, font installers all are).

set -uo pipefail   # NOT -e — we want to continue past individual repo failures

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; DIM='\033[2m'; NC='\033[0m'
log()  { printf "${GREEN}▶${NC} %s\n" "$*"; }
ok()   { printf "  ${GREEN}✓${NC} %s\n" "$*"; }
warn() { printf "  ${YELLOW}!${NC} %s\n" "$*"; }
fail() { printf "  ${RED}✗${NC} %s\n" "$*"; }
dim()  { printf "${DIM}  %s${NC}\n" "$*"; }

# ─── Prereqs ──────────────────────────────────────────────────────────
log "Checking prereqs"
if ! command -v brew >/dev/null 2>&1; then
  log "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Make brew available in this shell
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi
ok "Homebrew at $(brew --prefix)"
command -v git >/dev/null 2>&1 || brew install git
ok "git $(git --version | awk '{print $3}')"
command -v jq  >/dev/null 2>&1 || brew install jq
ok "jq $(jq --version)"

# ─── Baseline apps & CLI tools (idempotent — brew skips if already present) ───
# Pinned to AvalonLotus's daily-driver set. Each line = either a brew formula
# (CLI tool) or a cask (.app in /Applications). To remove an item, just
# delete its line; brew install is no-op if the cask/formula is already there.
log "Installing baseline tools (CLI + macOS apps)"

# Hang-detection wrapper. macOS doesn't ship GNU `timeout` so we DIY with a
# subshell + sleep watchdog. If brew install hangs >5min on a single package
# (slow network, stuck on EULA prompt, sudo password expected, etc) the
# watchdog kills it instead of blocking the whole bootstrap for hours.
# 2026-05-26: added after Mac 2 install.sh sat zombie for hours on docker cask.
HANG_LIMIT=300  # seconds — generous enough for big downloads like Docker/OBS
run_with_timeout() {
  local label="$1"; shift
  local start=$(date +%s)
  ("$@" 2>&1 | tail -3) &
  local pid=$!
  (sleep "$HANG_LIMIT" && kill -0 "$pid" 2>/dev/null && {
    warn "    $label exceeded ${HANG_LIMIT}s — killing, continuing"
    kill -9 "$pid" 2>/dev/null
    pkill -9 -P "$pid" 2>/dev/null
  }) &
  local watchdog=$!
  wait "$pid" 2>/dev/null
  local rc=$?
  kill "$watchdog" 2>/dev/null
  return $rc
}

# CLI formulae — small, fast, mostly invisible
# node + python: developer runtimes GFN's preflight expects. Added 2026-06 —
# a clean machine needs them; brew skips if already present.
# yt-dlp + ffmpeg + tesseract (+tesseract-lang): YouTube frame-analysis pipeline
# (download video/subs, scene-cut frame extraction, OCR of on-screen text).
# tesseract-lang is ~685MB but carries chi_tra (Traditional Chinese) required for
# CJK on-screen text. Added 2026-06.
# pandoc + poppler: document pipeline (markdown<->docx<->pdf conversion, PDF
# text/info extraction) for the book/PDF build workflow. Added 2026-06-30.
# mas dropped 2026-08-10 with utm + codex + visual-studio-code — trimming the
# baseline to what a new Mac actually needs. Nothing is ever uninstalled here.
# whisper-cpp + opencc: local speech-to-text (meeting/webinar recordings ->
# transcript). Added 2026-08-16 — audio never leaves the machine. The whisper-cpp
# formula is 9MB and ships no model; the GGML weights are fetched separately
# below. opencc normalises whisper's zh output to Traditional Chinese, which the
# model drifts out of partway through a long recording.
FORMULAE="gh node python yt-dlp ffmpeg tesseract tesseract-lang pandoc poppler whisper-cpp opencc"
for tool in $FORMULAE; do
  if brew list "$tool" >/dev/null 2>&1; then
    dim "  ✓ $tool (formula) already installed"
  else
    log "  brew install $tool"
    run_with_timeout "$tool" brew install "$tool" || warn "    $tool install failed (continue)"
  fi
done

# GUI apps via cask
# GFN essentials:  docker
# Daily drivers:   google-chrome, obsidian, claude, claude-code
# Specialised:     obs
# Docs/publishing: libreoffice, font-sarasa-gothic (CJK font for book/PDF). Added 2026-06-30.
# utm, codex, visual-studio-code dropped 2026-08-10 — trimmed out of the baseline.
# claude-code added 2026-08-12: the `claude` cask is the DESKTOP app; the CLI is a
# separate cask. Until now no installer ever installed the CLI — a fresh Mac got
# Claude.app but no `claude` command, so Skills' hooks and the memory links had
# nothing to attach to. Ordering is safe either way: Skills/install.sh writes
# ~/.claude/settings.json whether or not the CLI exists yet.
CASKS="docker google-chrome obsidian claude claude-code obs font-sarasa-gothic libreoffice"
for cask in $CASKS; do
  if brew list --cask "$cask" >/dev/null 2>&1; then
    dim "  ✓ $cask (cask) already installed"
  elif [ "$cask" = "docker" ] && [ -d "/Applications/Docker.app" ]; then
    dim "  ✓ docker.app exists (non-brew install — skipping)"
  elif [ "$cask" = "obsidian" ] && [ -d "/Applications/Obsidian.app" ]; then
    dim "  ✓ obsidian.app exists (non-brew install — skipping)"
  elif [ "$cask" = "claude" ] && [ -d "/Applications/Claude.app" ]; then
    dim "  ✓ claude.app exists (non-brew install — skipping)"
  elif [ "$cask" = "claude-code" ] && command -v claude >/dev/null 2>&1; then
    dim "  ✓ claude CLI on PATH (native/npm install — skipping)"
  else
    log "  brew install --cask $cask"
    run_with_timeout "$cask" brew install --cask "$cask" || warn "    $cask install failed (continue)"
  fi
done

# ─── Whisper model weights ────────────────────────────────────────────
# brew ships whisper-cpp with no model, so a fresh Mac has the binary and
# nothing to run. large-v3 is the only model worth carrying here: on Traditional
# Chinese the smaller ones drop proper nouns, which is exactly what these
# recordings are full of. 2.9GB, downloaded once, resumable.
# Size-checked rather than existence-checked — a half-finished download leaves a
# file that looks present and then fails inside whisper-cli with a parse error.
WHISPER_MODEL_DIR="$HOME/.cache/whisper-models"
WHISPER_MODEL="$WHISPER_MODEL_DIR/ggml-large-v3.bin"
WHISPER_MODEL_BYTES=3095033483
WHISPER_MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin"

log "Checking whisper large-v3 model"
mkdir -p "$WHISPER_MODEL_DIR"
if [ "$(stat -f %z "$WHISPER_MODEL" 2>/dev/null || echo 0)" = "$WHISPER_MODEL_BYTES" ]; then
  dim "  ✓ ggml-large-v3.bin already present (2.9GB)"
else
  log "  downloading ggml-large-v3.bin (2.9GB, resumable)"
  curl -fL -C - --retry 3 -o "$WHISPER_MODEL" "$WHISPER_MODEL_URL" \
    || warn "    model download failed (continue — re-run install.sh to resume)"
  if [ "$(stat -f %z "$WHISPER_MODEL" 2>/dev/null || echo 0)" != "$WHISPER_MODEL_BYTES" ]; then
    warn "    model incomplete — transcribe.sh will refuse until install.sh finishes it"
  fi
fi

# Put transcribe.sh on PATH. Symlinked rather than copied so a `git pull` of this
# repo updates the command in place, the same way login-sync picks up changes.
# Resolve this repo's checkout. Under `curl | bash` there is no script path on
# disk, so fall back to the canonical clone location install.sh documents.
SELF="${BASH_SOURCE[0]:-}"
if [ -f "$SELF" ]; then
  TRANSCRIBE_SRC="$(cd "$(dirname "$SELF")" && pwd)/transcribe.sh"
else
  TRANSCRIBE_SRC="$HOME/AvalonLotus Mac-Setup/transcribe.sh"
fi
TRANSCRIBE_DST="$(brew --prefix)/bin/transcribe"
if [ -f "$TRANSCRIBE_SRC" ]; then
  chmod +x "$TRANSCRIBE_SRC"
  if [ "$(readlink "$TRANSCRIBE_DST" 2>/dev/null)" = "$TRANSCRIBE_SRC" ]; then
    dim "  ✓ transcribe already linked"
  else
    ln -sfn "$TRANSCRIBE_SRC" "$TRANSCRIBE_DST" && ok "transcribe -> $TRANSCRIBE_SRC" \
      || warn "    could not link transcribe (continue)"
  fi
fi

ok "baseline tools done"

# Commit-signature trust (model B) removed 2026-08-10 by user decision, together
# with trust/allowed_signers, the phone-approval tooling that rode on it
# (approve.command, add-signer.command, phone-approve-guide.md, APPROVALS.log) and
# the per-machine kill-switch setup (setup-security.command, security-setup-guide.md).
# login-sync now applies the bootstrap on any HEAD move, whoever committed it.

# ─── Login auto-sync agent ────────────────────────────────────────────
# Installs com.avalonlotus.login-sync: at login AND every 15 min it pulls THIS
# repo and, only if it changed, re-runs install.sh so new tools/skills/setups
# land automatically. (Other repos' content is pulled by
# com.avalonlotus.git-autopull; this agent re-applies the bootstrap when the
# bootstrap itself changes.)
# The 15-min StartInterval matters because a machine that is never logged out /
# restarted would otherwise only ever fire RunAtLoad once — new bootstrap
# tools would sit unapplied indefinitely. The timer makes propagation
# independent of login. Cheap when idle: a no-change run is just a pull +
# "nothing to apply" exit (lighter than git-autopull, which already pulls 5
# repos every 15 min); install.sh only re-runs when Mac-Setup HEAD moved.
# Idempotent — re-running install.sh just refreshes the agent.
log "Installing login auto-sync LaunchAgent"
LOGIN_SCRIPT="$HOME/AvalonLotus Mac-Setup/login-sync.sh"
LOGIN_PLIST="$HOME/Library/LaunchAgents/com.avalonlotus.login-sync.plist"
LOGIN_LOG_DIR="$HOME/.local/state/git-autosync"
mkdir -p "$LOGIN_LOG_DIR" "$HOME/Library/LaunchAgents"
chmod +x "$LOGIN_SCRIPT" 2>/dev/null || true
cat > "$LOGIN_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.avalonlotus.login-sync</string>
  <key>ProgramArguments</key><array>
    <string>/bin/sh</string><string>$LOGIN_SCRIPT</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>900</integer>
  <key>StandardOutPath</key><string>$LOGIN_LOG_DIR/login-sync.log</string>
  <key>StandardErrorPath</key><string>$LOGIN_LOG_DIR/login-sync.log</string>
</dict></plist>
PLIST
_uid=$(id -u)
_loaded=$(launchctl print "gui/$_uid/com.avalonlotus.login-sync" >/dev/null 2>&1 && echo yes || echo no)

# Never bootout the job we are RUNNING UNDER. login-sync.sh invokes this script
# from inside the com.avalonlotus.login-sync launchd job, and booting that job
# out kills its whole process tree — install.sh dies before the bootstrap line
# and the agent stays uninstalled, permanently. That is exactly what happened
# 2026-08-11 02:33 the first time login-sync ever managed to apply the bootstrap.
if [ "$_loaded" = yes ] && [ "${AVALONLOTUS_FROM_LOGIN_SYNC:-}" = 1 ]; then
  ok "login-sync agent already loaded (plist refreshed; reload skipped — we are running inside it)"
elif [ "$_loaded" = yes ] && cmp -s "$LOGIN_PLIST" "$LOGIN_PLIST.installed" 2>/dev/null; then
  ok "login-sync agent already loaded and unchanged (no reload needed)"
else
  launchctl bootout "gui/$_uid" "$LOGIN_PLIST" 2>/dev/null || true
  if launchctl bootstrap "gui/$_uid" "$LOGIN_PLIST" 2>/dev/null; then
    ok "login-sync agent loaded (runs at login + every 15 min)"
  else
    warn "login-sync bootstrap failed (will load at next login)"
  fi
fi
cp "$LOGIN_PLIST" "$LOGIN_PLIST.installed" 2>/dev/null || true

# ─── Repo manifest ────────────────────────────────────────────────────
# Add new repos here. Format per row: <repo_url>|<local_path>|<setup_cmd>
# setup_cmd is run from the repo's root directory. Empty = no setup.
REPOS="
https://github.com/AvalonLotus/AvalonLotus.com.git|$HOME/AvalonLotus.com|
https://github.com/AvalonLotus/Global-Finance-News.git|$HOME/AvalonLotus Projects/Global Finance News|bash scripts/install-git-autosync.sh
https://github.com/AvalonLotus/AvalonLotus-Obsidian.git|$HOME/AvalonLotus Obsidian|./setup.sh
https://github.com/AvalonLotus/AvalonLotus-Skills.git|$HOME/AvalonLotus Skills|./install.sh
"

# ─── Process each repo ────────────────────────────────────────────────
SUCCEEDED=""
FAILED=""
SKIPPED=""

echo "$REPOS" | while IFS='|' read -r url path setup; do
  [ -z "$url" ] && continue
  name=$(basename "$path")
  echo
  log "[$name]"

  if [ -d "$path/.git" ]; then
    dim "exists at $path — pulling"
    if ! (cd "$path" && git pull --rebase --autostash --quiet 2>&1 | tail -3); then
      fail "$name: pull failed"
      continue
    fi
    ok "pulled"
  else
    dim "cloning into $path"
    mkdir -p "$(dirname "$path")"
    if ! git clone --quiet "$url" "$path" 2>&1; then
      fail "$name: clone failed"
      continue
    fi
    ok "cloned"
  fi

  if [ -n "$setup" ]; then
    dim "running setup: $setup"
    if (cd "$path" && eval "$setup"); then
      ok "$name setup OK"
    else
      fail "$name setup failed (clone OK, just setup)"
    fi
  else
    dim "(no setup script, repo is just cloned)"
  fi
done

echo
log "All done. See above for any ✗ failures."
echo
echo "What's installed:"
echo "$REPOS" | while IFS='|' read -r url path setup; do
  [ -z "$url" ] && continue
  [ -d "$path/.git" ] && echo "  • $(basename "$path")  → $path"
done

echo
echo "If you re-run this script, it will pull the latest of each repo and"
echo "re-run their setup. All setup scripts are designed to be idempotent."
