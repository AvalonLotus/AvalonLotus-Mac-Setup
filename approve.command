#!/usr/bin/env bash
# AvalonLotus 一鍵核准 — approve.command
#
# 用途:把副機(或任何來源)推上來的「未簽章」改動看過一遍、蓋章(產生一個
#       受信任的簽章 commit)、推送。所有機器的 login-sync 只會套用「HEAD 已
#       被信任金鑰簽章」的版本,所以這一步就是讓改動真正生效的「核准」。
#
# 安全:只有持有 allowed_signers 內受信任『簽章金鑰』的機器(=主機,或你之後
#       指定的第二主機)能真的核准;其他機器執行會被拒絕。因此把本檔放進 repo、
#       每台都有一份也安全 —— 沒有鑰匙的機器按了也沒用。
#
# 用法:
#   ./approve.command            互動:同步 → 顯示改了什麼 → 問 y/N → 簽章推送
#   ./approve.command --show     只顯示待核准內容,不做任何改動(給手機先看)
#   ./approve.command --yes      不問直接核准(給手機按下「核准」後執行)
#   ./approve.command --status   一行狀態(有沒有待核准 / HEAD 是否已簽章)
#
# 對應設計:login-sync.sh 只在 `git log -1 --format=%G?` == G 時才跑 install.sh。
set -uo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'
say()  { printf "%b\n" "$*"; }
ok()   { printf "  ${GREEN}v${NC} %s\n" "$*"; }
warn() { printf "  ${YELLOW}!${NC} %s\n" "$*"; }
err()  { printf "  ${RED}x${NC} %s\n" "$*"; }

MODE="interactive"
case "${1:-}" in
  --show)     MODE="show" ;;
  --yes|-y)   MODE="yes" ;;
  --status|-s) MODE="status" ;;
  "")         MODE="interactive" ;;
  *) echo "用法: approve.command [--show|--yes|--status]"; exit 2 ;;
esac

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR" || { err "找不到 repo 目錄"; exit 1; }

# allowed_signers 位置:優先用安裝好的,退回 repo 內的正本
AS="$HOME/.config/git-autosync/allowed_signers"
[ -f "$AS" ] || AS="$DIR/trust/allowed_signers"

# 帶上 ssh 簽章驗證設定的 git(自成一體,不依賴全域設定)
gitv() { git -c gpg.format=ssh -c gpg.ssh.allowedSignersFile="$AS" "$@"; }
head_sig() { gitv log -1 --format='%G?' 2>/dev/null; }

