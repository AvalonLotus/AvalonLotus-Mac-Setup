<#
.SYNOPSIS
  AvalonLotus Windows Setup — bootstrap a new Windows PC in one command.
  (Windows port of install.sh — uses winget instead of Homebrew.)

.DESCRIPTION
  1. Ensures winget + git are available (jq installed via winget)
  2. Installs a baseline set of CLI tools and GUI apps via winget
  3. Clones (or pulls) all AvalonLotus repos to Windows paths
  4. Runs each repo's setup step (where a Windows equivalent exists)
  5. Reports what worked vs failed at the end

  Idempotent — safe to re-run. Re-running pulls the latest of each repo.

.USAGE
  Recommended (verify-then-run):
    git clone https://github.com/AvalonLotus/AvalonLotus-Mac-Setup.git "$HOME\AvalonLotus-Mac-Setup"
    powershell -ExecutionPolicy Bypass -File "$HOME\AvalonLotus-Mac-Setup\install.ps1"

.NOTES
  Mac -> Windows mapping:
    Homebrew (brew)            -> winget (built into Windows 10/11)
    cask (.app to /Applications) -> winget install (GUI apps)
    mas (Mac App Store CLI)    -> no Windows equivalent (skipped)
    launchd daemon (autosync)  -> Task Scheduler (see Global Finance News note)
    UTM (Mac virtualization)   -> no direct port (skipped; use Hyper-V/WSL2)
    $HOME/...                  -> $HOME\... ($HOME = C:\Users\<you> in PowerShell)

  Some winget package IDs may differ on your system. Verify with:
    winget search <name>
#>

$ErrorActionPreference = 'Continue'   # NOT Stop — continue past individual failures

# ─── Console encoding ─────────────────────────────────────────────────
# Windows PowerShell 5.1 defaults the console to the legacy code page (e.g. Big5
# on a zh-TW machine), which mangles winget's UTF-8 output into mojibake. Force
# UTF-8 so winget's localized text — and our 中文 messages — display correctly.
try {
    $OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::InputEncoding  = [System.Text.Encoding]::UTF8
    chcp 65001 > $null
} catch { }

# ─── Pretty logging ───────────────────────────────────────────────────
function Log  ($m) { Write-Host "> $m"      -ForegroundColor Green }
function Ok   ($m) { Write-Host "  v $m"    -ForegroundColor Green }
function Warn ($m) { Write-Host "  ! $m"    -ForegroundColor Yellow }
function Fail ($m) { Write-Host "  x $m"    -ForegroundColor Red }
function Dim  ($m) { Write-Host "  $m"      -ForegroundColor DarkGray }

# ─── Prereqs ──────────────────────────────────────────────────────────
Log "Checking prereqs"

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Fail "winget not found. Install 'App Installer' from the Microsoft Store, then re-run."
    Fail "https://apps.microsoft.com/detail/9nblggh4nns1"
    exit 1
}
Ok ("winget " + (winget --version))

# Helper: install a winget package only if its command/id isn't already present.
# $check is an optional command name to test for (skips install if found).
function Install-WingetPkg {
    param(
        [string]$Id,
        [string]$Label = $Id,
        [string]$Check = $null
    )
    if ($Check -and (Get-Command $Check -ErrorAction SilentlyContinue)) {
        Dim "  v $Label already present ($Check on PATH)"
        return
    }
    # Is it already installed per winget's own ledger?
    $listed = winget list --id $Id --exact 2>$null | Select-String -SimpleMatch $Id
    if ($listed) {
        Dim "  v $Label already installed"
        return
    }
    Log "  winget install $Label"
    # Hang-detection watchdog (ported from install.sh). A winget/msiexec install
    # can stall indefinitely waiting on a hidden UAC/elevation prompt or an MSI
    # lock. Run it as a child process and kill it if it exceeds HangLimit so one
    # stuck package can't block the whole bootstrap.
    $HangLimit = 300  # seconds
    $wgArgs = @('install','--id',$Id,'--exact','--silent',
                '--accept-package-agreements','--accept-source-agreements','--disable-interactivity')
    $p = Start-Process -FilePath 'winget' -ArgumentList $wgArgs -PassThru -NoNewWindow
    if (-not $p.WaitForExit($HangLimit * 1000)) {
        Warn "$Label exceeded ${HangLimit}s (likely waiting on a UAC prompt) — killing, continuing"
        try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch { }
        Get-CimInstance Win32_Process -Filter "ParentProcessId=$($p.Id)" -ErrorAction SilentlyContinue |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        return
    }
    if ($p.ExitCode -eq 0) { Ok "$Label installed" }
    else { Warn "$Label install returned exit $($p.ExitCode) (continuing)" }
}

# git + jq are core prereqs
Install-WingetPkg -Id 'Git.Git'   -Label 'git' -Check 'git'
Install-WingetPkg -Id 'jqlang.jq' -Label 'jq'  -Check 'jq'

