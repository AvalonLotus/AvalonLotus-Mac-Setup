# AvalonLotus 機器安全設定說明書

> 目的:讓每台機器擁有一把「可單獨作廢」的雲端鑰匙,
> 並把硬碟加密。達成三件事:
> 1. 任何一台被偷,主機可「一鍵斷線」,該台從此收不到、也送不出你的東西。
> 2. 被偷的硬碟內容,小偷讀不到(加密)。
> 3. 「刪除整個 repo」「踢掉別台」這類危險權力,只存在於主機。
>
> 可接受的最壞情況:被偷當日、已經在那台機器上的資料,放棄不要;
> 之後你更新的東西不會再流到它手上。

---

## 名詞約定

- **主機**:你的主要控制機器(MacBook)。全機唯一可以「踢人」「刪 repo」。
- **副機**:其他所有機器(備援 Mac、Windows 等)。可正常 push,但不能踢人、不能刪 repo。
- **連線鑰匙**:本說明書新建的 SSH 鑰匙,負責「連 GitHub 收發」,跟你既有的「簽章鑰匙」是兩把,不要混用。

每台機器先取一個名字,之後當鑰匙標籤與踢人對象,例如:`MacBook-main`、`BackupMac`、`Windows-PC`。

---

## A. 每台機器都要做(主機、副機共通)

### A1. 產生連線專用 SSH 鑰匙

把 `名字-auth` 換成這台的名字,例如 `BackupMac-auth`:

```
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_github_auth -N "" -C "BackupMac-auth"
```

這把刻意不設密碼,讓背景自動同步能無人值守地使用;它的安全交給硬碟加密(A6)在底層保護。

### A2. 指定連 github.com 時使用這把鑰匙

把以下內容寫進 `~/.ssh/config`(若檔案已存在,附加在後面):

```
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_github_auth
  IdentitiesOnly yes
```

### A3. 把公鑰登記到 GitHub,並掛上這台的名字

副機請從**主機**或直接用 GitHub 網頁登記(避免讓副機握有管理金鑰的權限)。

主機自己登記可用指令(需要管理金鑰權限,見 B1):

```
gh ssh-key add ~/.ssh/id_ed25519_github_auth.pub --title "BackupMac"
```

網頁登記方式:先在這台印出公鑰內容,複製整行:

```
cat ~/.ssh/id_ed25519_github_auth.pub
```

再到 GitHub 網頁 → 右上頭像 → Settings → SSH and GPG keys → New SSH key,
Title 填這台的名字、Key 貼上剛剛複製的整行,Add SSH key。

### A4. 把所有 repo 改用 SSH 連線

以下為 macOS 路徑,逐行貼上即可(Windows 見 E 節):

```
git -C "$HOME/AvalonLotus.com" remote set-url origin git@github.com:AvalonLotus/AvalonLotus.com.git
git -C "$HOME/AvalonLotus Obsidian" remote set-url origin git@github.com:AvalonLotus/AvalonLotus-Obsidian.git
git -C "$HOME/AvalonLotus Skills" remote set-url origin git@github.com:AvalonLotus/AvalonLotus-Skills.git
git -C "$HOME/AvalonLotus Mac-Setup" remote set-url origin git@github.com:AvalonLotus/AvalonLotus-Mac-Setup.git
git -C "$HOME/AvalonLotus Projects/Global Finance News" remote set-url origin git@github.com:AvalonLotus/Global-Finance-News.git
```

### A5. 測試連線

```
ssh -T git@github.com
```

看到「Hi AvalonLotus!」即成功。接著進任一 repo 做一次測試抓取確認可正常收發:

```
git -C "$HOME/AvalonLotus Obsidian" pull --rebase
```

### A6. 開硬碟加密(被偷也讀不到)

macOS:系統設定 → 隱私權與安全性 → FileVault → 開啟。
過程中會問解鎖方式,選「**建立救援金鑰**」(不要選用 iCloud 帳號解鎖)。

