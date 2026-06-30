#!/usr/bin/env bash
# AvalonLotus 主副機安全設定 — 一鍵腳本
# 在每台機器各跑一次(主機選 1、副機選 2)。可重複執行,不會弄壞已設定好的東西。
set -uo pipefail

echo "=== AvalonLotus 安全設定 ==="
read -rp "這台是主控機還是副機?  1=主控機  2=副機 : " ROLE
read -rp "幫這台取個名字 (例 MacBook-main / BackupMac / Windows-PC): " MACHINE
[ -z "${MACHINE:-}" ] && { echo "沒輸入名字,中止。"; exit 1; }

KEY="$HOME/.ssh/id_ed25519_github_auth"
mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"

# 1. 連線專用 SSH 金鑰(跟簽章金鑰分開)
if [ -f "$KEY" ]; then
  echo "[跳過] 連線金鑰已存在"
else
  ssh-keygen -t ed25519 -f "$KEY" -N "" -C "$MACHINE-auth"
  echo "[完成] 已產生連線金鑰"
fi

# 2. 指定連 github.com 用這把金鑰
CFG="$HOME/.ssh/config"; touch "$CFG"; chmod 600 "$CFG"
if grep -q "id_ed25519_github_auth" "$CFG" 2>/dev/null; then
  echo "[跳過] ssh config 已設定"
else
  printf '\nHost github.com\n  HostName github.com\n  User git\n  IdentityFile ~/.ssh/id_ed25519_github_auth\n  IdentitiesOnly yes\n' >> "$CFG"
  echo "[完成] 已寫入 ssh config"
fi

# 3. 所有 repo 改用 SSH 連線
REPOS=(
  "$HOME/AvalonLotus.com|AvalonLotus.com"
  "$HOME/AvalonLotus Obsidian|AvalonLotus-Obsidian"
  "$HOME/AvalonLotus Skills|AvalonLotus-Skills"
  "$HOME/AvalonLotus Mac-Setup|AvalonLotus-Mac-Setup"
  "$HOME/AvalonLotus Founder Note|Founder-Note"
  "$HOME/AvalonLotus Projects/Global Finance News|Global-Finance-News"
)
for e in "${REPOS[@]}"; do
  p="${e%%|*}"; n="${e##*|}"
  if [ -d "$p/.git" ]; then
    git -C "$p" remote set-url origin "git@github.com:AvalonLotus/$n.git"
    echo "[完成] $n 已改用 SSH"
  fi
done

# 4. 把金鑰登記到 GitHub
if [ "$ROLE" = "1" ] && command -v gh >/dev/null 2>&1; then
  gh auth refresh -h github.com -s admin:public_key,delete_repo || true
  if gh ssh-key add "$KEY.pub" --title "$MACHINE" 2>/dev/null; then
    echo "[完成] 金鑰已登記為 $MACHINE"
  else
    echo "[注意] 金鑰可能已登記過,略過"
  fi
else
  echo
  echo ">>> 請手動把下面這把公鑰加到 GitHub:"
  echo ">>> Settings → SSH and GPG keys → New SSH key,Title 填: $MACHINE"
  echo "------------------------------------------------------------"
  cat "$KEY.pub"
  echo "------------------------------------------------------------"
fi

# 5. 主控機才裝「踢人」按鈕(被偷時一鍵斷線)
if [ "$ROLE" = "1" ]; then
  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/kick" <<'KICK'
#!/usr/bin/env bash
set -euo pipefail
title="${1:?用法: kick <機器名>}"
id=$(gh api /user/keys --jq ".[] | select(.title==\"$title\") | .id")
if [ -n "$id" ]; then
  gh api -X DELETE "/user/keys/$id" && echo "已踢掉 $title (key $id)"
else
  echo "找不到名為 $title 的金鑰"
fi
KICK
  chmod +x "$HOME/.local/bin/kick"
  echo "[完成] 已安裝踢人按鈕,用法: kick <機器名>"
fi

# 6. 測試連線
echo
echo "=== 測試 GitHub 連線 ==="
ssh -T git@github.com 2>&1 | head -1 || true

# 7. 硬碟加密狀態提醒
echo
echo "=== FileVault 硬碟加密 ==="
fdesetup status 2>/dev/null || echo "(非 macOS;Windows 請改開 BitLocker)"
echo "若顯示 Off:系統設定 → 隱私權與安全性 → FileVault → 開啟,選『建立救援金鑰』,金鑰另外保存。"

echo
echo "=== 設定完成 ==="