# Make freshly-installed tools available in THIS session without a restart
$env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
            [System.Environment]::GetEnvironmentVariable('Path','User')

if (Get-Command git -ErrorAction SilentlyContinue) { Ok ("git " + ((git --version) -split ' ')[2]) }
else { Fail "git still not on PATH — open a new terminal and re-run." }

# ─── Baseline apps & CLI tools (idempotent — winget skips if present) ───
Log "Installing baseline tools (CLI + Windows apps)"

# CLI tools (Mac: gh, mas)
#   gh  -> GitHub.cli
#   mas -> NO Windows equivalent (Mac App Store only) — skipped
Install-WingetPkg -Id 'GitHub.cli' -Label 'gh' -Check 'gh'
# Developer runtimes GFN's preflight expects (node for helper scripts/tests,
# python for reporting). Added 2026-06 after a clean Windows install surfaced
# that the Mac already had these from prior tooling, so they were never listed.
Install-WingetPkg -Id 'OpenJS.NodeJS.LTS' -Label 'node'   -Check 'node'
Install-WingetPkg -Id 'Python.Python.3.12' -Label 'python' -Check 'python'
# Media / OCR pipeline (Mac: yt-dlp ffmpeg tesseract tesseract-lang). Powers the
# YouTube frame-analysis workflow (download + scene-cut frames + OCR).
#   yt-dlp -> yt-dlp.yt-dlp ; ffmpeg -> Gyan.FFmpeg ; tesseract -> UB-Mannheim.TesseractOCR
Install-WingetPkg -Id 'yt-dlp.yt-dlp'            -Label 'yt-dlp'    -Check 'yt-dlp'
Install-WingetPkg -Id 'Gyan.FFmpeg'              -Label 'ffmpeg'    -Check 'ffmpeg'
Install-WingetPkg -Id 'UB-Mannheim.TesseractOCR' -Label 'tesseract' -Check 'tesseract'
# Mac's tesseract-lang bundles every language incl. chi_tra. The Windows
# UB-Mannheim build ships a default set WITHOUT Traditional Chinese — drop
# chi_tra.traineddata (+ chi_tra_vert) into the install's tessdata\ folder
# manually if you need CJK on-screen OCR on Windows.
Warn "tesseract (Windows): Traditional Chinese (chi_tra) data may need manual add to tessdata\ — Mac gets it automatically via tesseract-lang"
Warn "mas (Mac App Store CLI) has no Windows equivalent — skipped"

# GUI apps (Mac casks -> winget IDs)
#   Verify any of these with: winget search <name>
$Apps = @(
    @{ Id = 'Docker.DockerDesktop';        Label = 'docker' }
    @{ Id = 'Google.Chrome';               Label = 'google-chrome' }
    @{ Id = 'Microsoft.VisualStudioCode';  Label = 'visual-studio-code' }
    @{ Id = 'Obsidian.Obsidian';           Label = 'obsidian' }
    @{ Id = 'Anthropic.Claude';            Label = 'claude' }
    @{ Id = 'OBSProject.OBSStudio';        Label = 'obs' }
)
foreach ($app in $Apps) {
    Install-WingetPkg -Id $app.Id -Label $app.Label
}
Warn "utm (Mac virtualization) — no Windows port; use Hyper-V or WSL2 instead (skipped)"
Warn "codex — no confirmed winget package; install manually if needed (skipped)"

Ok "baseline tools done"

# ─── Commit-signature trust (model B) ─────────────────────────────────
# Installs the trusted-signers list so this machine can VERIFY bootstrap commits
# before login-sync runs install.ps1. Verification only (signing is admin-only).
Log "Installing commit-signature trust (allowed_signers)"
$cfgDir = Join-Path $HOME '.config\git-autosync'
New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
$trustSrc = Join-Path $PSScriptRoot 'trust\allowed_signers'
if (Test-Path $trustSrc) {
    Copy-Item $trustSrc (Join-Path $cfgDir 'allowed_signers') -Force
    git config --global gpg.format ssh
    git config --global gpg.ssh.allowedSignersFile ((Join-Path $cfgDir 'allowed_signers') -replace '\\','/')
    Ok "allowed_signers installed; login-sync will verify bootstrap commits"
} else {
    Warn "trust\allowed_signers missing — login-sync will block bootstrap until it exists"
}

# ─── Login auto-sync ──────────────────────────────────────────────────
# macOS uses a login-sync LaunchAgent to pull this repo at logon. On Windows we
# deliberately do NOT register a scheduled task: on some PCs the Task Scheduler
# will not launch script processes (Windows Defender / Controlled Folder Access
# blocks scheduler-spawned powershell — the process never starts, last result
# 0x1 / 0xFFFD0000). Instead, auto-pull of ALL AvalonLotus repos (this one
# included) is handled by the Startup-folder background loop that
# Global-Finance-News' scripts\install-git-autosync.ps1 installs (see below /
# the GFN repo Setup step). So there is nothing to register here.
Log "Login auto-sync is handled by the Startup-folder loop (Global-Finance-News autosync) — no scheduled task"
# Clean up any AvalonLotus-LoginSync task left behind by an older version.
schtasks /Delete /TN 'AvalonLotus-LoginSync' /F 2>$null | Out-Null

