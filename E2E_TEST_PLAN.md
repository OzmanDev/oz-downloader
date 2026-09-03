# Oz Downloader — End-to-End Test Plan

Manual E2E checklist for **v0.2.0**. Run against a fresh install from `OzDownloader-Installer.dmg` when possible, and again after major download/convert changes.

**Pass criteria:** each case ends in the expected UI state **and** the expected files on disk. Note macOS version + Apple Silicon/Intel on the report.

---

## Automated smoke

```bash
cd ~/Desktop/ZotifyStudio
chmod +x scripts/e2e_test.sh scripts/e2e_downloads_test.sh

# Release / tools / convert fixture smoke
./scripts/e2e_test.sh
./scripts/e2e_test.sh --offline

# Downloads: track, playlist, 2 lists, cancel, auth, all formats
./scripts/e2e_downloads_test.sh
./scripts/e2e_downloads_test.sh --lifecycle-only   # D5–D8 only
./scripts/e2e_downloads_test.sh --formats-only
./scripts/e2e_downloads_test.sh --no-live

# Full automated run + HTML report (cases, steps, results)
./scripts/e2e_run_all.sh
# → Desktop/OzDownloader-E2E-Report.html
# → build/e2e-reports/latest.html

# UI / OAuth / Gatekeeper suite only
./scripts/e2e_ui_test.sh
# Optional: OZ_E2E_SPOTIFY_USER / OZ_E2E_SPOTIFY_PASS for A1/A3
# Optional: OZ_E2E_ALLOW_NETWORK_FLIP=1 for X3
# Requires Xcode.app for XCUITest, or Accessibility permission for AX fallback.
# R3 (second Mac) remains manual.
```

Cases marked **manual** still need a human (UI buttons, second Mac, OAuth browser chrome).

---

## 0. Environment prep

| Step | Action |
|------|--------|
| 0.1 | Use a clean Mac user or reset app data: quit app, remove `~/Library/Application Support/OzDownloader/` if testing first-run |
| 0.2 | Optional clean library: move/rename `~/Music/Oz Downloader` so downloads start empty |
| 0.3 | Install from Desktop DMG → Applications (or open `build/Oz Downloader.app` for local builds) |
| 0.4 | Confirm Preferences → Spotify account can sign in |
| 0.5 | Confirm Preferences: FLAC + **Convert automatically** ON, skip-existing ON |

**Fixtures (suggested):**

