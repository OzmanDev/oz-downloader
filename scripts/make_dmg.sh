#!/usr/bin/env bash
# Build Oz Downloader.app and wrap it in a DMG installer.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${ROOT}/build"
APP_NAME="Oz Downloader"
EXEC_NAME="OzDownloader"
APP="${BUILD}/${APP_NAME}.app"
DMG_NAME="OzDownloader-Installer"
DMG_PATH="${HOME}/Desktop/${DMG_NAME}.dmg"
STAGE="${BUILD}/dmg-stage"
SDK="$(xcrun --show-sdk-path)"
ARCHS="${ARCHS:-$(uname -m)}"
ICON_ICNS="${ROOT}/ZotifyStudio/Resources/AppIcon.icns"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
APPLE_ID="${APPLE_ID:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
APPLE_APP_SPECIFIC_PASSWORD="${APPLE_APP_SPECIFIC_PASSWORD:-}"
BUILD_STAMP="${BUILD_STAMP:-$(date +%Y.%m.%d.%H%M)}"

echo "==> Compiling (${ARCHS})"
mkdir -p "${BUILD}"
SOURCES=(
  "${ROOT}/ZotifyStudio/ZotifyStudioApp.swift"
  "${ROOT}/ZotifyStudio/ContentView.swift"
  "${ROOT}/ZotifyStudio/Models/AppPaths.swift"
  "${ROOT}/ZotifyStudio/Models/Models.swift"
  "${ROOT}/ZotifyStudio/Models/FriendlyLabels.swift"
  "${ROOT}/ZotifyStudio/Services/AppStore.swift"
  "${ROOT}/ZotifyStudio/Services/ZotifyCLI.swift"
  "${ROOT}/ZotifyStudio/Services/DownloadService.swift"
  "${ROOT}/ZotifyStudio/Services/LinkPreviewService.swift"
  "${ROOT}/ZotifyStudio/Views/DownloadView.swift"
  "${ROOT}/ZotifyStudio/Views/PlaylistsView.swift"
  "${ROOT}/ZotifyStudio/Views/SettingsView.swift"
  "${ROOT}/ZotifyStudio/Views/AboutView.swift"
  "${ROOT}/ZotifyStudio/Views/ContactFooter.swift"
  "${ROOT}/ZotifyStudio/Views/LinkPreviewCard.swift"
  "${ROOT}/ZotifyStudio/Views/PlaylistArtworkView.swift"
)

BINS=()
for arch in ${ARCHS}; do
  BIN="${BUILD}/${EXEC_NAME}-${arch}"
  echo "    swiftc → ${arch}"
  swiftc -sdk "${SDK}" \
    -target "${arch}-apple-macosx13.0" \
    -parse-as-library \
    -framework SwiftUI -framework AppKit -framework Foundation -framework Combine -framework CryptoKit \
    "${SOURCES[@]}" \
    -o "${BIN}"
  BINS+=("${BIN}")
done

