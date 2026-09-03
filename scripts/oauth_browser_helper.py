#!/usr/bin/env python3
"""Complete Spotify OAuth in a browser when Oz Downloader writes e2e_oauth_url.txt.

Requires:
  OZ_E2E_SPOTIFY_USER
  OZ_E2E_SPOTIFY_PASS

Uses Playwright if installed (`pip install playwright && playwright install chromium`),
otherwise falls back to opening the system browser (manual completion still needed).
"""
from __future__ import annotations

import argparse
import os
import sys
import time
import webbrowser
from pathlib import Path


def playwright_login(url: str, user: str, password: str, timeout_s: int = 120) -> bool:
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print("playwright not installed", file=sys.stderr)
        return False

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=False)
        page = browser.new_page()
        page.goto(url, wait_until="domcontentloaded")
        # Spotify login form selectors evolve; try common ones.
        try:
            page.wait_for_selector('input#login-username, input[name="username"], input[type="email"]', timeout=20000)
        except Exception:
            print("login form not found", file=sys.stderr)
            browser.close()
            return False

        user_sel = 'input#login-username, input[name="username"], input[type="email"]'
        pass_sel = 'input#login-password, input[name="password"], input[type="password"]'
        page.fill(user_sel, user)
        # Continue / next if present
        for label in ("Continue", "Next", "Log in", "Login"):
            btn = page.get_by_role("button", name=label)
            if btn.count():
                try:
                    btn.first.click(timeout=2000)
                    break
                except Exception:
                    pass
        page.wait_for_timeout(800)
        if page.locator(pass_sel).count():
            page.fill(pass_sel, password)
            for label in ("Log in", "Login", "Continue", "Sign in"):
                btn = page.get_by_role("button", name=label)
                if btn.count():
                    try:
                        btn.first.click(timeout=2000)
                        break
                    except Exception:
                        pass
        # Agree / Authorize if consent screen
        deadline = time.time() + timeout_s
        while time.time() < deadline:
            for label in ("Agree", "Allow", "Accept", "Authorize"):
                btn = page.get_by_role("button", name=label)
                if btn.count():
                    try:
                        btn.first.click(timeout=1500)
                    except Exception:
                        pass
            # Success often redirects to localhost callback then closes
            if "127.0.0.1" in page.url or "localhost" in page.url or "/login" in page.url:
                time.sleep(1.5)
                browser.close()
                return True
            # Detect app success page text
            body = ""
            try:
                body = page.content().lower()
            except Exception:
                pass
            if "success" in body and "spotify" in body:
                time.sleep(1)
                browser.close()
                return True
            page.wait_for_timeout(1000)
        browser.close()
        return False


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", help="Authorize URL (else read e2e_oauth_url.txt)")
    ap.add_argument("--timeout", type=int, default=120)
    args = ap.parse_args()

    user = os.environ.get("OZ_E2E_SPOTIFY_USER", "")
    password = os.environ.get("OZ_E2E_SPOTIFY_PASS", "")
    if not user or not password:
        print("SKIP: set OZ_E2E_SPOTIFY_USER and OZ_E2E_SPOTIFY_PASS", file=sys.stderr)
        return 2

    url = args.url
    if not url:
        path = Path.home() / "Library/Application Support/OzDownloader/e2e_oauth_url.txt"
        if path.exists():
            url = path.read_text(encoding="utf-8").strip()
    if not url:
        print("No OAuth URL", file=sys.stderr)
        return 1

    print(f"OAuth URL: {url[:80]}…")
    if playwright_login(url, user, password, timeout_s=args.timeout):
        print("OK playwright login")
        return 0

    print("Falling back to system browser (complete login manually)", file=sys.stderr)
    webbrowser.open(url)
    # Wait for credentials file to appear/update
    creds = Path.home() / "Library/Application Support/OzDownloader/zotify/credentials.json"
    deadline = time.time() + args.timeout
    while time.time() < deadline:
        if creds.exists() and creds.stat().st_size > 20:
            print("OK credentials present after browser open")
            return 0
        time.sleep(1)
    print("TIMEOUT waiting for credentials", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
