#!/bin/sh
# login-sync.sh — run at every login by the com.avalonlotus.login-sync LaunchAgent.
#
# What it does:
#   1. Pulls the latest AvalonLotus Mac-Setup (the bootstrap definition).
#   2. Compares HEAD against the commit recorded in the applied-stamp; if they
#      differ, re-runs install.sh so any new brew tools, skill links, or repo
#      setup steps are applied automatically, then records the new commit.
#   3. If the stamp already matches HEAD, it does nothing expensive.
#
# Installed / refreshed by install.sh. Idempotent and safe to run repeatedly.
# Log: ~/.local/state/git-autosync/login-sync.log
#
# NOTE: git content for the OTHER repos is already kept current by the separate
# com.avalonlotus.git-autopull agent (every 15 min + at login). This script's
# job is only to re-APPLY the bootstrap when the bootstrap itself changes.
#
# Why a stamp and not before/after-pull comparison (fixed 2026-08-10): git-autopull
# scans $HOME and pulls Mac-Setup too, so by login time HEAD had almost always
# already moved and this script saw before == after — "nothing to apply" 1272 times,
# install.sh never once re-applied since 2026-06-03. The stamp records what was
# actually applied on THIS machine, so it no longer matters who did the pull.

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

STAMP="$LOG_DIR/login-sync.applied"

git pull --rebase --autostash >> "$LOG" 2>&1
head=$(git rev-parse HEAD 2>/dev/null)
applied=$(cat "$STAMP" 2>/dev/null)

if [ -n "$head" ] && [ "$head" = "$applied" ]; then
  echo "[$(ts)] login-sync: already applied ($head), nothing to do" >> "$LOG"
  exit 0
fi

# The dual-admin signature gate (model B, 2026-06-03) and the phone-approval
# system built on top of it (2026-07-26) were REMOVED 2026-08-10 by user decision.
# Bootstrap applies as soon as HEAD differs from the stamp, whoever committed it.
echo "[$(ts)] login-sync: applied=${applied:-none} head=$head, running install.sh" >> "$LOG"
# Tells install.sh not to bootout the launchd job we are running inside — doing so
# kills this process tree mid-script and leaves the agent uninstalled.
export AVALONLOTUS_FROM_LOGIN_SYNC=1
if bash "$REPO/install.sh" >> "$LOG" 2>&1; then
  printf '%s\n' "$head" > "$STAMP"
  echo "[$(ts)] login-sync: install.sh finished, stamped $head" >> "$LOG"
else
  echo "[$(ts)] login-sync: install.sh FAILED, stamp not advanced — will retry next login" >> "$LOG"
fi
