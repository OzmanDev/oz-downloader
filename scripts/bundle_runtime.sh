#!/usr/bin/env bash
# Build a self-contained Python + zotify + ffmpeg runtime for Oz Downloader.app
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME="${ROOT}/build/runtime"
CACHE="${ROOT}/build/runtime-cache"
ARCH="$(uname -m)"
PY_TAG="20251217"
PY_VER="3.12.12"

case "${ARCH}" in
  arm64)  PY_TRIPLE="aarch64-apple-darwin" ;;
  x86_64) PY_TRIPLE="x86_64-apple-darwin" ;;
  *) echo "Unsupported arch: ${ARCH}"; exit 1 ;;
esac

PY_ARCHIVE="cpython-${PY_VER}+${PY_TAG}-${PY_TRIPLE}-install_only_stripped.tar.gz"
PY_URL="https://github.com/astral-sh/python-build-standalone/releases/download/${PY_TAG}/${PY_ARCHIVE}"

ZOTIFY_TOOLS="${ZOTIFY_TOOLS:-${HOME}/Desktop/zotify-tools}"
MARKER="${RUNTIME}/.oz-runtime-ready"
WANT_MARKER="py=${PY_VER}+${PY_TAG};zotify=git;ffmpeg=imageio;arch=${ARCH}"

echo "==> Bundling runtime (${ARCH})"
mkdir -p "${CACHE}" "${RUNTIME}"

if [[ -f "${MARKER}" ]] && [[ "$(cat "${MARKER}")" == "${WANT_MARKER}" ]] \
   && [[ -x "${RUNTIME}/bin/python3" ]] \
   && "${RUNTIME}/bin/python3" -c "import zotify, mutagen, requests, imageio_ffmpeg" 2>/dev/null \
   && [[ -x "${RUNTIME}/bin/ffmpeg" ]] \
   && [[ -x "${RUNTIME}/bin/zotify-postprocess" ]]; then
  echo "    reusable runtime at ${RUNTIME}"
  exit 0
fi

rm -rf "${RUNTIME}"
mkdir -p "${RUNTIME}" "${CACHE}"

ARCHIVE_PATH="${CACHE}/${PY_ARCHIVE}"
if [[ ! -f "${ARCHIVE_PATH}" ]]; then
  echo "==> Downloading Python standalone"
  curl -fL --retry 3 -o "${ARCHIVE_PATH}.partial" "${PY_URL}"
  mv "${ARCHIVE_PATH}.partial" "${ARCHIVE_PATH}"
fi

echo "==> Extracting Python"
TMP_EXTRACT="${CACHE}/py-extract-$$"
rm -rf "${TMP_EXTRACT}"
mkdir -p "${TMP_EXTRACT}"
tar -xzf "${ARCHIVE_PATH}" -C "${TMP_EXTRACT}"
# Archive contains a top-level "python/" directory
if [[ -d "${TMP_EXTRACT}/python" ]]; then
  rsync -a "${TMP_EXTRACT}/python/" "${RUNTIME}/"
else
  # Fallback: copy whatever was extracted
  rsync -a "${TMP_EXTRACT}/" "${RUNTIME}/"
fi
rm -rf "${TMP_EXTRACT}"

PYBIN="${RUNTIME}/bin/python3"
if [[ ! -x "${PYBIN}" ]]; then
  echo "ERROR: python3 missing after extract"
  ls -la "${RUNTIME}" || true
  exit 1
fi

echo "==> Installing Python packages (zotify + deps + ffmpeg)"
export PYTHONNOUSERSITE=1
"${PYBIN}" -m pip install --upgrade pip wheel
"${PYBIN}" -m pip install --no-user mutagen requests imageio-ffmpeg
"${PYBIN}" -m pip install --no-user "git+https://github.com/Googolplexed0/zotify.git"

if [[ -f "${ZOTIFY_TOOLS}/scripts/patch_oauth.py" ]]; then
  echo "==> Applying librespot OAuth patch (bundled env only)"
  PYTHONNOUSERSITE=1 "${PYBIN}" "${ZOTIFY_TOOLS}/scripts/patch_oauth.py" || echo "WARNING: OAuth patch failed"
else
  echo "WARNING: ${ZOTIFY_TOOLS}/scripts/patch_oauth.py not found — skipping patch"
fi

if [[ -f "${ZOTIFY_TOOLS}/scripts/patch_skip_existing.py" ]]; then
  echo "==> Applying zotify skip-existing patch (extension-agnostic duplicate check)"
  PYTHONNOUSERSITE=1 "${PYBIN}" "${ZOTIFY_TOOLS}/scripts/patch_skip_existing.py" || echo "WARNING: skip-existing patch failed"
else
  echo "WARNING: ${ZOTIFY_TOOLS}/scripts/patch_skip_existing.py not found — skipping patch"
fi

echo "==> Linking ffmpeg from imageio-ffmpeg"
FFMPEG_SRC="$("${PYBIN}" -c "import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())")"
mkdir -p "${RUNTIME}/bin"
cp "${FFMPEG_SRC}" "${RUNTIME}/bin/ffmpeg"
chmod +x "${RUNTIME}/bin/ffmpeg"

echo "==> Installing zotify-postprocess"
if [[ ! -f "${ZOTIFY_TOOLS}/bin/zotify-postprocess" ]]; then
  echo "ERROR: missing ${ZOTIFY_TOOLS}/bin/zotify-postprocess"
  exit 1
fi
cp "${ZOTIFY_TOOLS}/bin/zotify-postprocess" "${RUNTIME}/bin/zotify-postprocess.py"
cat > "${RUNTIME}/bin/zotify-postprocess" <<'EOF'
#!/bin/bash
HERE="$(cd "$(dirname "$0")" && pwd)"
exec "$HERE/python3" "$HERE/zotify-postprocess.py" "$@"
EOF
chmod +x "${RUNTIME}/bin/zotify-postprocess" "${RUNTIME}/bin/zotify-postprocess.py"

# Thin zotify CLI wrapper for Process launches that expect a `zotify` binary
cat > "${RUNTIME}/bin/zotify" <<'EOF'
#!/bin/bash
HERE="$(cd "$(dirname "$0")" && pwd)"
export PATH="$HERE:$PATH"
exec "$HERE/python3" -m zotify "$@"
EOF
chmod +x "${RUNTIME}/bin/zotify"

# Sanity check
"${PYBIN}" -c "import zotify, mutagen, requests, imageio_ffmpeg; print('runtime ok')"
"${RUNTIME}/bin/ffmpeg" -version | head -1

printf '%s\n' "${WANT_MARKER}" > "${MARKER}"
echo "==> Runtime ready: ${RUNTIME}"
du -sh "${RUNTIME}"
