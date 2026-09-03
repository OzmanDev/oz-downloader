#!/usr/bin/env bash
# Run all automated E2E suites and write an HTML report (cases + steps).
#
# Usage:
#   ./scripts/e2e_run_all.sh
#   ./scripts/e2e_run_all.sh --offline-smoke
#   ./scripts/e2e_run_all.sh --skip-ui
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${APP:-${ROOT}/build/Oz Downloader.app}"
REPORT_DIR="${REPORT_DIR:-${ROOT}/build/e2e-reports}"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="${REPORT_DIR}/${STAMP}"
SMOKE_MODE=""
SKIP_UI=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --offline-smoke) SMOKE_MODE="--offline"; shift ;;
    --skip-ui) SKIP_UI=1; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

mkdir -p "${OUT_DIR}"
HOST="$(scutil --get ComputerName 2>/dev/null || hostname)"
echo "==> Oz Downloader full E2E + HTML report"
echo "    OUT=${OUT_DIR}"
echo "    APP=${APP}"
echo

set +e
echo "==> Suite 1: smoke (e2e_test.sh ${SMOKE_MODE:-full})"
"${ROOT}/scripts/e2e_test.sh" ${SMOKE_MODE} 2>&1 | tee "${OUT_DIR}/smoke.log"
SMOKE_EC=${PIPESTATUS[0]}
echo "smoke exit=${SMOKE_EC}" | tee -a "${OUT_DIR}/smoke.log"
echo

echo "==> Suite 2: downloads (e2e_downloads_test.sh)"
"${ROOT}/scripts/e2e_downloads_test.sh" 2>&1 | tee "${OUT_DIR}/downloads.log"
DL_EC=${PIPESTATUS[0]}
echo "downloads exit=${DL_EC}" | tee -a "${OUT_DIR}/downloads.log"
echo

UI_EC=0
if [[ "${SKIP_UI}" -eq 0 ]]; then
  echo "==> Suite 3: UI / OAuth / Gatekeeper (e2e_ui_test.sh)"
  export OZ_E2E_UI_OUT="${OUT_DIR}/ui"
  "${ROOT}/scripts/e2e_ui_test.sh" 2>&1 | tee "${OUT_DIR}/ui.log"
  UI_EC=${PIPESTATUS[0]}
  echo "ui exit=${UI_EC}" | tee -a "${OUT_DIR}/ui.log"
  # Prefer structured suite log for the report
  if [[ -f "${OUT_DIR}/ui/ui-suite.log" ]]; then
    cp "${OUT_DIR}/ui/ui-suite.log" "${OUT_DIR}/ui-suite.log"
  else
    cp "${OUT_DIR}/ui.log" "${OUT_DIR}/ui-suite.log"
  fi
else
  echo "==> Suite 3: UI skipped (--skip-ui)"
  echo "==> Summary" > "${OUT_DIR}/ui-suite.log"
  echo "SKIP  UI suite — --skip-ui" >> "${OUT_DIR}/ui-suite.log"
  echo "Passed: 0  Failed: 0  Skipped: 1" >> "${OUT_DIR}/ui-suite.log"
fi
set -e

echo
echo "==> Building HTML report"
python3 "${ROOT}/scripts/e2e_html_report.py" \
  --catalog "${ROOT}/scripts/e2e_case_catalog.json" \
  --smoke-log "${OUT_DIR}/smoke.log" \
  --downloads-log "${OUT_DIR}/downloads.log" \
  --ui-log "${OUT_DIR}/ui-suite.log" \
  --app "${APP}" \
  --host "${HOST}" \
  --out "${OUT_DIR}/index.html"

rm -f "${REPORT_DIR}/latest.html"
cp "${OUT_DIR}/index.html" "${REPORT_DIR}/latest.html"
ln -sfn "${STAMP}" "${REPORT_DIR}/latest" 2>/dev/null || true
DESKTOP_REPORT="${HOME}/Desktop/OzDownloader-E2E-Report.html"
cp "${OUT_DIR}/index.html" "${DESKTOP_REPORT}"

echo
echo "Report: ${OUT_DIR}/index.html"
echo "Latest: ${REPORT_DIR}/latest.html"
echo "Desktop: ${DESKTOP_REPORT}"

if [[ "${SMOKE_EC}" -ne 0 || "${DL_EC}" -ne 0 || "${UI_EC}" -ne 0 ]]; then
  exit 1
fi
exit 0
