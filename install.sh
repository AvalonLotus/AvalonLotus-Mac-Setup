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
# node + python: developer runtimes GFN's preflight expects. Added 2026-06 for
# parity with install.ps1 — a clean machine needs them; brew skips if present.
# yt-dlp + ffmpeg + tesseract (+tesseract-lang): YouTube frame-analysis pipeline
# (download video/subs, scene-cut frame extraction, OCR of on-screen text).
# tesseract-lang is ~685MB but carries chi_tra (Traditional Chinese) required for
# CJK on-screen text. Added 2026-06.
# pandoc + poppler: document pipeline (markdown<->docx<->pdf conversion, PDF
# text/info extraction) for the book/PDF build workflow. Added 2026-06-30.
FORMULAE="gh mas node python yt-dlp ffmpeg tesseract tesseract-lang pandoc poppler"
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
# Daily drivers:   google-chrome, visual-studio-code, obsidian, claude
# Specialised:     obs
# Docs/publishing: libreoffice, font-sarasa-gothic (CJK font for book/PDF). Added 2026-06-30.
CASKS="docker google-chrome visual-studio-code obsidian claude obs font-sarasa-gothic libreoffice"
for cask in $CASKS; do
  if brew list --cask "$cask" >/dev/null 2>&1; then
    dim "  ✓ $cask (cask) already installed"
  elif [ "$cask" = "docker" ] && [ -d "/Applications/Docker.app" ]; then
    dim "  ✓ docker.app exists (non-brew install — skipping)"
  elif [ "$cask" = "obsidian" ] && [ -d "/Applications/Obsidian.app" ]; then
    dim "  ✓ obsidian.app exists (non-brew install — skipping)"
  elif [ "$cask" = "claude" ] && [ -d "/Applications/Claude.app" ]; then
    dim "  ✓ claude.app exists (non-brew install — skipping)"
  else
    log "  brew install --cask $cask"
    run_with_timeout "$cask" brew install --cask "$cask" || warn "    $cask install failed (continue)"
  fi
done

ok "baseline tools done"

# ─── Commit-signature trust (model B) ─────────────────────────────────
# Installs the trusted-signers list so THIS machine can VERIFY that bootstrap
# commits were signed by the admin key before login-sync runs install.sh.
# Verification only — signing is set up solely on the admin machine. Refreshing
# allowed_signers here is safe: login-sync only re-runs install.sh for commits
# already trusted by the EXISTING local list, so key rotation must itself be a
# signed (trusted) commit.
log "Installing commit-signature trust (allowed_signers)"
mkdir -p "$HOME/.config/git-autosync"
if [ -f "$HOME/AvalonLotus Mac-Setup/trust/allowed_signers" ]; then
  cp "$HOME/AvalonLotus Mac-Setup/trust/allowed_signers" "$HOME/.config/git-autosync/allowed_signers"
  git config --global gpg.format ssh
  git config --global gpg.ssh.allowedSignersFile "$HOME/.config/git-autosync/allowed_signers"
  ok "allowed_signers installed; login-sync will verify bootstrap commits"
else
  warn "trust/allowed_signers missing — login-sync will block bootstrap until it exists"
fi

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
launchctl bootout "gui/$_uid" "$LOGIN_PLIST" 2>/dev/null || true
if launchctl bootstrap "gui/$_uid" "$LOGIN_PLIST" 2>/dev/null; then
  ok "login-sync agent loaded (runs at login + every 1h)"
else
  warn "login-sync bootstrap failed (will load at next login)"
fi

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

# ─── Security setup reminder (per-machine, run manually) ──────────────
# NOT auto-run: it is interactive and role-specific (main vs secondary),
# and must never auto-grant admin scopes to every machine.
if [ ! -f "$HOME/.ssh/id_ed25519_github_auth" ]; then
  echo
  warn "這台尚未做安全設定（每台一次,分主機/副機）"
  echo "    手動執行一次:  bash \"\$HOME/AvalonLotus Mac-Setup/setup-security.command\""
  echo "    說明文件:      \$HOME/AvalonLotus Mac-Setup/security-setup-guide.md"
fi

echo
echo "If you re-run this script, it will pull the latest of each repo and"
echo "re-run their setup. All setup scripts are designed to be idempotent."
