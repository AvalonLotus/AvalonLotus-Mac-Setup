#!/bin/sh
# login-sync.sh — run at every login by the com.avalonlotus.login-sync LaunchAgent.
#
# What it does:
#   1. Pulls the latest AvalonLotus Mac-Setup (the bootstrap definition).
#   2. ONLY if this repo actually changed, re-runs install.sh so any new brew
#      tools, skill links, or repo setup steps are applied automatically.
#   3. If nothing changed, it does nothing expensive — just a quick pull.
#
# Installed / refreshed by install.sh. Idempotent and safe to run repeatedly.
# Log: ~/.local/state/git-autosync/login-sync.log
#
# NOTE: git content for the OTHER repos is already kept current by the separate
# com.avalonlotus.git-autopull agent (every 15 min + at login). This script's
# job is only to re-APPLY the bootstrap when the bootstrap itself changes.

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
REPO="$HOME/AvalonLotus Mac-Setup"
LOG_DIR="$HOME/.local/state/git-autosync"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/login-sync.log"
ts() { date '+%F %T'; }

[ -d "$REPO/.git" ] || { echo "[$(ts)] login-sync: no Mac-Setup repo, skip" >> "$LOG"; exit 0; }
cd "$REPO" || exit 0

# Never act on a dirty tree (mid-edit) — let it settle until next login/run.
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  echo "[$(ts)] login-sync: repo dirty, skip" >> "$LOG"; exit 0
fi

before=$(git rev-parse HEAD 2>/dev/null)
git pull --rebase --autostash >> "$LOG" 2>&1
after=$(git rev-parse HEAD 2>/dev/null)

if [ "$before" = "$after" ]; then
  echo "[$(ts)] login-sync: up to date ($after), nothing to apply" >> "$LOG"
  exit 0
fi

# The dual-admin signature gate (model B, 2026-06-03) and the phone-approval
# system built on top of it (2026-07-26) were REMOVED 2026-08-10 by user decision.
# Bootstrap applies as soon as HEAD moves — the original pre-2026-06-03 behavior.
echo "[$(ts)] login-sync: updated $before -> $after, running install.sh" >> "$LOG"
bash "$REPO/install.sh" >> "$LOG" 2>&1
echo "[$(ts)] login-sync: install.sh finished" >> "$LOG"
