#!/usr/bin/env bash
#
# transcribe.sh — local speech-to-text for meeting/webinar recordings.
#
# Usage:
#   transcribe.sh <audio-or-video-file> [output-dir]
#   transcribe.sh recording.m4a
#   transcribe.sh recording.m4a ~/Desktop
#   WHISPER_LANG=en transcribe.sh interview.mp3
#
# Writes <name>.txt (plain transcript) and <name>.srt (timestamped) next to the
# source file, or into output-dir if given.
#
# Everything runs on this machine — the audio is never uploaded.
#
# Installed by install.sh, which also fetches the large-v3 weights. This script
# exists because whisper-cli on its own is not usable on real recordings: it
# accepts only 16kHz mono WAV, so every phone/Zoom/QuickTime file needs an
# ffmpeg pass first, and Chinese output needs a Traditional-Chinese prompt or it
# comes back Simplified.

set -uo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; DIM='\033[2m'; NC='\033[0m'
log()  { printf "${GREEN}▶${NC} %s\n" "$*"; }
ok()   { printf "  ${GREEN}✓${NC} %s\n" "$*"; }
warn() { printf "  ${YELLOW}!${NC} %s\n" "$*"; }
die()  { printf "  ${RED}✗${NC} %s\n" "$*" >&2; exit 1; }
dim()  { printf "${DIM}  %s${NC}\n" "$*"; }

SRC="${1:-}"
[ -n "$SRC" ]  || die "usage: transcribe.sh <audio-or-video-file> [output-dir]"
[ -f "$SRC" ]  || die "no such file: $SRC"

MODEL="$HOME/.cache/whisper-models/ggml-large-v3.bin"
MODEL_BYTES=3095033483
LANG="${WHISPER_LANG:-zh}"

command -v whisper-cli >/dev/null 2>&1 || die "whisper-cli not found — run install.sh"
command -v ffmpeg      >/dev/null 2>&1 || die "ffmpeg not found — run install.sh"
# opencc is not fatal — checked at the end, where the fallback is a warning.
[ "$(stat -f %z "$MODEL" 2>/dev/null || echo 0)" = "$MODEL_BYTES" ] \
  || die "model missing or incomplete at $MODEL — run install.sh to (re)fetch it"

OUTDIR="${2:-$(dirname "$SRC")}"
mkdir -p "$OUTDIR" || die "cannot write to $OUTDIR"
BASE="$(basename "${SRC%.*}")"
OUTPREFIX="$OUTDIR/$BASE"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
WAV="$WORK/audio.wav"

# whisper-cli reads 16kHz mono PCM only; everything else must be converted.
log "Converting to 16kHz mono WAV"
ffmpeg -v error -y -i "$SRC" -ar 16000 -ac 1 -c:a pcm_s16le "$WAV" \
  || die "ffmpeg could not decode $SRC"
DURATION="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$WAV" 2>/dev/null | cut -d. -f1)"
if [ -n "${DURATION:-}" ]; then
  if [ "$DURATION" -ge 60 ]; then dim "$((DURATION / 60)) min of audio"; else dim "${DURATION}s of audio"; fi
fi

# The prompt does two jobs: it pins the output to Traditional Chinese (whisper
# defaults to Simplified for zh) and primes the finance/insurance vocabulary
# these recordings run on, which is where a generic model mangles proper nouns.
# -mc 64 trims the context window: at the full 224 the decoder occasionally
# latches onto a phrase and repeats it for whole minutes.
PROMPT_ZH="以下是繁體中文的錄音內容,主題多為金融、保險、信託與財富規劃。常見詞彙:保費融資、槓桿、躉繳保費、保單現金價值、內部報酬率IRR、質借成數、利差、要保人、受益人、宣告利率、承作、貸款成數、保證利率、家族信託、閉鎖性股份有限公司。"
PROMPT_ARGS=()
[ "$LANG" = "zh" ] && PROMPT_ARGS=(--prompt "$PROMPT_ZH")

log "Transcribing (lang=$LANG, large-v3) — this runs at roughly real-time"
whisper-cli \
  -m "$MODEL" -f "$WAV" -l "$LANG" \
  -t 8 -bs 5 -bo 5 -mc 64 \
  "${PROMPT_ARGS[@]}" \
  -otxt -osrt -of "$OUTPREFIX" -np \
  || die "whisper-cli failed"

[ -s "$OUTPREFIX.txt" ] || die "transcription produced no text"

# The prompt only steers the first decode window, so a long zh recording drifts
# back into Simplified partway through. opencc settles it deterministically:
# s2twp is Simplified -> Traditional with Taiwan phrasing (网络->網路, 软件->軟體),
# and it is a no-op on text that is already Traditional, so re-running is safe.
if [ "$LANG" = "zh" ]; then
  if command -v opencc >/dev/null 2>&1; then
    for f in "$OUTPREFIX.txt" "$OUTPREFIX.srt"; do
      [ -s "$f" ] || continue
      if opencc -c s2twp -i "$f" -o "$f.tw" 2>/dev/null && [ -s "$f.tw" ]; then
        mv "$f.tw" "$f"
      else
        rm -f "$f.tw"
        warn "    opencc failed on $(basename "$f") — left as whisper wrote it"
      fi
    done
    dim "normalised to Traditional Chinese (opencc s2twp)"
  else
    warn "    opencc not found — some passages may be Simplified; run install.sh"
  fi
fi

ok "$OUTPREFIX.txt"
ok "$OUTPREFIX.srt"

# A stuck decoder produces a file that looks fine by size but is one line over
# and over, so flag it rather than let it pass as a clean transcript.
DUPES="$(sort "$OUTPREFIX.txt" | uniq -c | sort -rn | head -1 | awk '{print $1}')"
[ "${DUPES:-0}" -gt 10 ] && warn "a line repeats ${DUPES}x — check for a decoder loop around that passage"

exit 0
