# Oz Downloader (native Swift)

Native macOS app for downloading Spotify playlists.

## Defaults

Starts **empty** — no playlists or Spotify session bundled.

App data:

```text
~/Library/Application Support/OzDownloader/
```

## Build DMG

```bash
cd ~/Desktop/ZotifyStudio
./scripts/make_dmg.sh
```

Creates:

- `build/Oz Downloader.app` (with **Z** icon)
- **`~/Desktop/OzDownloader-Installer.dmg`**

## Run from source

```bash
open ~/Desktop/ZotifyStudio/ZotifyStudio.xcodeproj
```

Requires **zotify** installed (`zotify-tools/./install.sh`).
