#!/usr/bin/env bash
# Oz Downloader — automated E2E smoke (maps to E2E_TEST_PLAN.md)
# Usage:
#   ./scripts/e2e_test.sh              # full smoke (includes live Spotify if creds exist)
#   ./scripts/e2e_test.sh --offline    # skip live Spotify download
#   ./scripts/e2e_test.sh --quick      # release + convert only
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${APP:-${ROOT}/build/Oz Downloader.app}"
DMG="${DMG:-${HOME}/Desktop/OzDownloader-Installer.dmg}"
RUNTIME="${APP}/Contents/Resources/runtime"
PY="${RUNTIME}/bin/python3"
POST="${RUNTIME}/bin/zotify-postprocess.py"
FFMPEG="${RUNTIME}/bin/ffmpeg"
ZOTIFY="${RUNTIME}/bin/zotify"
CREDS="${HOME}/Library/Application Support/OzDownloader/zotify/credentials.json"
CONFIG="${HOME}/Library/Application Support/OzDownloader/zotify/config.json"
SETTINGS="${HOME}/Library/Application Support/OzDownloader/settings.json"
MUSIC_ROOT="${HOME}/Music/Oz Downloader"
E2E_ROOT="${TMPDIR:-/tmp}/oz-downloader-e2e-$$"
MODE="${1:-}"

PASS=0
FAIL=0
SKIP=0
RESULTS=()

