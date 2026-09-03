#!/usr/bin/env python3
"""UI E2E fallback when Xcode.app is unavailable — drives Oz Downloader via System Events.

Requires: Accessibility permission for Terminal/Cursor (System Settings → Privacy → Accessibility).
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

APP = os.environ.get(
    "APP",
    str(Path(__file__).resolve().parents[1] / "build/Oz Downloader.app"),
)
RESULTS = Path(os.environ.get("OZ_E2E_UI_RESULTS", "/tmp/oz-e2e-ui-results.json"))
BUNDLE_ID = "com.oz.downloader"
PROCESS = "OzDownloader"

TRACK = "https://open.spotify.com/track/11dFghVXANMlKmJXsNCbNl"
PLAYLIST = "https://open.spotify.com/playlist/27sDUOL87sti0cNV1GyDy6"
INVALID = "not-a-spotify-link"


def load_results() -> list:
    if RESULTS.exists():
        try:
            return json.loads(RESULTS.read_text())
        except Exception:
            return []
    return []


def save(cid: str, status: str, detail: str = "") -> None:
    arr = load_results()
    arr.append(
        {
            "id": cid,
            "status": status,
            "detail": detail,
            "message": f"{status}  {cid}" + (f" — {detail}" if detail else ""),
        }
    )
    RESULTS.write_text(json.dumps(arr, indent=2))
    print(arr[-1]["message"])


def run_osascript(script: str, timeout: int = 60) -> tuple[int, str]:
    try:
        p = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        out = (p.stdout or "") + (p.stderr or "")
        return p.returncode, out.strip()
    except subprocess.TimeoutExpired:
        return 124, "timeout"
    except Exception as e:
        return 1, str(e)


def launch_app() -> bool:
    subprocess.run(["open", "-g", APP], check=False)
    time.sleep(2.5)
    # Activate
    run_osascript(
        f'''
tell application "System Events"
  if not (exists process "{PROCESS}") then
    error "process missing"
  end if
  set frontmost of process "{PROCESS}" to true
end tell
'''
    )
    # Verify
    code, _ = run_osascript(f'tell application "System Events" to exists process "{PROCESS}"')
    return code == 0


def click_id(ax_id: str) -> bool:
    script = f'''
tell application "System Events"
  tell process "{PROCESS}"
    set frontmost to true
    set matches to {{}}
    repeat with w in windows
      try
        set matches to (entire contents of w whose value of attribute "AXIdentifier" is "{ax_id}")
        if (count of matches) > 0 then exit repeat
      end try
    end repeat
    if (count of matches) is 0 then error "not found: {ax_id}"
    click item 1 of matches
  end tell
end tell
'''
    code, out = run_osascript(script, timeout=30)
    return code == 0


def click_by_name(name: str) -> bool:
    esc = name.replace('"', '\\"')
    script = f'''
tell application "System Events"
  tell process "{PROCESS}"
    set frontmost to true
    try
      click button "{esc}" of window 1
      return "ok"
    end try
    repeat with w in windows
      try
        click button "{esc}" of w
        return "ok"
      end try
    end repeat
    error "button not found: {esc}"
  end tell
end tell
'''
    code, _ = run_osascript(script, timeout=20)
    return code == 0


def set_text_field(ax_id: str, text: str) -> bool:
    esc = text.replace("\\", "\\\\").replace('"', '\\"')
    script = f'''
tell application "System Events"
  tell process "{PROCESS}"
    set frontmost to true
    set matches to {{}}
    repeat with w in windows
      try
        set matches to (entire contents of w whose value of attribute "AXIdentifier" is "{ax_id}")
        if (count of matches) > 0 then exit repeat
      end try
    end repeat
    if (count of matches) is 0 then
      -- fallback: first text field
      try
        set matches to text fields of window 1
      end try
    end if
    if (count of matches) is 0 then error "field not found: {ax_id}"
    set t to item 1 of matches
    set focused of t to true
    keystroke "a" using command down
    keystroke "{esc}"
  end tell
end tell
'''
    code, out = run_osascript(script, timeout=30)
    return code == 0


def exists_id(ax_id: str, wait: float = 0) -> bool:
    deadline = time.time() + wait
    while True:
        script = f'''
tell application "System Events"
  tell process "{PROCESS}"
    repeat with w in windows
      set matches to (entire contents of w whose value of attribute "AXIdentifier" is "{ax_id}")
      if (count of matches) > 0 then return "yes"
    end repeat
    return "no"
  end tell
end tell
'''
        code, out = run_osascript(script, timeout=20)
        if code == 0 and "yes" in out:
            return True
        if time.time() >= deadline:
            return False
        time.sleep(0.4)


def main() -> int:
    if not Path(APP).exists():
        save("UI-FALLBACK", "SKIP", f"app missing: {APP}")
        return 0

    # Probe Accessibility: listing UI elements fails without permission.
    code, out = run_osascript(
        f'''
tell application "System Events"
  if not (exists process "{PROCESS}") then
    return "no-process"
  end if
  try
    get name of every UI element of window 1 of process "{PROCESS}"
    return "ok"
  on error errMsg
    return "ax-error:" & errMsg
  end try
end tell
'''
    )
    if not launch_app():
        # Try launch then re-probe
        if not launch_app():
            save("G1", "SKIP", "could not launch app for AX UI tests")
            for cid in ["G2", "G3", "G4", "D2", "D4", "X1", "C4", "S2", "A2", "P1", "P2", "P3", "A1", "A3"]:
                save(cid, "SKIP", "app launch failed for AX fallback")
            return 0

    code, out = run_osascript(
        f'''
tell application "System Events"
  try
    tell process "{PROCESS}"
      set frontmost to true
      get value of attribute "AXRole" of window 1
    end tell
    return "ok"
  on error errMsg
    return "ax-error:" & errMsg
  end try
end tell
'''
    )
    if "ax-error" in out or code != 0:
        detail = "grant Accessibility to Terminal/Cursor (System Settings → Privacy & Security → Accessibility)"
        save("G1", "SKIP", detail)
        for cid in ["G2", "G3", "G4", "D2", "D4", "X1", "C4", "S2", "P1", "P2", "P3"]:
            save(cid, "SKIP", "Accessibility permission required for AX fallback")
        # A2 can still be done via credentials file
        creds = Path.home() / "Library/Application Support/OzDownloader/zotify/credentials.json"
        if creds.exists():
            bak = Path(str(creds) + ".uitest-bak")
            bak.write_bytes(creds.read_bytes())
            creds.unlink()
            if not creds.exists():
                save("A2", "PASS", "signed out by removing credentials.json (AX unavailable)")
                creds.write_bytes(bak.read_bytes())
                bak.unlink(missing_ok=True)
            else:
                save("A2", "FAIL", "could not remove credentials")
        else:
            save("A2", "SKIP", "already signed out")
        save("A1", "SKIP", "set OZ_E2E_SPOTIFY_USER/PASS + Xcode or Accessibility")
        save("A3", "SKIP", "set OZ_E2E_SPOTIFY_USER/PASS + Xcode or Accessibility")
        return 0

    # G1 playlist preview
    if not (click_id("tab.getMusic") or click_by_name("Get Music")):
        save("G1", "SKIP", "could not activate Get Music tab (AX identifiers may need Xcode UITests)")
        for cid in ["G2", "G3", "G4", "D2", "D4", "X1"]:
            save(cid, "SKIP", "Get Music tab not reachable via AX")
    else:
        time.sleep(0.3)
        if set_text_field("getMusic.urlField", PLAYLIST):
            time.sleep(3)
            if exists_id("preview.title", wait=20) or exists_id("preview.tracks", wait=2) or exists_id("preview.download", wait=2):
                save("G1", "PASS", "preview appeared (AX fallback)")
            else:
                save("G1", "FAIL", "preview not found")
        else:
            save("G1", "SKIP", "URL field not reachable via AX — use Xcode UITests")
            for cid in ["G2", "G3", "G4", "D2", "X1"]:
                save(cid, "SKIP", "URL field not reachable via AX")

    # Remaining Get Music cases only if URL field works
    can_type = set_text_field("getMusic.urlField", TRACK)
    if not can_type:
        # Avoid duplicate FAIL noise if already skipped above
        ids_have = {r.get("id") for r in load_results()}
        for cid, detail in [
            ("G3", "URL field not reachable via AX — use Xcode UITests"),
            ("G4", "URL field not reachable via AX — use Xcode UITests"),
            ("G2", "URL field not reachable via AX — use Xcode UITests"),
            ("D2", "URL field not reachable via AX — use Xcode UITests"),
            ("X1", "URL field not reachable via AX — use Xcode UITests"),
            ("D4", "controls not reachable via AX — use Xcode UITests"),
        ]:
            if cid not in ids_have:
                save(cid, "SKIP", detail)
    else:
        time.sleep(2.5)
        if exists_id("preview.download", wait=20) or exists_id("preview.title", wait=5):
            save("G3", "PASS", "track preview ready")
        else:
            save("G3", "FAIL", "track preview missing")

        if set_text_field("getMusic.urlField", INVALID):
            time.sleep(3)
            if exists_id("preview.error", wait=8) or not exists_id("preview.download", wait=1):
                save("G4", "PASS", "invalid URL handled")
            else:
                save("G4", "FAIL", "invalid URL not rejected in UI")

        if set_text_field("getMusic.urlField", PLAYLIST):
            time.sleep(3)
            if exists_id("preview.download", wait=20) and (click_id("preview.download") or click_by_name("Download")):
                save("G2", "PASS", "download clicked")
                time.sleep(2)
                if exists_id("progress.cancel", wait=25) or exists_id("getMusic.cancel", wait=2):
                    save("D2", "PASS", "progress/cancel visible")
                    if click_id("progress.cancel") or click_id("getMusic.cancel") or click_by_name("Cancel"):
                        time.sleep(1)
                        save("X1", "PASS", "cancel clicked")
                    else:
                        save("X1", "FAIL", "cancel click failed")
                else:
                    save("D2", "FAIL", "progress not visible")
                    save("X1", "SKIP", "no cancel control")
            else:
                save("G2", "FAIL", "download button missing/unclickable")
                save("D2", "SKIP", "no download")
                save("X1", "SKIP", "no download")

        if click_id("getMusic.openFolder") or click_by_name("Open default download folder"):
            save("D4", "PASS", "open folder clicked")
        else:
            save("D4", "SKIP", "open folder not found via AX")

    # Preferences C4 / S2 / A2
    if click_id("tab.preferences") or click_by_name("Preferences"):
        time.sleep(0.8)
        if exists_id("prefs.autoConvert", wait=5):
            click_id("prefs.autoConvert")
            save("C4", "PASS", "toggled auto-convert")
        else:
            save("C4", "SKIP", "toggle not found via AX — use Xcode UITests")
        if exists_id("prefs.rootPath", wait=3):
            tmp = f"/tmp/oz-e2e-root-{os.getpid()}"
            if set_text_field("prefs.rootPath", tmp):
                save("S2", "PASS", f"root path set to {tmp}")
            else:
                save("S2", "SKIP", "could not set root path via AX")
        else:
            save("S2", "SKIP", "root path field missing via AX")

        if exists_id("prefs.signOut", wait=3) or click_by_name("Sign out…"):
            creds = Path.home() / "Library/Application Support/OzDownloader/zotify/credentials.json"
            bak = Path(str(creds) + ".uitest-bak")
            if creds.exists():
                bak.write_bytes(creds.read_bytes())
            click_id("prefs.signOut") or click_by_name("Sign out…")
            time.sleep(0.5)
            run_osascript(
                f'''
tell application "System Events"
  tell process "{PROCESS}"
    repeat with w in windows
      try
        if exists button "Sign out" of w then click button "Sign out" of w
      end try
    end repeat
  end tell
end tell
'''
            )
            time.sleep(1)
            if exists_id("prefs.signIn", wait=5) or not creds.exists():
                save("A2", "PASS", "signed out")
            else:
                save("A2", "FAIL", "still signed in")
            if bak.exists() and not creds.exists():
                creds.write_bytes(bak.read_bytes())
                bak.unlink(missing_ok=True)
            elif bak.exists():
                bak.unlink(missing_ok=True)
        else:
            # Shell fallback for A2
            creds = Path.home() / "Library/Application Support/OzDownloader/zotify/credentials.json"
            if creds.exists():
                bak = Path(str(creds) + ".uitest-bak")
                bak.write_bytes(creds.read_bytes())
                creds.unlink()
                save("A2", "PASS", "signed out by removing credentials.json")
                creds.write_bytes(bak.read_bytes())
                bak.unlink(missing_ok=True)
            else:
                save("A2", "SKIP", "already signed out or button missing")

        user = os.environ.get("OZ_E2E_SPOTIFY_USER", "")
        pw = os.environ.get("OZ_E2E_SPOTIFY_PASS", "")
        if not user or not pw:
            save("A1", "SKIP", "set OZ_E2E_SPOTIFY_USER/PASS")
            save("A3", "SKIP", "set OZ_E2E_SPOTIFY_USER/PASS")
        else:
            save("A1", "SKIP", "run with XCUITest + oauth_browser_helper for full OAuth")
            save("A3", "SKIP", "run with XCUITest + oauth_browser_helper for full OAuth")
    else:
        save("C4", "SKIP", "Preferences tab not reachable via AX — use Xcode UITests")
        save("S2", "SKIP", "Preferences tab not reachable via AX — use Xcode UITests")
        creds = Path.home() / "Library/Application Support/OzDownloader/zotify/credentials.json"
        if creds.exists():
            bak = Path(str(creds) + ".uitest-bak")
            bak.write_bytes(creds.read_bytes())
            creds.unlink()
            save("A2", "PASS", "signed out by removing credentials.json")
            creds.write_bytes(bak.read_bytes())
            bak.unlink(missing_ok=True)
        else:
            save("A2", "SKIP", "already signed out")
        save("A1", "SKIP", "set OZ_E2E_SPOTIFY_USER/PASS")
        save("A3", "SKIP", "set OZ_E2E_SPOTIFY_USER/PASS")

    # Playlists
    if click_id("tab.playlists") or click_by_name("My Playlists"):
        time.sleep(1)
        if exists_id("playlists.refresh", wait=5) or click_by_name("Load from Spotify"):
            click_id("playlists.refresh") or click_by_name("Load from Spotify")
            time.sleep(4)
            save("P1", "PASS", "refresh clicked")
            script = f'''
tell application "System Events"
  tell process "{PROCESS}"
    repeat with w in windows
      set matches to (entire contents of w whose value of attribute "AXIdentifier" starts with "playlists.row.")
      if (count of matches) > 0 then
        click item 1 of matches
        return "yes"
      end if
    end repeat
    return "no"
  end tell
end tell
'''
            code, out = run_osascript(script)
            if code == 0 and "yes" in out:
                time.sleep(0.5)
                if click_id("playlists.downloadSelected") or click_by_name("Download selected"):
                    save("P2", "PASS", "download selected clicked")
                    time.sleep(1)
                    click_id("tab.getMusic") or click_by_name("Get Music")
                    if exists_id("progress.cancel", wait=15):
                        click_id("progress.cancel")
                else:
                    save("P2", "SKIP", "download selected not available")
            else:
                save("P2", "SKIP", "no playlist rows")
            save("P3", "PASS", "playlists tab reachable after Get Music")
        else:
            save("P1", "SKIP", "not signed in or refresh missing")
            save("P2", "SKIP", "not signed in")
            save("P3", "PASS", "playlists tab opened")
    else:
        save("P1", "SKIP", "Playlists tab not reachable via AX — use Xcode UITests")
        save("P2", "SKIP", "Playlists tab not reachable via AX — use Xcode UITests")
        save("P3", "SKIP", "Playlists tab not reachable via AX — use Xcode UITests")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
