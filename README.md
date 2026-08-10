# AvalonLotus Mac Setup

One-command bootstrap for a new Mac. Clones every AvalonLotus repo and runs each one's setup script.

**macOS only.** The Windows port (`install.ps1` / `login-sync.ps1`) was removed 2026-08-10; a Windows machine keeps auto-pull through Global-Finance-News' `scripts\install-git-autosync.ps1` Startup loop, but has no one-command bootstrap here.

**No approval step.** The signed-commit trust gate, the phone-approval system, and the per-machine kill-switch setup were all removed 2026-08-10. `login-sync` applies the bootstrap on any HEAD move, whoever committed it — a malicious `install.sh` pushed from any machine now runs everywhere.

## Quick start (new Mac)

```bash
# Option A — verify-then-run (recommended)
git clone https://github.com/AvalonLotus/AvalonLotus-Mac-Setup.git "$HOME/AvalonLotus Mac-Setup"
bash "$HOME/AvalonLotus Mac-Setup/install.sh"

# Option B — one-liner (faster, requires trust)
curl -fsSL avalonlotus.com/mac | bash
```

Takes ~5-10 minutes on a fresh Mac (most time is Homebrew install).

## What it installs

| # | Repo | Cloned to | Setup |
|---|---|---|---|
| 1 | [AvalonLotus.com](https://github.com/AvalonLotus/AvalonLotus.com) | `~/AvalonLotus.com` | (just clone, no setup) |
| 2 | [Global-Finance-News](https://github.com/AvalonLotus/Global-Finance-News) | `~/AvalonLotus Projects/Global Finance News` | `scripts/install-git-autosync.sh` — post-commit auto-push + 15-min auto-pull launchd daemon |
| 3 | [AvalonLotus-Obsidian](https://github.com/AvalonLotus/AvalonLotus-Obsidian) | `~/AvalonLotus Obsidian` | `./setup.sh` — fonts + Python markdown packages |
| 4 | [AvalonLotus-Skills](https://github.com/AvalonLotus/AvalonLotus-Skills) | `~/AvalonLotus Skills` | `./install.sh` — symlinks each skill into `~/.claude/skills/` |

Prereqs (auto-installed if missing): Homebrew, git, jq.



## Baseline tools (auto-installed via Homebrew)

Installed before any repos are cloned, idempotent (skipped if already present):

**CLI formulae:** `gh`, `node`, `python`, `yt-dlp`, `ffmpeg`, `tesseract`, `tesseract-lang`, `pandoc`, `poppler`

`yt-dlp` / `ffmpeg` / `tesseract` power the YouTube frame-analysis workflow (download, scene-cut frame extraction, on-screen text OCR); `tesseract-lang` is ~685MB but carries `chi_tra` for Traditional Chinese. `pandoc` / `poppler` drive the book and PDF build pipeline.

**GUI apps (casks):**
- GFN essentials: `docker`
- Daily drivers: `google-chrome`, `obsidian`, `claude`
- Specialised: `obs`
- Docs/publishing: `libreoffice`, `font-sarasa-gothic`

To add/remove items, edit the `FORMULAE` / `CASKS` variables in `install.sh`.

## Adding a new repo

Edit the `REPOS` block at the top of `install.sh`:

```
<repo_url>|<local_path>|<setup_cmd>
```

Commit + push. Next time you (or another machine) runs `install.sh`, the new repo gets included.

## Idempotent

Safe to re-run anytime. Pulls latest of each repo, re-runs setup. Useful as a "sync everything" command.

## Why not Ansible / Nix / chezmoi

Three reasons:
1. **Zero-prereq bootstrapping** — a fresh Mac has bash + git. Anything else needs to be installed first, which defeats the "one command" goal.
2. **Personal scale** — ~5 repos, ~2 machines. The complexity overhead of a real config manager isn't worth it.
3. **Each repo owns its own setup** — `install-git-autosync.sh`, `setup.sh`, etc. live in their respective repos. This file just calls them. Easy to maintain.
