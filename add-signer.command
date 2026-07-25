#!/usr/bin/env bash
# AvalonLotus 新增簽章金鑰 — add-signer.command
#
# 用途:把一把新的『簽章金鑰』(例如手機 Working Copy 在 Secure Enclave 產生的)
#       加入信任清單 allowed_signers,然後用『主機的印章』把這個變更簽章推送。
#       完成後,那把新鑰匙(手機)就成為受信任的簽章者 —— 這就是「雙主機」。
#
# 只能在主機執行:最後一步要用現有的受信任鑰匙簽章,沒有鑰匙的機器會被 approve
#                拒絕(這正是安全規則:新鑰匙必須由既有可信鑰匙加持)。
#
# 用法:
#   ./add-signer.command                                   互動貼上公鑰
#   ./add-signer.command "iphone-signing" "ssh-ed25519 AAAA... iphone"
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd "$DIR" || exit 1
AS_REPO="$DIR/trust/allowed_signers"
AS_LIVE="$HOME/.config/git-autosync/allowed_signers"
PRINCIPALS="Lien.Founder@AvalonLotus.com,AvalonLotus.Lien@gmail.com"

LABEL="${1:-}"; PUB="${2:-}"
if [ -z "$PUB" ]; then
  echo "貼上手機(Working Copy)產生的『公鑰』整行,例:"
  echo "  ssh-ed25519 AAAA... iphone"
  printf "公鑰: "; read -r PUB
fi
[ -z "${LABEL}" ] && { printf "幫這把鑰匙取個名字(例 iphone-signing): "; read -r LABEL; }

# 取出 "type base64"(忽略註解)
BLOB="$(printf '%s\n' "$PUB" | awk '{print $1" "$2}')"
case "$BLOB" in
  ssh-ed25519\ *|ssh-rsa\ *|sk-ssh-ed25519@openssh.com\ *|ecdsa-*|sk-ecdsa-*) ;;
  *) echo "看起來不是有效的公鑰,已取消。"; exit 1 ;;
esac

if [ -f "$AS_REPO" ] && grep -qF "$BLOB" "$AS_REPO"; then
  echo "這把鑰匙已經在信任清單裡了,不需重複加入。"; exit 0
fi

printf '%s %s %s\n' "$PRINCIPALS" "$BLOB" "$LABEL" >> "$AS_REPO"
mkdir -p "$(dirname "$AS_LIVE")"; cp "$AS_REPO" "$AS_LIVE"
echo "[完成] 已加入信任清單:$LABEL"
echo "接著用主機的印章簽章並推送(交給 approve.command)…"
echo
exec bash "$DIR/approve.command"
