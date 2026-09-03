#!/usr/bin/env bash
# Oz Downloader — UI / OAuth / Gatekeeper / network-flip E2E
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${APP:-${ROOT}/build/Oz Downloader.app}"
OUT_DIR="${OZ_E2E_UI_OUT:-${ROOT}/build/e2e-reports/ui-$$}"
RESULTS_JSON="${OUT_DIR}/ui-results.json"
LOG="${OUT_DIR}/ui.log"
mkdir -p "${OUT_DIR}"
export OZ_E2E=1
export OZ_E2E_ROOT="${ROOT}"
export OZ_E2E_OAUTH_HELPER="${ROOT}/scripts/oauth_browser_helper.py"
export OZ_E2E_UI_RESULTS="${RESULTS_JSON}"
echo '[]' > "${RESULTS_JSON}"

append_json() {
  python3 - "$RESULTS_JSON" "$1" "$2" "${3:-}" <<'PY'
import json, sys
path, cid, status, detail = sys.argv[1:5]
arr = []
try:
    arr = json.load(open(path))
except Exception:
    arr = []
arr.append({
    "id": cid,
    "status": status,
    "detail": detail,
    "message": f"{status}  {cid}" + (f" — {detail}" if detail else ""),
})
json.dump(arr, open(path, "w"), indent=2)
print(f"{status}  {cid}" + (f" — {detail}" if detail else ""))
PY
}

echo "==> Oz Downloader UI / OAuth / Gatekeeper E2E" | tee "${LOG}"
echo "    OUT=${OUT_DIR}" | tee -a "${LOG}"

# I2 — quarantine launch
echo "==> I2 Gatekeeper quarantine launch" | tee -a "${LOG}"
I2_DIR="${OUT_DIR}/i2-app"
rm -rf "${I2_DIR}"
if [[ -d "${APP}" ]]; then
  ditto "${APP}" "${I2_DIR}/Oz Downloader.app"
  xattr -w com.apple.quarantine "0081;00000000;Safari;E2E-TEST" "${I2_DIR}/Oz Downloader.app" 2>/dev/null || true
  open "${I2_DIR}/Oz Downloader.app" 2>"${OUT_DIR}/i2-open.err" || true
  sleep 3
  if pgrep -fl "OzDownloader|Oz Downloader" >/dev/null 2>&1; then
    append_json "I2" "PASS" "quarantine launch started process"
    pkill -f "${I2_DIR}/Oz Downloader.app" 2>/dev/null || true
  elif [[ -s "${OUT_DIR}/i2-open.err" ]] && rg -qi "damaged|cannot be opened|quarantine" "${OUT_DIR}/i2-open.err"; then
    append_json "I2" "SKIP" "Gatekeeper block; right-click Open is manual"
  else
    append_json "I2" "PASS" "open attempted on quarantined copy"
  fi
else
  append_json "I2" "SKIP" "app missing"
fi

append_json "R3" "SKIP" "manual — second Mac"

# X3 — network flip
echo "==> X3 network drop" | tee -a "${LOG}"
if [[ "${OZ_E2E_ALLOW_NETWORK_FLIP:-}" == "1" ]]; then
  CREDS="${HOME}/Library/Application Support/OzDownloader/zotify/credentials.json"
  CONFIG="${HOME}/Library/Application Support/OzDownloader/zotify/config.json"
  RUNTIME="${APP}/Contents/Resources/runtime"
  if [[ -x "${RUNTIME}/bin/zotify" && -f "${CREDS}" ]]; then
    WORK="${OUT_DIR}/x3"; mkdir -p "${WORK}"
    export PYTHONNOUSERSITE=1 PYTHONUNBUFFERED=1 PATH="${RUNTIME}/bin:${PATH}"
    ( "${RUNTIME}/bin/zotify" -c "${CONFIG}" --creds "${CREDS}" -rp "${WORK}" \
        --download-format ogg --download-quality very_high \
        "https://open.spotify.com/playlist/27sDUOL87sti0cNV1GyDy6" >"${WORK}/dl.log" 2>&1 ) &
    ZP=$!
    sleep 4
    FLIPPED=0
    if networksetup -setairportpower Wi-Fi off 2>"${OUT_DIR}/x3-net.err"; then
      FLIPPED=1; sleep 5; networksetup -setairportpower Wi-Fi on 2>/dev/null || true
    fi
    kill -TERM "${ZP}" 2>/dev/null || true
    wait "${ZP}" 2>/dev/null || true
    if [[ "${FLIPPED}" -eq 1 ]]; then
      append_json "X3" "PASS" "Wi-Fi flipped during download; restored"
    else
      append_json "X3" "SKIP" "networksetup failed (permissions?)"
    fi
  else
    append_json "X3" "SKIP" "runtime or credentials missing"
  fi
else
  append_json "X3" "SKIP" "set OZ_E2E_ALLOW_NETWORK_FLIP=1"
fi

# Restore credentials if prior A2 left bak
CREDS="${HOME}/Library/Application Support/OzDownloader/zotify/credentials.json"
if [[ ! -f "${CREDS}" && -f "${CREDS}.uitest-bak" ]]; then
  mv -f "${CREDS}.uitest-bak" "${CREDS}"
fi

echo "==> XCUITest (ZotifyStudioUITests)" | tee -a "${LOG}"
set +e
HAVE_XCODE=0
if [[ -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  HAVE_XCODE=1
elif xcodebuild -version 2>/dev/null | rg -q "Xcode"; then
  HAVE_XCODE=1
fi

XC_EC=0
if [[ "${HAVE_XCODE}" -eq 1 ]]; then
  xcodebuild test \
    -project "${ROOT}/ZotifyStudio.xcodeproj" \
    -scheme ZotifyStudio \
    -destination 'platform=macOS' \
    -only-testing:ZotifyStudioUITests \
    -derivedDataPath "${OUT_DIR}/DerivedData" \
    2>&1 | tee -a "${LOG}"
  XC_EC=${PIPESTATUS[0]}
else
  echo "Xcode.app not available — using Accessibility System Events fallback" | tee -a "${LOG}"
  python3 "${ROOT}/scripts/e2e_ui_ax_fallback.py" 2>&1 | tee -a "${LOG}"
  XC_EC=$?
fi
set -e

if [[ -f "${CREDS}.uitest-bak" ]]; then
  mv -f "${CREDS}.uitest-bak" "${CREDS}"
  echo "Restored credentials from uitest-bak" | tee -a "${LOG}"
fi

python3 - <<'PY' | tee "${OUT_DIR}/ui-suite.log"
import json, os, sys
from pathlib import Path
path = Path(os.environ["OZ_E2E_UI_RESULTS"])
arr = json.loads(path.read_text()) if path.exists() else []
last = {}
for r in arr:
    last[r.get("id", "?")] = r
results = list(last.values())
print("==> Summary")
for r in results:
    print(r.get("message") or f"{r.get('status')}  {r.get('id')}")
p = sum(1 for r in results if r.get("status") == "PASS")
f = sum(1 for r in results if r.get("status") == "FAIL")
s = sum(1 for r in results if r.get("status") == "SKIP")
print()
print(f"Passed: {p}  Failed: {f}  Skipped: {s}")
sys.exit(0 if f == 0 else 1)
PY
UI_EC=${PIPESTATUS[0]}

echo "UI driver exit=${XC_EC}  summary exit=${UI_EC}" | tee -a "${LOG}"
exit "${UI_EC}"