# ─── Repo manifest ────────────────────────────────────────────────────
# Format per row: @{ Url=...; Path=...; Setup=... }
# Setup is a scriptblock run from the repo root. $null = no setup.
# $ROOT = container folder for all repos on Windows — the company document folder,
#         so repos sit alongside the existing "AvalonLotus - X - Y" document folders.
# NOTE: Windows uses its own localized folder names ("AvalonLotus - <EN> - <中文>").
#       This is independent of the Mac layout in install.sh — neither affects the other.
$ROOT = 'D:\AvalonLotus International Pty., Ltd'
$Repos = @(
    @{ Url = 'https://github.com/AvalonLotus/AvalonLotus.com.git';      Path = "$ROOT\AvalonLotus - Website - 官方網站";                Setup = $null }
    @{ Url = 'https://github.com/AvalonLotus/Global-Finance-News.git';  Path = "$ROOT\AvalonLotus - Projects - 專案\AvalonLotus - Global Finance News - 全球財經新聞"; Setup = {
            # Mac used a launchd daemon (install-git-autosync.sh). On Windows the
            # equivalent is a Scheduled Task. If the repo ships a .ps1, prefer it.
            if (Test-Path 'scripts\install-git-autosync.ps1') {
                powershell -ExecutionPolicy Bypass -File 'scripts\install-git-autosync.ps1'
            } else {
                Warn "no Windows autosync script found (scripts\install-git-autosync.ps1)."
                Warn "Mac uses launchd; on Windows set up a Scheduled Task to 'git pull' on an interval."
            }
      } }
    @{ Url = 'https://github.com/AvalonLotus/AvalonLotus-Obsidian.git'; Path = "$ROOT\AvalonLotus - Obsidian - 知識庫"; Setup = {
            if (Test-Path 'setup.ps1') { powershell -ExecutionPolicy Bypass -File 'setup.ps1' }
            else { Warn "no setup.ps1 (Mac used setup.sh for fonts + Python markdown pkgs)." }
      } }
    @{ Url = 'https://github.com/AvalonLotus/AvalonLotus-Skills.git';   Path = "$ROOT\AvalonLotus - Skills - 技能庫";  Setup = {
            # Mac runs the repo's install.sh to symlink each skill into
            # ~/.claude/skills. The repo currently ships only a bash installer;
            # if a Windows port (install.ps1) is added, prefer it. Until then,
            # warn so skills aren't silently left unlinked on Windows.
            if (Test-Path 'install.ps1') { powershell -ExecutionPolicy Bypass -File 'install.ps1' }
            else { Warn "no install.ps1 in Skills repo — skills NOT linked into `$HOME\.claude\skills on Windows. Add a Windows installer or create the symlinks/junctions manually (needs Developer Mode or admin)." }
      } }
)

# ─── Process each repo ────────────────────────────────────────────────
foreach ($repo in $Repos) {
    $name = Split-Path $repo.Path -Leaf
    Write-Host ""
    Log "[$name]"

    if (Test-Path (Join-Path $repo.Path '.git')) {
        Dim "exists at $($repo.Path) — pulling"
        Push-Location $repo.Path
        git pull --rebase --autostash --quiet 2>&1 | Select-Object -Last 3 | ForEach-Object { Dim $_ }
        if ($LASTEXITCODE -eq 0) { Ok "pulled" } else { Fail "${name}: pull failed"; Pop-Location; continue }
        Pop-Location
    } else {
        Dim "cloning into $($repo.Path)"
        $parent = Split-Path $repo.Path -Parent
        if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
        git clone --quiet $repo.Url $repo.Path 2>&1 | ForEach-Object { Dim $_ }
        if ($LASTEXITCODE -eq 0) { Ok "cloned" } else { Fail "${name}: clone failed (private repo? sign in to GitHub first)"; continue }
    }

    if ($repo.Setup) {
        Dim "running setup"
        Push-Location $repo.Path
        try { & $repo.Setup; Ok "$name setup OK" }
        catch { Fail "$name setup failed (clone OK, just setup): $_" }
        finally { Pop-Location }
    } else {
        Dim "(no setup step, repo is just cloned)"
    }
}

# ─── Summary ──────────────────────────────────────────────────────────
Write-Host ""
Log "All done. See above for any x failures."
Write-Host ""
Write-Host "What's installed:"
foreach ($repo in $Repos) {
    if (Test-Path (Join-Path $repo.Path '.git')) {
        $name = Split-Path $repo.Path -Leaf
        Write-Host "  - $name  -> $($repo.Path)"
    }
}
Write-Host ""
Write-Host "Re-run anytime to pull latest of each repo and re-run setup."
