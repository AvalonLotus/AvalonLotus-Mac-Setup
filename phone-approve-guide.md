# 手機核准設定 — 雙主機(iPhone 當第二支印章)

讓 iPhone 成為一台**能自己簽章核准**的機器。設定完成後,即使主機關機,你也能用
手機把 setup 改動核准、套用到所有機器。

原理:手機用 **Working Copy** 在 **Secure Enclave** 產生一把簽章金鑰(私鑰永遠
無法被匯出、每次簽章要 Face ID)。把這把鑰匙加入信任清單 `trust/allowed_signers`
後,手機簽的 commit 就會被所有機器的 `login-sync` 認定為受信任(`%G? = G`)而套用。
對應機制見 [login-sync.sh](login-sync.sh) 的簽章驗證。

---

## 為什麼「第一次」一定要用到主機

新鑰匙要被信任,必須由**現有已受信任的鑰匙**簽章加入清單——否則任何撿到手機的人
都能把自己加進去。所以手機這把鑰匙的「加持」只能由主機做一次。**做完這一次之後,
主機就可以永遠關機**,手機自己簽自己的。

---

## 第 1 段:手機端準備(現在就能做,不需要主機)

1. App Store 安裝 **Working Copy**,並解鎖 **Pro**(內購)。
   - Push 到私有 repo、SSH 簽章都是 Pro 功能,一定要解鎖。
   - Secure Enclave 金鑰需 2024-12-15 之後購買/升級的 Pro。

2. **連上 GitHub**:Working Copy →「+」→ 選 GitHub → 登入授權(OAuth 最省事)。

3. **Clone 這個 repo**:repo 列表 →「+」→ 選 GitHub →
   選 `AvalonLotus/AvalonLotus-Mac-Setup` → Clone。

4. **產生簽章金鑰(放 Secure Enclave)**:
   `Settings → SSH Keys → [+]` → 類型選 **Ed25519 / Secure Enclave** → 命名
   例如 `iphone-signing` → 建立。

5. **把這把金鑰的「公鑰」複製給我 / 記下來**(第 2 段主機要用):
   在該金鑰上選「Export / Copy Public Key」,得到一整行
   `ssh-ed25519 AAAA... iphone-signing`。

6. **設定簽章身分**:`Settings → Identity` → 新增或編輯一個 Identity →
   - 名字/Email 設成:`AvalonLotus` / `Lien.Founder@AvalonLotus.com`
     (跟現有 commit 一致)
   - **Attach Private Key**:選剛剛那把 `iphone-signing`,格式 SSH。
   - 這樣 Working Copy 之後 commit 就會用它簽章。

> ⚠️ 選單名稱會因 Working Copy 版本略有不同,以官方 users guide 為準:
> https://workingcopyapp.com/users-guide

---

## 第 2 段:主機加持一次(下次碰到主機時)

在主機的 `AvalonLotus Mac-Setup` 資料夾:

```bash
cd "$HOME/AvalonLotus Mac-Setup" && ./add-signer.command "iphone-signing" "在這裡貼上手機的公鑰整行"
```

它會:把手機公鑰加入 `trust/allowed_signers` → 呼叫 `approve.command` 用主機的
印章簽章 → 推送。同一步也會**順便把目前累積的待核准改動一次清掉**(解除卡住狀態)。

之後所有機器下次自動同步時,就會信任手機這把鑰匙。**主機任務完成,可以關機。**

---

## 第 3 段:之後日常(手機自己就能核准,主機免開機)

要發佈一個 setup 改動時,在 iPhone 的 Working Copy:

1. 開 repo → 先 **Pull**(拉最新)。
2. **做改動**:直接編輯檔案(例如 `install.sh` 增減軟體);
   或若只是要「核准別台推上來的改動」,就在 `APPROVALS.log` 加一行(日期+說明)。
3. **Commit**(會要求 Face ID 簽章)→ 作者選第 1 段設好的 Identity。
4. **Push**。

完成。所有機器會在下次登入 / 每 15 分鐘自動套用。

---

## 手機遺失怎麼辦(撤銷)

Secure Enclave 私鑰無法被偷走,風險已很低。若仍要撤銷:

1. 用「尋找」App 遠端清除 iPhone。
2. 在主機把 `trust/allowed_signers` 裡該行(`iphone-signing`)刪掉,執行
   `./approve.command` 簽章推送 → 手機那把鑰匙即失效。
3. 若手機也存有 GitHub 連線金鑰,一併用 `kick` 踢掉(見
   [security-setup-guide.md](security-setup-guide.md))。
