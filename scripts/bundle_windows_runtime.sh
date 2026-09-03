#!/usr/bin/env bash
# Build a self-contained Windows Python + zotify + ffmpeg runtime for Oz Downloader.
# Must be run on Windows (Git Bash / WSL) — pip packages are platform-specific.
set -euo pipefail

if [[ "$(uname -s)" != MINGW* && "$(uname -s)" != MSYS* && "$(uname -s)" != CYGWIN* ]]; then
  echo "ERROR: bundle_windows_runtime.sh must run on Windows (Git Bash or WSL)."
  echo "       Python packages for Windows cannot be installed from macOS/Linux."
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME="${ROOT}/windows/resources/runtime"
CACHE="${ROOT}/windows/resources/cache"
PY_TAG="20251217"
PY_VER="3.12.12"
PY_ARCHIVE="cpython-${PY_VER}+${PY_TAG}-x86_64-pc-windows-msvc-install_only_stripped.tar.gz"
PY_URL="https://github.com/astral-sh/python-build-standalone/releases/download/${PY_TAG}/${PY_ARCHIVE}"
ZOTIFY_TOOLS="${ZOTIFY_TOOLS:-${HOME}/Desktop/zotify-tools}"

echo "==> Bundling Windows runtime"
mkdir -p "${CACHE}" "${RUNTIME}"

ARCHIVE_PATH="${CACHE}/${PY_ARCHIVE}"
if [[ ! -f "${ARCHIVE_PATH}" ]]; then
  echo "==> Downloading Python standalone"
  curl -fL --retry 3 -o "${ARCHIVE_PATH}.partial" "${PY_URL}"
  mv "${ARCHIVE_PATH}.partial" "${ARCHIVE_PATH}"
fi

echo "==> Extracting Python"
rm -rf "${RUNTIME}"
mkdir -p "${RUNTIME}"
tar -xzf "${ARCHIVE_PATH}" -C "${RUNTIME}"
if [[ -d "${RUNTIME}/python" ]]; then
  rsync -a "${RUNTIME}/python/" "${RUNTIME}/"
  rm -rf "${RUNTIME}/python"
fi

PYBIN="${RUNTIME}/python.exe"
if [[ ! -x "${PYBIN}" ]]; then
  echo "ERROR: python.exe missing after extract"
  exit 1
fi

echo "==> Installing Python packages"
export PYTHONNOUSERSITE=1
"${PYBIN}" -m pip install --upgrade pip wheel
"${PYBIN}" -m pip install --no-user mutagen requests imageio-ffmpeg
"${PYBIN}" -m pip install --no-user "git+https://github.com/Googolplexed0/zotify.git"

if [[ -f "${ZOTIFY_TOOLS}/scripts/patch_oauth.py" ]]; then
  echo "==> Applying OAuth patch"
  PYTHONNOUSERSITE=1 "${PYBIN}" "${ZOTIFY_TOOLS}/scripts/patch_oauth.py" || echo "WARNING: OAuth patch failed"
fi

if [[ -f "${ZOTIFY_TOOLS}/scripts/patch_skip_existing.py" ]]; then
  echo "==> Applying skip-existing patch"
  PYTHONNOUSERSITE=1 "${PYBIN}" "${ZOTIFY_TOOLS}/scripts/patch_skip_existing.py" || echo "WARNING: skip-existing patch failed"
fi

echo "==> Linking ffmpeg"
FFMPEG_SRC="$("${PYBIN}" -c "import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())")"
cp "${FFMPEG_SRC}" "${RUNTIME}/ffmpeg.exe"

echo "==> Installing zotify-postprocess"
POST_SRC="${ZOTIFY_TOOLS}/bin/zotify-postprocess"
if [[ ! -f "${POST_SRC}" ]]; then
  echo "ERROR: missing ${POST_SRC}"
  exit 1
fi
cp "${POST_SRC}" "${RUNTIME}/zotify-postprocess.py"

cat > "${RUNTIME}/zotify-postprocess.bat" <<'EOF'
@echo off
"%~dp0python.exe" "%~dp0zotify-postprocess.py" %*
EOF

cat > "${RUNTIME}/zotify.bat" <<'EOF'
@echo off
set "PATH=%~dp0;%~dp0Scripts;%PATH%"
"%~dp0python.exe" -m zotify %*
EOF

"${PYBIN}" -c "import zotify, mutagen, requests, imageio_ffmpeg; print('runtime ok')"
echo "==> Windows runtime ready: ${RUNTIME}"