FINAL_BIN="${BUILD}/${EXEC_NAME}"
if [[ ${#BINS[@]} -eq 1 ]]; then
  cp "${BINS[0]}" "${FINAL_BIN}"
else
  lipo -create -output "${FINAL_BIN}" "${BINS[@]}"
fi
chmod +x "${FINAL_BIN}"

echo "==> Assembling ${APP_NAME}.app"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${FINAL_BIN}" "${APP}/Contents/MacOS/${EXEC_NAME}"
cp "${ROOT}/ZotifyStudio/Info.plist" "${APP}/Contents/Info.plist"

if [[ -f "${ICON_ICNS}" ]]; then
  cp "${ICON_ICNS}" "${APP}/Contents/Resources/AppIcon.icns"
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable ${EXEC_NAME}" "${APP}/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleName ${APP_NAME}" "${APP}/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName ${APP_NAME}" "${APP}/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string ${APP_NAME}" "${APP}/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.oz.downloader" "${APP}/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "${APP}/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "${APP}/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_STAMP}" "${APP}/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string ${BUILD_STAMP}" "${APP}/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${BUILD_STAMP}" "${APP}/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string ${BUILD_STAMP}" "${APP}/Contents/Info.plist" 2>/dev/null || true

cat > "${APP}/Contents/Resources/README.txt" <<'EOF'
Oz Downloader

This app starts empty (no playlists or Spotify session).

Requires zotify + ffmpeg on this Mac (install via Homebrew / zotify-tools).

First launch may need: right-click → Open (Gatekeeper).
EOF

if command -v codesign >/dev/null 2>&1; then
  if [[ -n "${SIGN_IDENTITY}" ]]; then
    echo "==> Developer ID codesign (${SIGN_IDENTITY})"
    codesign --force --deep --options runtime --timestamp --sign "${SIGN_IDENTITY}" "${APP}"
  else
    echo "==> Ad-hoc codesign (local testing only)"
    codesign --force --deep --sign - "${APP}" 2>/dev/null || true
  fi
fi

echo "==> Staging DMG contents"
rm -rf "${STAGE}"
mkdir -p "${STAGE}/.background"
cp -R "${APP}" "${STAGE}/"
ln -s /Applications "${STAGE}/Applications"

# Classic drag-install artwork
python3 "${ROOT}/scripts/make_dmg_background.py"
cp "${BUILD}/dmg-resources/background.png" "${STAGE}/.background/background.png"

echo "==> Creating DMG → ${DMG_PATH}"
rm -f "${DMG_PATH}"
rm -f "${HOME}/Desktop/ZotifyStudio-Installer.dmg"
TMP_DMG="${BUILD}/${DMG_NAME}-rw.dmg"
rm -f "${TMP_DMG}"

# Read-write DMG so we can set Finder layout, then compress.
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${STAGE}" \
  -ov \
  -fs HFS+ \
  -format UDRW \
  "${TMP_DMG}"

MOUNT_DIR="$(hdiutil attach -readwrite -noverify -noautoopen "${TMP_DMG}" | awk 'END{print $NF}')"
VOLUME="/Volumes/${APP_NAME}"
# Prefer the mounted volume name path
if [[ -d "${VOLUME}" ]]; then
  MOUNT_DIR="${VOLUME}"
fi

sleep 1

# Apply window size, background, and icon positions (app → Applications).
osascript <<EOF || true
tell application "Finder"
  tell disk "${APP_NAME}"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 160, 840, 560}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set background picture of viewOptions to file ".background:background.png"
    set position of item "${APP_NAME}.app" of container window to {160, 180}
    set position of item "Applications" of container window to {480, 180}
    update without registering applications
    delay 1
    close
    open
    delay 1
  end tell
end tell
EOF

sync
hdiutil detach "${MOUNT_DIR}" -quiet || hdiutil detach "${VOLUME}" -quiet || true

hdiutil convert "${TMP_DMG}" -format UDZO -imagekey zlib-level=9 -o "${DMG_PATH}"
rm -f "${TMP_DMG}"

if [[ -n "${SIGN_IDENTITY}" ]]; then
  echo "==> Codesign DMG (${SIGN_IDENTITY})"
  codesign --force --timestamp --sign "${SIGN_IDENTITY}" "${DMG_PATH}"
fi

if [[ -n "${APPLE_ID}" && -n "${APPLE_TEAM_ID}" && -n "${APPLE_APP_SPECIFIC_PASSWORD}" ]]; then
  echo "==> Notarizing DMG with Apple"
  xcrun notarytool submit "${DMG_PATH}" \
    --apple-id "${APPLE_ID}" \
    --team-id "${APPLE_TEAM_ID}" \
    --password "${APPLE_APP_SPECIFIC_PASSWORD}" \
    --wait
  echo "==> Stapling notarization ticket"
  xcrun stapler staple "${APP}"
  xcrun stapler staple "${DMG_PATH}"
elif [[ -n "${SIGN_IDENTITY}" ]]; then
  echo "==> Notarization skipped (set APPLE_ID, APPLE_TEAM_ID, APPLE_APP_SPECIFIC_PASSWORD to enable)"
fi

echo
echo "==> Ready"
echo "    App: ${APP}"
ls -lh "${APP}/Contents/MacOS/${EXEC_NAME}"
ls -lh "${APP}/Contents/Resources/AppIcon.icns" 2>/dev/null || true
echo "    DMG: ${DMG_PATH}"
ls -lh "${DMG_PATH}"