# ── 找出這台可用的『受信任簽章金鑰』與對應身分 ────────────────────────
SIGN_KEY=""; SIGN_EMAIL=""
if [ -f "$AS" ]; then
  # 信任清單裡的 key 指紋:"type base64"
  TRUSTED="$(awk '{for(i=1;i<=NF;i++) if($i ~ /^(ssh-|sk-)/){print $i" "$(i+1); break}}' "$AS")"
  for pub in "$HOME"/.ssh/*.pub; do
    [ -f "$pub" ] || continue
    blob="$(awk '{print $1" "$2}' "$pub")"
    if printf '%s\n' "$TRUSTED" | grep -qxF "$blob"; then
      priv="${pub%.pub}"
      if [ -f "$priv" ]; then SIGN_KEY="$priv"; else SIGN_KEY="$pub"; fi
      SIGN_EMAIL="$(grep -F "$blob" "$AS" | head -1 | awk '{print $1}' | cut -d, -f1)"
      break
    fi
  done
fi
SIGN_EMAIL="${SIGN_EMAIL:-Lien.Founder@AvalonLotus.com}"

# ── 找最近一個『受信任簽章』的 commit 當基準 ──────────────────────────
find_base() {
  local c
  for c in $(git rev-list -n 200 HEAD); do
    [ "$(gitv log -1 --format='%G?' "$c" 2>/dev/null)" = "G" ] && { echo "$c"; return 0; }
  done
  return 1
}

show_pending() {
  local base="$1"
  say "${BOLD}待核准的改動:${NC}"
  if [ -n "$base" ]; then
    git --no-pager log --format='  • %h  %s  (%an)' "$base"..HEAD
    echo; say "${BOLD}內容差異:${NC}"
    git --no-pager diff --stat "$base"..HEAD; echo
    git --no-pager diff "$base"..HEAD
  else
    git --no-pager log --format='  • %h  %s  (%an)' -n 20
  fi
}

# ── --status:一行狀態就走 ────────────────────────────────────────────
if [ "$MODE" = "status" ]; then
  if [ "$(head_sig)" = "G" ]; then say "HEAD 已簽章(G),沒有待核准的東西。"
  else say "HEAD 未受信任($(head_sig)),有待核准的改動。"; fi
  exit 0
fi

# ── 同步遠端(把副機/其他來源推上來的抓下來)────────────────────────
say "> 同步 GitHub 最新狀態…"
if ! git pull --rebase --autostash 2>&1 | sed 's/^/  /'; then
  err "git pull 失敗(可能有衝突),請先處理後再試。"; exit 1
fi

LOCAL_DIRTY=0
{ git diff --quiet && git diff --cached --quiet; } || LOCAL_DIRTY=1
SIG="$(head_sig)"
BASE="$(find_base || true)"

# 沒有任何待核准
if [ "$SIG" = "G" ] && [ "$LOCAL_DIRTY" -eq 0 ]; then
  ok "沒有待核准的東西,一切都已生效。"; exit 0
fi

echo; show_pending "$BASE"
if [ "$LOCAL_DIRTY" -eq 1 ]; then
  echo; warn "偵測到本機尚未提交的改動:"; git --no-pager status -s | sed 's/^/    /'
fi
echo

# ── --show:看完就走 ─────────────────────────────────────────────────
if [ "$MODE" = "show" ]; then
  say "(僅顯示,未做任何變更。要核准請執行:approve.command --yes)"; exit 0
fi

# ── 能不能簽章?────────────────────────────────────────────────────────
if [ -z "$SIGN_KEY" ]; then
  err "這台找不到『受信任的簽章金鑰』,無法核准。"
  err "核准只能在持有簽章鑰匙的機器(主機)執行。"; exit 1
fi

# ── 互動模式要確認 ────────────────────────────────────────────────────
if [ "$MODE" = "interactive" ]; then
  printf "要核准以上改動並套用到所有機器嗎? [y/N] "
  read -r ans
  case "$ans" in y|Y|yes|YES) ;; *) say "已取消,未做任何變更。"; exit 0 ;; esac
fi

sign_commit() { # $1 = message ; $2 = "empty" 表示允許空 commit
  local extra=""; [ "${2:-}" = "empty" ] && extra="--allow-empty"
  git -c gpg.format=ssh -c user.signingkey="$SIGN_KEY" \
      -c user.name="AvalonLotus" -c user.email="$SIGN_EMAIL" \
      -c commit.gpgsign=true \
      commit $extra -S -m "$1" >/dev/null
}

if [ "$LOCAL_DIRTY" -eq 1 ] && [ "$MODE" = "interactive" ]; then
  git add -A
  sign_commit "approve: 主機直接修改並核准"
elif [ "$SIG" != "G" ]; then
  n="$(git rev-list --count ${BASE:+$BASE..}HEAD 2>/dev/null || echo '?')"
  sign_commit "approve: 核准 ${n} 筆待生效改動" empty
else
  warn "有本機未提交的改動,但非互動模式不會自動提交;請在主機用互動模式處理。"; exit 0
fi

# ── 驗證簽章,不通過就還原、不推送 ───────────────────────────────────
if [ "$(head_sig)" != "G" ]; then
  err "簽章驗證未通過(得到 '$(head_sig)')。已還原,未推送。"
  git reset --hard HEAD~1 >/dev/null 2>&1 || true; exit 1
fi
ok "已簽章(G)"

say "> 推送到 GitHub…"
if git push 2>&1 | sed 's/^/  /'; then
  ok "核准完成!所有機器會在下次自動同步(登入 / 每 15 分鐘)時套用。"
else
  err "推送失敗,請檢查網路或 GitHub 連線。"; exit 1
fi