- [Pilé - Gospel](https://open.spotify.com/playlist/27sDUOL87sti0cNV1GyDy6) — 3 songs (~8 min) — full download / convert
- [رواقة](https://open.spotify.com/playlist/0AHqGidWige3fk8sGpqkgk) — 20 songs — second queue / cancel mid-list (do not full-download in automated E2E)
- Single track URL
- Album URL
- Playlist that already has some songs on disk (for skip / partial convert)

---

## 1. Install & Gatekeeper

| ID | Case | Steps | Expected |
|----|------|-------|----------|
| I1 | Fresh DMG install | Open notarized DMG → drag to Applications → open | App launches; no persistent malware block on notarized build |
| I2 | First open if blocked | Right-click → Open | App opens after confirmation |
| I3 | Bundled tools | Preferences / download without Terminal Python | Downloads work; no “tool missing” for zotify/ffmpeg |

---

## 2. Sign-in

| ID | Case | Steps | Expected |
|----|------|-------|----------|
| A1 | Sign in from Preferences | Preferences → Sign in → complete browser OAuth | Account name shown; “Signed in with Spotify” |
| A2 | Sign out | Preferences → Sign out | Session cleared; must sign in again to download |
| A3 | Mid-download auth | Start download with expired/missing session | Polished sign-in flow (success page), then download continues or retries cleanly — not a raw librespot blank page loop |

---

## 3. Get Music — preview & queue

| ID | Case | Steps | Expected |
|----|------|-------|----------|
| G1 | Playlist preview | Paste Spotify playlist link | Preview shows name + song count; no Save as section on Get Music |
| G2 | Download | Press download / add to queue | Progress appears; status updates |
| G3 | Album / track | Paste album and single-track URLs | Preview + download succeed |
| G4 | Invalid URL | Paste non-Spotify text | Clear error; no crash |

---

## 4. Download & folder layout

| ID | Case | Steps | Expected |
|----|------|-------|----------|
| D1 | Playlist folder | Download a new playlist | Files under `~/Music/Oz Downloader/<Playlist Name>/` — **not** loose in the music root |
| D2 | Progress honesty | Watch Progress during download | Song rows update; Total N of M matches disk when finished |
| D3 | Skip existing | Re-download same playlist | Already-on-disk tracks skipped; no duplicate mess |
| D4 | Open folder | Click **Open default download folder** | Finder opens the configured root |
| D5 | Full list | Download [Pilé - Gospel](https://open.spotify.com/playlist/27sDUOL87sti0cNV1GyDy6) completely | All tracks on disk (3) |
| D6 | Partial list | Start Pilé (or رواقة) → Cancel after first track(s) | Incomplete folder (`n <` full count); Progress not “all done” celebration |
| D7 | Existed unconverted | Playlist folder already has `.ogg` → download again | Skip-existing; same file count; no duplicates |
| D8 | Existed converted | Playlist folder already has `.flac` → download again (+ convert ON) | Skips; FLACs kept; no leftover duplicate `.ogg` mess |

Automated: `./scripts/e2e_downloads_test.sh` covers D5–D8 (full / partial / exist-unconv / exist-conv).

---

## 5. Convert & tagging

| ID | Case | Steps | Expected |
|----|------|-------|----------|
| C1 | Convert on | Preferences: FLAC + convert ON → download playlist | Progress shows convert success (not Failed / Skipped incorrectly) |
| C2 | Output format | After C1, open playlist folder | `.flac` files (not leftover `.ogg`); sensible renamed titles |
| C3 | Genre tag | Set default genre in Preferences → download | Genre present in FLAC tags (spot-check in Music / `ffprobe` / Get Info) |
| C4 | Convert off | Turn convert OFF → download | `.ogg` (or configured download format) remains; no convert failure row |
| C5 | Re-download with convert | OGG already on disk, convert ON | Convert still runs and produces FLAC in the playlist folder |
| C6 | All formats | Preferences / script: flac, mp3, m4a, wav, ogg, none | Each produces the expected extension; Spotify OGGs with embedded cover art convert (incl. **m4a**) without hang/fail |

Automated coverage for track, playlist, two lists, cancel list/track, before/after login, Get Music vs playlist URL paths, and format matrix: `./scripts/e2e_downloads_test.sh`.

---

## 6. Cancel & errors

| ID | Case | Steps | Expected |
|----|------|-------|----------|
| X1 | Cancel mid-download | Start playlist → Cancel | Stops cleanly; UI does not blank/flicker; no false “all done” celebration for cancelled job |
| X2 | Cancel playlist in queue | Multi-item queue if available → cancel one | Remaining queue behavior is sane; no stuck spinner |
| X3 | Network drop | Disable Wi‑Fi mid-download | Error or retry messaging; app recoverable after network returns |

---

## 7. My Playlists

| ID | Case | Steps | Expected |
|----|------|-------|----------|
| P1 | Load library | My Playlists after sign-in | Owned/followed playlists list loads (or clear rate-limit message) |
| P2 | Download from list | Start download from a listed playlist | Same folder + convert behavior as Get Music |
| P3 | Remembered playlists | After Get Music download | Playlist appears / is remembered as designed |

---

## 8. Preferences UI

| ID | Case | Steps | Expected |
|----|------|-------|----------|
| S1 | No Dependencies block | Open Preferences | No “Ready to sign in” / Dependencies card |
| S2 | Change folder | Choose another download folder → download once | Files land in the new root / playlist subfolder |
| S3 | Quality / convert toggles | Change settings → Save → restart app | Settings persist |

---

## 9. Release / distribution smoke

| ID | Case | Steps | Expected |
|----|------|-------|----------|
| R1 | Notarization | `spctl -a -vv -t install ~/Desktop/OzDownloader-Installer.dmg` | `accepted` · `Notarized Developer ID` |
| R2 | Staple | `xcrun stapler validate ~/Desktop/OzDownloader-Installer.dmg` | Validate succeeded |
| R3 | Second Mac | Copy DMG to another Mac, install, sign in, download 1 song | Works without Terminal; Gatekeeper OK |

---

## Suggested run order (smoke, ~20 min)

1. **I1 → A1 → G1 → D1 → C1 → C2** (happy path)  
2. **D3 → C5** (skip + convert existing)  
3. **X1** (cancel)  
4. **S1 → R1** (UI + notarization)  

Full regression: all tables above.

---

## Bug report template

```text
Case ID:
Build: DMG / build/Oz Downloader.app · version:
macOS:
Steps:
Expected:
Actual:
Disk path / file list:
Screenshot / Progress text:
```

---

## Out of scope (for now)

- Full XCUITest UI automation (browser OAuth, cancel UX, My Playlists UI remain manual)  
- Windows / Linux  
- Spotify Connect / playback inside the app  
- Large library stress (1000+ track playlists) — optional soak later  