得到的那串救援金鑰,**存到密碼管理器或抄下來放在安全的地方,絕對不要只留在這台機器裡**。忘記登入密碼時,這是唯一能救回資料的東西。

---

## B. 只在主機做(副機不要做)

### B1. 升級主機 token 權限

讓主機(也只有主機)取得「管理金鑰」與「刪 repo」權限:

```
gh auth refresh -h github.com -s admin:public_key,delete_repo
```

### B2. 安裝「踢人」按鈕

把以下內容存成 `~/.local/bin/kick`:

```
#!/usr/bin/env bash
set -euo pipefail
title="$1"
id=$(gh api /user/keys --jq ".[] | select(.title==\"$title\") | .id")
if [ -n "$id" ]; then
  gh api -X DELETE "/user/keys/$id"
  echo "已踢掉 $title (key $id)"
else
  echo "找不到名為 $title 的金鑰"
fi
```

給它執行權限:

```
chmod +x ~/.local/bin/kick
```

### B3. 把每台副機的公鑰加進來

每台副機在 A3 完成登記後,主機可列出目前所有鑰匙確認名字正確:

```
gh ssh-key list
```

---

## C. 副機注意事項

- **不要**對副機執行 B1(不要給副機 `admin:public_key`、`delete_repo`)。
  這樣就算副機被偷,小偷也無法反過來踢掉你其他機器、或刪你的 repo。
- 副機若未登入 Apple ID,將無法使用 Find My Mac(遠端定位/鎖定/抹除)。
  這是為了減少私人資訊而做的取捨,**不影響資料安全**:資料保密靠 A6 的 FileVault,
  停止同步靠主機的「踢人」按鈕,兩者都不需要 Apple ID。

---

## D. 機器被偷時的處理流程

1. 在**主機**執行(把名字換成被偷那台):

```
kick BackupMac
```

   人不在主機旁時,改用手機:GitHub App 或網頁 → Settings → SSH and GPG keys →
   把被偷那台的鑰匙刪掉,效果相同。

2. 確認該台已斷線:它之後任何 push / pull 都會失敗,收不到你的新東西、也送不出任何東西。

3. 該台硬碟上「被偷當日已存在」的內容,靠 FileVault 加密,小偷讀不到。

---

## E. Windows 差異

- **SSH 鑰匙**:Windows 內建 OpenSSH,A1、A2、A3、A5 指令相同;
  路徑為 `C:\Users\<你的使用者>\.ssh\`,設定檔同為 `~/.ssh/config`。
- **repo 路徑不同**(資料夾命名兩邊不一樣),A4 改用 Windows 實際路徑,
  指向的 GitHub repo 名稱相同。
- **硬碟加密**:用 **BitLocker**(需 Windows 專業版)取代 FileVault;
  家用版可改用「裝置加密」或第三方加密工具。同樣要保存好救援金鑰。
- 「踢人」按鈕(B 節)只放主機(MacBook),Windows 為副機,不安裝。

---

## F. 進階(選配,之後再評估)

- **force-push(改寫歷史)硬擋**:要在 GitHub 伺服器端擋,私人 repo 需升級
  GitHub Pro(約 US$4/月)才能開分支保護。目前先不做;force-push 靠
  「自動同步從不執行它 + 改寫歷史需明確指令 + 其他機器可救回」守住。

---

## 驗證清單(設定完逐項打勾)

- [ ] 每台機器都有自己的 `id_ed25519_github_auth` 鑰匙
- [ ] 每台的公鑰都已登記到 GitHub,且標籤是該台的名字
- [ ] 所有 repo 的 remote 都已改成 `git@github.com:...`
- [ ] `ssh -T git@github.com` 在每台都顯示 Hi AvalonLotus
- [ ] 每台都已開硬碟加密,救援金鑰已另外保存
- [ ] 只有主機有 `kick` 按鈕、只有主機 token 有 `admin:public_key` 與 `delete_repo`
- [ ] 已實測:主機 `kick <某副機>` 後,該副機 push 立即失效(測完記得重新登記該台鑰匙)
