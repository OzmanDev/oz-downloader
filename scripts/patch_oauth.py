#!/usr/bin/env python3
"""Patch librespot OAuth refresh to tolerate missing refresh_token in Spotify responses."""

from __future__ import annotations

import sys
from pathlib import Path

OLD = '''    def ingest_token_response(self, result):
        self.__token = result["access_token"]
        self.__refresh_token = result["refresh_token"]
        if "expires_in" in result:
            self.__token_expires_at = datetime.now() + timedelta(seconds=result["expires_in"])
        elif "expires_at" in result:
            self.__token_expires_at = datetime.fromtimestamp(result["expires_at"])
        return self'''

NEW = '''    def ingest_token_response(self, result):
        self.__token = result["access_token"]
        # Spotify often omits refresh_token on refresh responses; keep the existing one.
        if "refresh_token" in result and result["refresh_token"]:
            self.__refresh_token = result["refresh_token"]
        if "expires_in" in result:
            self.__token_expires_at = datetime.now() + timedelta(seconds=result["expires_in"])
        elif "expires_at" in result:
            self.__token_expires_at = datetime.fromtimestamp(result["expires_at"])
        return self'''

ALREADY = 'if "refresh_token" in result and result["refresh_token"]:'


def find_oauth_files() -> list[Path]:
    files = []
    try:
        import librespot
        pkg = Path(librespot.__file__).resolve().parent
        cand = pkg / "oauth.py"
        if cand.exists():
            files.append(cand)
    except Exception:
        pass

    # Fallback common locations
    for base in [
        Path.home() / ".local/lib",
        Path("/opt/anaconda3/lib"),
        Path("/usr/local/lib"),
        Path(sys.prefix) / "lib",
    ]:
        if not base.exists():
            continue
        for cand in base.rglob("librespot/oauth.py"):
            if cand not in files:
                files.append(cand)
    return files


def patch_file(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    if ALREADY in text:
        return "already-patched"
    if OLD not in text:
        return "unexpected-content"
    path.write_text(text.replace(OLD, NEW), encoding="utf-8")
    return "patched"


def main() -> int:
    files = find_oauth_files()
    if not files:
        print("WARNING: could not find librespot/oauth.py to patch", file=sys.stderr)
        return 1

    status = 0
    for path in files:
        result = patch_file(path)
        print(f"{result}: {path}")
        if result == "unexpected-content":
            status = 1
    return status


if __name__ == "__main__":
    raise SystemExit(main())
