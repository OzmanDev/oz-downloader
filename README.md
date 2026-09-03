# Oz Downloader

Native macOS app for downloading Spotify playlists, albums, and tracks. Converts to FLAC (or other formats), tags files, and organizes them into playlist folders.

**Version:** 0.2.0 · **Bundle ID:** `com.oz.downloader` · **Minimum macOS:** 13.0

---

## Requirements

### End users (install from DMG)

| Requirement | Details |
|-------------|---------|
| **macOS** | 13.0 Ventura or later |
| **Architecture** | Apple Silicon (arm64) build is primary; Intel needs a separate build |
| **Spotify account** | Free or Premium — sign in inside the app (Preferences) |
| **Network** | Internet access for Spotify login + downloads |
| **Disk space** | Enough free space under `~/Music/Oz Downloader` (FLAC is large) |
| **Permissions** | Allow the app when Gatekeeper prompts; Music/Downloads folder access as needed |

No Terminal setup, Homebrew, Python, or ffmpeg install is required — those ship inside the app.

**Install:** open `OzDownloader-Installer.dmg` → drag **Oz Downloader** to Applications → open from Applications.

If macOS blocks the app on first launch: right-click the app → **Open** → **Open**.

### What the app needs at runtime

- **Spotify OAuth** — browser sign-in (localhost callback on port 4381)
- **Default download folder** — `~/Music/Oz Downloader` (changeable in Preferences)
- **App support data** — `~/Library/Application Support/OzDownloader/` (credentials, settings, config)

### Defaults (Preferences)

| Setting | Default |
|---------|---------|
| Download folder | `~/Music/Oz Downloader` |
| Preferred quality | Highest |
| Save as | Best quality (FLAC) |
| Convert after download | On |
| Skip songs already on disk | On |

Playlists are saved as a **folder per playlist** under the download root. Source downloads are OGG, then converted/tagged when convert is enabled.

### Build / developer requirements

| Requirement | Details |
|-------------|---------|
| **Xcode / Swift** | Command Line Tools or Xcode with `swiftc` |
| **macOS SDK** | macOS 13.0+ deployment target |
| **Optional: signing** | Developer ID Application certificate |
| **Optional: notarization** | Apple ID + Team ID + app-specific password |
| **Optional: zotify-tools** | `~/Desktop/zotify-tools` for OAuth patch + postprocess script when rebuilding the runtime |

---

## Build DMG (macOS)

```bash
cd ~/Desktop/ZotifyStudio
./scripts/make_dmg.sh
```

Creates:

- `build/Oz Downloader.app`
- `~/Desktop/OzDownloader-Installer.dmg`

---

## Build Installer (Windows)

**Important:** The Windows installer must be built **on a Windows PC** so Python, zotify, and ffmpeg can be bundled inside the app (same as the Mac DMG).

**Prerequisites on Windows:**
1. **Node.js LTS** from https://nodejs.org (must provide `npm` on PATH)
2. Git (for cloning zotify during the runtime bundle)
3. Open a **new** PowerShell after installing Node

On Windows (PowerShell):

```powershell
cd oz-downloader   # or oz-downloader-main\oz-downloader-main
powershell -ExecutionPolicy Bypass -File .\scripts\make_windows_installer.ps1
```

Or step by step:

```powershell
# 1. Bundle Python + zotify + ffmpeg (postprocess script is now in this repo)
powershell -ExecutionPolicy Bypass -File .\scripts\bundle_windows_runtime.ps1

# 2. Build installer
cd windows
npm install
npm run dist:win
```

Creates:
- `windows/dist-installer/OzDownloader-Installer.exe`

Copy to Desktop or share with users. Without the bundled runtime, link preview may work but **downloads will not**.

No separate `Desktop\zotify-tools` folder is required anymore.

---

### Signed + notarized release

```bash
export SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export APPLE_ID="you@example.com"
export APPLE_TEAM_ID="TEAMID"
export APPLE_APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"
./scripts/make_dmg.sh
```

---

## Run from source

```bash
open ~/Desktop/ZotifyStudio/ZotifyStudio.xcodeproj
```

Or rebuild the app binary into `build/Oz Downloader.app` via `scripts/make_dmg.sh` / local `swiftc`.

---

## Testing

See **[E2E_TEST_PLAN.md](./E2E_TEST_PLAN.md)** for the end-to-end test plan.

```bash
./scripts/e2e_test.sh                # release + tools smoke
./scripts/e2e_downloads_test.sh      # track / playlists / cancel / formats
```

---

## Support

- Email: mailosman.dev@gmail.com  
- Instagram: @oz.suliman  