green() { printf '\033[32m%s\033[0m\n' "$*"; }
red()   { printf '\033[31m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$*"; }

ok()   { PASS=$((PASS+1)); RESULTS+=("PASS  $1"); green "PASS  $1"; }
bad()  { FAIL=$((FAIL+1)); RESULTS+=("FAIL  $1 — $2"); red "FAIL  $1 — $2"; }
skip() { SKIP=$((SKIP+1)); RESULTS+=("SKIP  $1 — $2"); yellow "SKIP  $1 — $2"; }

cleanup() {
  rm -rf "${E2E_ROOT}" 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p "${E2E_ROOT}"

echo "==> Oz Downloader E2E"
echo "    APP=${APP}"
echo "    DMG=${DMG}"
echo "    MODE=${MODE:-full}"
echo

# ---------------------------------------------------------------------------
# R1 / R2 — release / notarization
# ---------------------------------------------------------------------------
if [[ -f "${DMG}" ]]; then
  if spctl -a -vv -t install "${DMG}" 2>&1 | tee "${E2E_ROOT}/spctl.txt" | rg -q 'accepted'; then
    if rg -q 'Notarized Developer ID' "${E2E_ROOT}/spctl.txt"; then
      ok "R1 notarization (spctl accepted + Notarized Developer ID)"
    else
      bad "R1 notarization" "accepted but not Notarized Developer ID"
    fi
  else
    bad "R1 notarization" "$(tr '\n' ' ' < "${E2E_ROOT}/spctl.txt")"
  fi

  if xcrun stapler validate "${DMG}" 2>&1 | tee "${E2E_ROOT}/staple.txt" | rg -qi 'validate action worked|The validate action worked'; then
    ok "R2 staple ticket present"
  else
    bad "R2 staple" "$(tr '\n' ' ' < "${E2E_ROOT}/staple.txt")"
  fi
else
  skip "R1/R2" "DMG not found at ${DMG}"
fi

# ---------------------------------------------------------------------------
# I3 — bundled tools
# ---------------------------------------------------------------------------
if [[ ! -d "${APP}" ]]; then
  bad "I3 app bundle" "missing ${APP}"
else
  missing=()
  for p in "${PY}" "${FFMPEG}" "${POST}" "${ZOTIFY}" "${APP}/Contents/MacOS/OzDownloader"; do
    [[ -e "${p}" ]] || missing+=("${p}")
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    ok "I3 bundled binaries present (python/ffmpeg/postprocess/zotify/app)"
  else
    bad "I3 bundled binaries" "missing: ${missing[*]}"
  fi

  if "${PY}" -c "import zotify, mutagen, requests" 2>"${E2E_ROOT}/import.err"; then
    ok "I3 python imports (zotify, mutagen, requests)"
  else
    bad "I3 python imports" "$(tr '\n' ' ' < "${E2E_ROOT}/import.err")"
  fi

  if "${FFMPEG}" -version >/dev/null 2>&1; then
    ok "I3 ffmpeg runs"
  else
    bad "I3 ffmpeg" "ffmpeg -version failed"
  fi
fi

# ---------------------------------------------------------------------------
# S1 — UI source checks (no Dependencies / no Save as on Get Music)
# ---------------------------------------------------------------------------
if ! rg -q 'Ready to sign in|Text\("Dependencies"\)' "${ROOT}/ZotifyStudio/Views/SettingsView.swift"; then
  ok "S1 Preferences has no Dependencies / Ready to sign in"
else
  bad "S1 Preferences" "Dependencies / Ready to sign in still in SettingsView"
fi

if ! rg -q 'Text\("Save as"\)' "${ROOT}/ZotifyStudio/Views/DownloadView.swift"; then
  ok "S1 Get Music has no Save as section"
else
  bad "S1 Get Music" "Save as UI still in DownloadView"
fi

# ---------------------------------------------------------------------------
# Settings defaults (0.5 / S3 persistence shape)
# ---------------------------------------------------------------------------
if [[ -f "${SETTINGS}" ]]; then
  if SETTINGS_PATH="${SETTINGS}" "${PY}" - <<'PY'
import json, os, sys
s = json.load(open(os.environ["SETTINGS_PATH"]))
checks = [
  ("convertFormat", "flac"),
  ("autoPostprocess", True),
  ("skipExisting", True),
]
fail = []
for k, want in checks:
    got = s.get(k)
    if got != want:
        fail.append(f"{k}={got!r} want {want!r}")
if fail:
    print("; ".join(fail))
    sys.exit(1)
PY
  then
    ok "S3 settings defaults (flac + convert + skipExisting)"
  else
    bad "S3 settings defaults" "unexpected values in settings.json"
  fi
else
  skip "S3 settings" "settings.json missing (app never launched)"
fi

# ---------------------------------------------------------------------------
# D1 layout — no loose audio in music root
# ---------------------------------------------------------------------------
if [[ -d "${MUSIC_ROOT}" ]]; then
  loose="$(MUSIC_ROOT="${MUSIC_ROOT}" "${PY}" - <<'PY'
from pathlib import Path
import os
root = Path(os.environ["MUSIC_ROOT"])
exts = {".ogg", ".mp3", ".m4a", ".flac", ".wav", ".opus", ".aac"}
loose = [p.name for p in root.iterdir() if p.is_file() and p.suffix.lower() in exts]
print("\n".join(loose))
PY
)"
  if [[ -z "${loose}" ]]; then
    ok "D1 no loose audio files in music root (playlist folders only)"
  else
    bad "D1 folder layout" "loose files in root: ${loose}"
  fi
else
  skip "D1 folder layout" "music root missing"
fi

# ---------------------------------------------------------------------------
# C1 / C2 / C3 / C5 — convert pipeline on a fixture playlist folder
# ---------------------------------------------------------------------------
if [[ -x "${PY}" && -f "${POST}" && -x "${FFMPEG}" ]]; then
  FIX="${E2E_ROOT}/E2E Convert Playlist"
  mkdir -p "${FIX}"
  # Short tone as stand-in for a zotify .ogg download
  "${FFMPEG}" -hide_banner -loglevel error -y -f lavfi -i "sine=frequency=440:duration=1" \
    -c:a libvorbis "${FIX}/Artist_Test Song.ogg"
  "${FFMPEG}" -hide_banner -loglevel error -y -f lavfi -i "sine=frequency=523:duration=1" \
    -c:a libvorbis "${FIX}/Other_Second Track.ogg"
  printf 'id1\t2026-01-01 00:00:00\tArtist\tTest Song\t\nid2\t2026-01-01 00:00:00\tOther\tSecond Track\t\n' > "${FIX}/.song_ids"

  if "${PY}" "${POST}" "${FIX}" --format flac --genre "Afrobeats" >"${E2E_ROOT}/convert.out" 2>"${E2E_ROOT}/convert.err"; then
    oggs=$(find "${FIX}" -maxdepth 1 -name '*.ogg' | wc -l | tr -d ' ')
    flacs=$(find "${FIX}" -maxdepth 1 -name '*.flac' | wc -l | tr -d ' ')
    if [[ "${oggs}" == "0" && "${flacs}" -ge 2 ]]; then
      ok "C1/C2 convert produces FLAC and removes OGG (${flacs} flac)"
    else
      bad "C1/C2 convert output" "ogg=${oggs} flac=${flacs}; $(tr '\n' ' ' < "${E2E_ROOT}/convert.out") $(tr '\n' ' ' < "${E2E_ROOT}/convert.err")"
    fi

    if FIX_PATH="${FIX}" "${PY}" - <<'PY'
from pathlib import Path
import os
from mutagen.flac import FLAC
folder = Path(os.environ["FIX_PATH"])
flacs = list(folder.glob("*.flac"))
assert flacs, "no flac"
ok = False
for f in flacs:
    audio = FLAC(str(f))
    genre = " ".join(audio.get("genre") or [])
    if "Afrobeats" in genre:
        ok = True
        break
assert ok, "genre Afrobeats not found in tags"
PY
    then
      ok "C3 genre tag written into FLAC"
    else
      bad "C3 genre tag" "Afrobeats missing from FLAC tags"
    fi
  else
    bad "C1 convert pipeline" "$(tr '\n' ' ' < "${E2E_ROOT}/convert.err")"
  fi
else
  skip "C1–C3 convert" "runtime tools missing"
fi

# ---------------------------------------------------------------------------
# A1 / live download — optional (needs Spotify credentials)
# ---------------------------------------------------------------------------
if [[ "${MODE}" == "--offline" || "${MODE}" == "--quick" ]]; then
  skip "A1/D1/C live Spotify download" "mode ${MODE}"
elif [[ ! -f "${CREDS}" ]]; then
  skip "A1/D1/C live Spotify download" "no credentials.json"
elif [[ ! -x "${ZOTIFY}" ]]; then
  skip "A1/D1/C live Spotify download" "zotify missing"
else
  LIVE="${E2E_ROOT}/live"
  mkdir -p "${LIVE}/E2E Smoke Track"
  # Single well-known public track (short). Uses app private config/creds.
  TRACK_URL="https://open.spotify.com/track/11dFghVXANMlKmJXsNCbNl"
  echo "    live download → ${TRACK_URL}"
  set +e
  "${ZOTIFY}" \
    -c "${CONFIG}" \
    --creds "${CREDS}" \
    -rp "${LIVE}/E2E Smoke Track" \
    --download-format ogg \
    --download-quality very_high \
    "${TRACK_URL}" >"${E2E_ROOT}/zotify.out" 2>&1
  ZEC=$?
  set -e
  audio_n=$(find "${LIVE}/E2E Smoke Track" -type f \( -name '*.ogg' -o -name '*.mp3' -o -name '*.flac' \) | wc -l | tr -d ' ')
  if [[ "${ZEC}" -eq 0 && "${audio_n}" -ge 1 ]]; then
    ok "A1/D1 live zotify download into playlist folder (${audio_n} file)"
    if "${PY}" "${POST}" "${LIVE}/E2E Smoke Track" --format flac >"${E2E_ROOT}/live-convert.out" 2>"${E2E_ROOT}/live-convert.err"; then
      live_flac=$(find "${LIVE}/E2E Smoke Track" -name '*.flac' | wc -l | tr -d ' ')
      live_ogg=$(find "${LIVE}/E2E Smoke Track" -name '*.ogg' | wc -l | tr -d ' ')
      if [[ "${live_flac}" -ge 1 && "${live_ogg}" == "0" ]]; then
        ok "C1/C2 live convert after download (${live_flac} flac)"
      else
        bad "C live convert output" "flac=${live_flac} ogg=${live_ogg}"
      fi
    else
      bad "C live convert" "$(tr '\n' ' ' < "${E2E_ROOT}/live-convert.err")"
    fi
  else
    # LOGIN FAILED is common; report clearly
    if rg -qi 'LOGIN FAILED|Sign in|authorize' "${E2E_ROOT}/zotify.out"; then
      skip "A1/D1 live download" "Spotify session needs refresh (LOGIN FAILED) — sign in via app Preferences"
    else
      bad "A1/D1 live download" "exit=${ZEC} files=${audio_n}; $(tail -c 400 "${E2E_ROOT}/zotify.out" | tr '\n' ' ')"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Manual-only leftovers (UI suite covers G/D/C/X/P/S2/A2; OAuth needs env)
# ---------------------------------------------------------------------------
if [[ "${MODE}" != "--quick" ]]; then
  skip "R3 second Mac" "manual — second Mac"
  skip "I2 Gatekeeper right-click Open dialog" "partial — quarantine launch automated in e2e_ui_test.sh"
fi

echo
echo "==> Summary"
printf '%s\n' "${RESULTS[@]}"
echo
echo "Passed: ${PASS}  Failed: ${FAIL}  Skipped: ${SKIP}"
if [[ "${FAIL}" -gt 0 ]]; then
  exit 1
fi
exit 0
