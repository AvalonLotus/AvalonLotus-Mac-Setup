# AvalonLotus Mac Setup

One-command bootstrap for a new Mac. Clones every AvalonLotus repo and runs each one's setup script.

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
| 4 | [Vansaintstone-Obsidian](https://github.com/AvalonLotus/Vansaintstone-Obsidian) | `~/Vansaintstone Obsidian` | `./setup.sh` — same |
| 5 | [Lossvia-Obsidian](https://github.com/AvalonLotus/Lossvia-Obsidian) | `~/Lossvia Obsidian` | `./setup.sh` — same |
| 6 | [Generative-Skill](https://github.com/AvalonLotus/Generative-Skill) | `~/Generative Skill` | `./install.sh` — symlinks each skill into `~/.claude/skills/`, merges hooks, links memory |

Prereqs (auto-installed if missing): Homebrew, git, jq.



## Baseline tools (auto-installed via Homebrew)

Installed before any repos are cloned, idempotent (skipped if already present):

**CLI formulae:** `gh`, `node`, `python`, `yt-dlp`, `ffmpeg`, `tesseract`, `tesseract-lang`, `pandoc`, `poppler`, `whisper-cpp`, `opencc`

`yt-dlp` / `ffmpeg` / `tesseract` power the YouTube frame-analysis workflow (download, scene-cut frame extraction, on-screen text OCR); `tesseract-lang` is ~685MB but carries `chi_tra` for Traditional Chinese. `pandoc` / `poppler` drive the book and PDF build pipeline. `whisper-cpp` / `opencc` are local speech-to-text — see below.

**GUI apps (casks):**
- GFN essentials: `docker`
- Daily drivers: `google-chrome`, `obsidian`, `claude`, `claude-code`
- Specialised: `obs`
- Docs/publishing: `libreoffice`, `font-sarasa-gothic`

To add/remove items, edit the `FORMULAE` / `CASKS` variables in `install.sh`.

## Transcription (`transcribe`)

Added 2026-08-16. Turns a recording into a transcript entirely on this machine — the audio is never uploaded.

```bash
transcribe ~/Downloads/recording.m4a
```

Writes `recording.txt` (plain) and `recording.srt` (timestamped) next to the source, or into a second argument if you give one. Any format ffmpeg reads works — m4a, mp3, wav, mp4, mov. Defaults to Traditional Chinese; override with `WHISPER_LANG=en transcribe file.mp3`.

Runs at roughly real-time on Apple Silicon, so a one-hour recording takes about an hour.

Two pieces sit behind the command. `install.sh` fetches the `large-v3` weights (2.9GB) to `~/.cache/whisper-models/` — the smaller models drop proper nouns on Traditional Chinese, which is most of what these recordings contain — and symlinks `transcribe.sh` to `$(brew --prefix)/bin/transcribe`. The download is resumable and size-checked, so an interrupted `install.sh` resumes rather than leaving a truncated file that fails later inside whisper.

`transcribe.sh` handles what raw `whisper-cli` won't: it converts to the 16kHz mono WAV whisper requires, primes a finance/insurance vocabulary prompt so the model stops mangling proper nouns, caps the decoder context to stop it latching onto a phrase and repeating it for minutes, and warns if a line still repeats suspiciously often. Edit the `PROMPT_ZH` line to retune the vocabulary.

The prompt only steers the first decode window, so a long `zh` recording drifts back into Simplified partway through no matter how it is worded. `opencc -c s2twp` settles that at the end — Simplified to Traditional with Taiwan phrasing (网络 → 網路, 软件 → 軟體), applied to both outputs, and a no-op on text that is already Traditional.

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
