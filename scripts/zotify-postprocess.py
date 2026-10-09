#!/usr/bin/env python3
"""Post-process Zotify downloads.

For each given folder:
  1. Convert audio (.ogg/.mp3/.m4a/...) to FLAC
  2. Rename to song-title-only filenames
  3. Embed title/artist/album/year/genre/track/lyrics into tags
  4. Remove duplicate tracks (keep larger file)
  5. Update .song_ids paths (+ add missing IDs when possible)

Usage:
  zotify-postprocess "~/Music/Zotify Music/Dj RnB"
  zotify-postprocess "~/Music/Zotify Music/Dj RnB" --genre "R&B"
  zotify-postprocess --all
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from html import unescape
import subprocess
import sys
import threading
import time
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path

from mutagen import File as MutagenFile
from mutagen.flac import FLAC, Picture
from mutagen.id3 import APIC, ID3, TIT2, TPE1, TALB, TPE2, TRCK, TCON, COMM, USLT, TDRC
from mutagen.mp4 import MP4

AUDIO_EXTS = {".ogg", ".mp3", ".m4a", ".aac", ".opus", ".wav", ".flac"}
OUTPUT_FORMATS = {"flac", "mp3", "m4a", "wav", "ogg"}
CREDS_CANDIDATES = [
    Path.home() / "Library/Application Support/OzDownloader/zotify/credentials.json",  # Oz Downloader (macOS)
    Path.home() / "Library/Application Support/Zotify/credentials.json",  # macOS
    Path.home() / ".config/zotify/credentials.json",  # Linux
    Path.home() / "AppData/Roaming/Zotify/credentials.json",  # Windows
    Path.home() / "AppData/Roaming/OzDownloader/zotify/credentials.json",  # Oz Downloader (Windows)
]


def creds_path() -> Path | None:
    for p in CREDS_CANDIDATES:
        if p.exists():
            return p
    return None


def sanitize_filename(name: str) -> str:
    """Make a safe filename without turning * ? \" into '_' (that breaks Artist_Title parses)."""
    name = name.strip().rstrip(".")
    # Strip chars that are illegal on Windows / confuse parsers — do not use '_'
    # (underscore splits legacy Artist_Title stems into garbage like gga.flac / 's.flac).
    for ch in ':/\\?*|"<>':
        name = name.replace(ch, "")
    # Collapse leftover whitespace from removed punctuation (Hot N*gga → Hot Ngga).
    name = re.sub(r"\s+", " ", name).strip()
    return name or "Unknown"


def norm(s: str) -> str:
    return "".join(c.lower() for c in (s or "") if c.isalnum() or c.isspace()).strip()


def clean_title(title: str) -> str:
    t = (title or "").strip()
    while t.startswith("_"):
        t = t[1:].strip()
    return t or title or "Unknown"


def missing_artist(artist: str) -> bool:
    return (artist or "").strip().lower() in {
        "", "_", "-", "unknown", "untitled", "untitled artist", "unknown artist",
    }


def clean_artist(artist: str) -> str:
    a = (artist or "").strip()
    if missing_artist(a):
        return ""
    return a


def primary_artist(artist: str) -> str:
    """First credited name. A long 'A, B, C' list makes public search miss the song."""
    artist = clean_artist(artist)
    if not artist:
        return ""
    head = re.split(r",|&| feat\.?| ft\.?| featuring ", artist, maxsplit=1, flags=re.IGNORECASE)[0]
    return clean_artist(head.strip())


def decide_metadata(
    stem: str, tag_artist: str, tag_title: str, tag_album: str
) -> tuple[int | None, str, str, bool]:
    """Choose track, artist, title, and whether a feature credit must match.

    Convert and refetch both call this before tags are written. A feature credit
    is not a song name, and a trailing playlist index is not a song name.
    """
    raw_artist = tag_artist or ""
    raw_title = tag_title or ""
    track, parsed_artist, parsed_title = parse_name(stem)
    parsed_artist = clean_artist(parsed_artist or "")
    parsed_title = clean_title(parsed_title) if (parsed_title or "").strip() else ""
    cleaned_artist = clean_artist(raw_artist)
    cleaned_title = clean_title(raw_title) if raw_title.strip() else ""

    artist = parsed_artist or cleaned_artist
    # An empty stem is not a title. clean_title("") would invent "Unknown".
    title = parsed_title or cleaned_title or (clean_title(stem) if (stem or "").strip() else "")

    if parsed_artist and parsed_title:
        bad = f"{parsed_artist}_{parsed_title}"
        if cleaned_title == bad or cleaned_title.lower().startswith(parsed_artist.lower() + "_"):
            title = parsed_title
            artist = parsed_artist
    elif cleaned_title and "_" in cleaned_title:
        _, parsed_from_title_artist, parsed_from_title = parse_name(cleaned_title)
        if parsed_from_title:
            title = clean_title(parsed_from_title)
            artist = clean_artist(parsed_from_title_artist or cleaned_artist) or cleaned_artist

    if cleaned_artist.endswith(" - From"):
        title = clean_title(parsed_title or raw_title.replace("_", " ").strip()) or title
        artist = clean_artist(cleaned_artist[:-6].strip()) or artist

    # A filename that is only "(feat. …)" must not replace a real title already in the tags.
    if is_feat_fragment(parsed_title) and cleaned_title and not is_feat_fragment(cleaned_title):
        title = cleaned_title
        if not missing_artist(cleaned_artist):
            artist = cleaned_artist

    # A filename that is only a track index must not replace a real title already in the tags.
    if (
        re.fullmatch(r"\d{1,3}", parsed_title or "")
        and cleaned_title
        and not re.fullmatch(r"\d{1,3}", cleaned_title)
    ):
        title = cleaned_title
        if not missing_artist(cleaned_artist):
            artist = cleaned_artist

    # A feature credit stored as the title is not the song name, and the song name is not the artist.
    if is_feat_fragment(title) and not is_feat_fragment(artist) and not missing_artist(artist):
        title = f"{artist} {title}".strip()
        artist = ""
    elif artist_holds_song_name(artist, title) and featured_people(title):
        artist = ""

    hidden = song_hidden_behind_number(artist, title, tag_album)
    if hidden:
        title = hidden
        artist = ""
    if missing_artist(artist):
        artist = ""

    # A feature-only filename must not force a new artist when the tags already name the song.
    # It still requires a feature match when the title itself is only that credit.
    require_feature_match = bool(featured_people(title)) and (
        is_feat_fragment(raw_title)
        or title_was_split_credit(stem)
        or artist_holds_song_name(raw_artist, title)
        or (is_feat_fragment(stem) and is_feat_fragment(title))
    )
    return track, artist, title, require_feature_match


def read_pictures(path: Path) -> list:
    audio = MutagenFile(path)
    if audio is None:
        return []
    if hasattr(audio, "pictures") and audio.pictures:
        return list(audio.pictures)
    if path.suffix.lower() == ".mp3":
        try:
            tags = ID3(path)
        except Exception:
            return []
        pics = []
        for frame in tags.getall("APIC"):
            pic = Picture()
            pic.type = getattr(frame, "type", 3) or 3
            pic.mime = frame.mime or "image/jpeg"
            pic.desc = frame.desc or "Cover"
            pic.data = frame.data
            pics.append(pic)
        return pics
    return []


def make_flac_picture(data: bytes, mime: str = "image/jpeg") -> Picture:
    pic = Picture()
    pic.type = 3
    pic.mime = mime or "image/jpeg"
    pic.desc = "Cover"
    pic.data = data
    return pic


def fetch_track_art(track_id: str, headers: dict | None) -> Picture | None:
    if not headers or not track_id:
        return None
    try:
        import requests
    except ImportError:
        return None
    r = requests.get(
        f"https://api.spotify.com/v1/tracks/{track_id}",
        headers=headers,
        timeout=30,
    )
    if r.status_code != 200:
        return None
    images = r.json().get("album", {}).get("images") or []
    if not images:
        return None
    img = requests.get(images[0]["url"], timeout=30)
    if img.status_code != 200 or not img.content:
        return None
    mime = img.headers.get("Content-Type") or "image/jpeg"
    return make_flac_picture(img.content, mime)


def fetch_cover_fallback(artist: str, title: str) -> Picture | None:
    """Fetch album art without Spotify OAuth (Deezer public API)."""
    try:
        import requests
    except ImportError:
        return None

    def try_search(query: str, want_artist: str, want_title: str) -> Picture | None:
        if not query.strip():
            return None
        r = requests.get(
            "https://api.deezer.com/search",
            params={"q": query, "limit": 12},
            timeout=30,
        )
        if r.status_code != 200:
            return None
        want_a = norm(want_artist)
        want_t = norm(re.sub(r"_(\d+)$", "", want_title))
        best = None
        best_score = 0
        for track in r.json().get("data") or []:
            t_title = norm(track.get("title", ""))
            t_artist = norm(track.get("artist", {}).get("name", ""))
            score = 0
            if want_t and (want_t in t_title or t_title in want_t):
                score += 2
            if want_a and (want_a in t_artist or t_artist in want_a):
                score += 2
            if score > best_score:
                url = (track.get("album") or {}).get("cover_xl") or (track.get("album") or {}).get("cover_big")
                if url:
                    best_score = score
                    best = url
        if not best:
            return None
        img = requests.get(best, timeout=30)
        if img.status_code == 200 and img.content:
            mime = img.headers.get("Content-Type") or "image/jpeg"
            return make_flac_picture(img.content, mime)
        return None

    clean_title = re.sub(r"_(\d+)$", "", title or "").strip()
    queries = [
        f"{artist} {clean_title}".strip(),
        clean_title,
        f"{artist} {re.sub(r' - .*', '', clean_title)}".strip(),
        re.sub(r"[^\w\s']+", " ", clean_title).strip(),
    ]
    seen = set()
    for q in queries:
        if not q or q in seen:
            continue
        seen.add(q)
        pic = try_search(q, artist, clean_title)
        if pic:
            return pic
    return None


_FEAT_FRAGMENT = re.compile(r"(?i)^\s*[\(\[]?\s*(?:feat\.?|ft\.?|featuring)(?=\s|$)")


def is_feat_fragment(text: str) -> bool:
    """True when the whole string is only a feature credit, like '(feat. Ja-Rule & Ashanti)'."""
    return bool(_FEAT_FRAGMENT.match((text or "").strip()))


def artist_holds_song_name(artist: str, title: str) -> bool:
    """True when the artist field is actually the song title, as in artist 'What's Luv'."""
    if missing_artist(artist) or is_feat_fragment(artist):
        return False
    song = canonical_title(title)
    return bool(song) and norm(artist) == song


def featured_people(text: str) -> list[str]:
    match = re.search(r"(?i)(?:feat\.?|ft\.?|featuring)\s+(.+)$", text or "")
    if not match:
        return []
    body = re.sub(r"[\)\]]+\s*$", "", match.group(1)).strip()
    parts = re.split(r"\s*(?:,|&|\band\b)\s*", body, flags=re.I)
    names = []
    for part in parts:
        name = part.strip("()[] ")
        if clean_artist(name):
            names.append(name)
    return names


def title_was_split_credit(stem: str) -> bool:
    """True when an underscore split a song name from a feature credit."""
    match = re.match(r"^(?:\d{2}_)?(.+?)_(.+)$", stem or "")
    return bool(match and is_feat_fragment(match.group(2)))


def song_hidden_behind_number(artist: str, title: str, album: str) -> str:
    """Return the real title when the title is only a track index like '66'.

    That happens for 'Song Name_66', which was stored as artist 'Song Name' and
    title '66'. The album then looks like 'Shakira: Bzrp Music Sessions, Vol. 53/66'.
    """
    number = (title or "").strip()
    if not re.fullmatch(r"\d{1,3}", number):
        return ""
    prefix = re.sub(r"/\d{1,3}$", "", (album or "").strip())
    if not prefix or re.fullmatch(r"\d{1,3}", prefix):
        return ""
    artist_key = norm(artist)
    prefix_key = norm(prefix)
    if artist_key and (artist_key == prefix_key or artist_key in prefix_key):
        return prefix
    return ""


def _person_mentioned(person: str, text: str) -> bool:
    needle = norm(person).replace(" ", "")
    hay = norm(text).replace(" ", "")
    return bool(needle) and needle in hay


def _join_split_credit(left: str, right: str) -> str | None:
    if not is_feat_fragment(right):
        return None
    return f"{left} {right}".strip()


def parse_name(stem: str):
    stem = (stem or "").strip()
    # Playlist: 01_Artist_Title
    m = re.match(r"^(\d{2})_(.+?)_(.+)$", stem)
    if m:
        joined = _join_split_credit(m.group(2), m.group(3))
        if joined:
            return int(m.group(1)), "", joined
        left, right = m.group(2), m.group(3)
        # "01_Song Name_66": the right side is a playlist index, not the title.
        if re.fullmatch(r"\d{1,3}", right) and not re.fullmatch(r"\d{1,3}", left):
            return int(m.group(1)), "", left
        return int(m.group(1)), left, right
    # Playlist with missing artist: 01__Title or 01_Title
    m = re.match(r"^(\d{2})__(.+)$", stem)
    if m:
        return int(m.group(1)), "", m.group(2)
    m = re.match(r"^(\d{2})_(.+)$", stem)
    if m and not re.match(r"^\d{2}_", m.group(2)):
        return int(m.group(1)), "", m.group(2)
    # Zotify placeholder when artist metadata was empty: _Title
    if stem.startswith("_"):
        return None, "", stem[1:].strip()
    # Legacy artist_title — only when artist segment is non-empty and not a lone underscore
    m = re.match(r"^(.+?)_(.+)$", stem)
    if m:
        artist, title = m.group(1), m.group(2)
        joined = _join_split_credit(artist, title)
        if joined:
            return None, None, joined
        # "Bzrp Music Sessions, Vol. 53_66" is the song name plus a trailing index.
        if re.fullmatch(r"\d{1,3}", title or "") and artist and not re.fullmatch(r"\d{1,3}", artist):
            return None, None, artist
        if artist and artist != "_":
            return None, artist, title
    return None, None, stem


def file_md5(path: Path) -> str:
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def ffmpeg_args_for(fmt: str) -> list[str]:
    fmt = fmt.lower()
    if fmt == "flac":
        return ["-c:a", "flac"]
    if fmt == "mp3":
        return ["-c:a", "libmp3lame", "-q:a", "0"]
    if fmt == "m4a":
        return ["-c:a", "aac", "-b:a", "256k"]
    if fmt == "wav":
        return ["-c:a", "pcm_s16le"]
    if fmt == "ogg":
        return ["-c:a", "libvorbis", "-q:a", "8"]
    raise ValueError(f"Unsupported format: {fmt}")


def convert_folder(folder: Path, fmt: str) -> tuple[int, int, dict[str, tuple[str, str]]]:
    """Convert non-target audio files in folder to fmt.

    Returns preserved artist/title tags keyed by output stem. ffmpeg strips
    metadata, and playlist filenames are title-only, so the artist would
    otherwise be lost.
    """
    fmt = fmt.lower()
    if fmt not in OUTPUT_FORMATS:
        raise ValueError(f"Unsupported format: {fmt}")
    target_ext = f".{fmt}"
    converted = failed = 0
    preserved: dict[str, tuple[str, str]] = {}
    for f in sorted(folder.iterdir()):
        if f.suffix.lower() not in AUDIO_EXTS:
            continue
        if f.suffix.lower() == target_ext:
            continue
        out = f.with_suffix(target_ext)
        preserved[out.stem.lower()] = read_easy_tags(f)
        pictures = read_pictures(f)
        # Map audio only and strip metadata: Spotify OGGs often embed cover art as a
        # video/MJPEG stream, which breaks m4a/ipod muxers. Avoid -vn with the bundled
        # ffmpeg — it can hang on those inputs; -map_metadata -1 + 0:a:0 is reliable.
        cmd = [
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
            "-i", str(f),
            "-map_metadata", "-1", "-map", "0:a:0",
            *ffmpeg_args_for(fmt),
            str(out),
        ]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode == 0 and out.exists() and out.stat().st_size > 0:
            if pictures and target_ext == ".flac":
                try:
                    audio = FLAC(out)
                    audio.clear_pictures()
                    for pic in pictures:
                        audio.add_picture(pic)
                    audio.save()
                except Exception:
                    pass
            f.unlink()
            converted += 1
            print(f"  converted: {f.name} -> {out.name}")
        else:
            failed += 1
            if out.exists():
                try:
                    out.unlink()
                except OSError:
                    pass
            print(f"  FAILED convert: {f.name}\n{r.stderr}", file=sys.stderr)
    return converted, failed, preserved


def write_tags(path: Path, *, title: str, artist: str, album: str, track: int | None,
               total_tracks: int, genre: str, year: str, lyrics: str, comment: str,
               pictures: list | None = None) -> None:
    ext = path.suffix.lower()
    if ext == ".flac":
        audio = FLAC(path)
        keep_pictures = pictures if pictures is not None else list(audio.pictures)
        audio.clear()
        audio["title"] = title
        audio["artist"] = artist
        audio["album"] = album
        audio["albumartist"] = artist
        if track is not None:
            audio["tracknumber"] = str(track)
            audio["tracktotal"] = str(total_tracks)
        if genre:
            audio["genre"] = genre
        if year:
            audio["date"] = year
            audio["year"] = year
        audio["comment"] = comment
        if lyrics:
            audio["lyrics"] = lyrics
        if keep_pictures:
            audio.clear_pictures()
            for pic in keep_pictures:
                audio.add_picture(pic)
        audio.save()
        return

    if ext == ".mp3":
        try:
            tags = ID3(path)
        except Exception:
            tags = ID3()
        tags.delall("TIT2"); tags.delall("TPE1"); tags.delall("TALB"); tags.delall("TPE2")
        tags.delall("TRCK"); tags.delall("TCON"); tags.delall("COMM"); tags.delall("USLT")
        tags.delall("TDRC"); tags.delall("TYER")
        tags.add(TIT2(encoding=3, text=title))
        tags.add(TPE1(encoding=3, text=artist))
        tags.add(TALB(encoding=3, text=album))
        tags.add(TPE2(encoding=3, text=artist))
        if track is not None:
            tags.add(TRCK(encoding=3, text=f"{track}/{total_tracks}"))
        if genre:
            tags.add(TCON(encoding=3, text=genre))
        if year:
            tags.add(TDRC(encoding=3, text=year))
        tags.add(COMM(encoding=3, lang="eng", desc="", text=comment))
        if lyrics:
            tags.add(USLT(encoding=3, lang="eng", desc="", text=lyrics))
        tags.save(path)
        return

    if ext == ".m4a":
        audio = MP4(path)
        audio["\xa9nam"] = [title]
        audio["\xa9ART"] = [artist]
        audio["\xa9alb"] = [album]
        audio["aART"] = [artist]
        if track is not None:
            audio["trkn"] = [(track, total_tracks)]
        if genre:
            audio["\xa9gen"] = [genre]
        if year:
            audio["\xa9day"] = [year]
        elif "\xa9day" in audio:
            del audio["\xa9day"]
        audio["\xa9cmt"] = [comment]
        if lyrics:
            audio["\xa9lyr"] = [lyrics]
        audio.save()
        return

    # wav/ogg — best-effort via mutagen
    audio = MutagenFile(path, easy=True)
    if audio is not None:
        try:
            audio["title"] = title
            audio["artist"] = artist
            audio["album"] = album
            if genre:
                audio["genre"] = genre
            if year:
                audio["date"] = year
            audio.save()
        except Exception:
            pass


def find_lrc(folder: Path, artist: str, title: str) -> Path | None:
    lrcs = {p.stem.lower(): p for p in folder.glob("*.lrc")}
    key = f"{artist}_{title}".lower()
    if key in lrcs:
        return lrcs[key]
    for stem, p in lrcs.items():
        if stem == title.lower():
            return p
        if stem.endswith("_" + title.lower()) and stem.startswith(artist.lower() + "_"):
            return p
    for stem, p in lrcs.items():
        if stem.endswith("_" + title.lower()):
            return p
    return None


def load_song_ids(path: Path) -> list[dict]:
    if not path.exists():
        return []
    entries = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 4:
                entries.append(
                    {
                        "id": parts[0],
                        "date": parts[1],
                        "artist": parts[2],
                        "title": parts[3],
                        "path": parts[4] if len(parts) > 4 else "",
                    }
                )
    return entries


def spotify_headers() -> dict | None:
    path = creds_path()
    if not path:
        return None
    try:
        import requests
    except ImportError:
        return None
    creds = json.loads(path.read_text())
    token = creds.get("access_token")
    refresh = creds.get("refresh_token")
    client_id = creds.get("client_id")
    if not token:
        return None

    expires_at = creds.get("expires_at") or 0
    if expires_at and expires_at < datetime.now().timestamp() + 60 and refresh and client_id:
        r = requests.post(
            "https://accounts.spotify.com/api/token",
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            data={"grant_type": "refresh_token", "client_id": client_id, "refresh_token": refresh},
            timeout=30,
        )
        if r.status_code == 200:
            body = r.json()
            creds["access_token"] = body["access_token"]
            if body.get("refresh_token"):
                creds["refresh_token"] = body["refresh_token"]
            creds["expires_at"] = (datetime.now() + timedelta(seconds=body.get("expires_in", 3600))).timestamp()
            path.write_text(json.dumps(creds))
            token = creds["access_token"]
    return {"Authorization": f"Bearer {token}"}


def lookup_spotify_id(artist: str, title: str, headers: dict | None) -> str | None:
    if not headers:
        return None
    try:
        import requests
    except ImportError:
        return None
    q = f'track:"{title}" artist:"{artist}"'
    r = requests.get(
        "https://api.spotify.com/v1/search",
        params={"q": q, "type": "track", "limit": 5},
        headers=headers,
        timeout=30,
    )
    if r.status_code != 200:
        return None
    items = r.json().get("tracks", {}).get("items", [])
    for t in items:
        if norm(t["name"]) == norm(title) and any(norm(a["name"]) == norm(artist) for a in t["artists"]):
            return t["id"]
    return items[0]["id"] if items else None


@dataclass
class SongMeta:
    album: str = ""
    year: str = ""
    genre: str = ""
    artist: str = ""

    def complete(self) -> bool:
        return bool(self.album and self.year and self.genre)

    def fill_missing(self, other: SongMeta) -> None:
        if not self.album and other.album:
            self.album = other.album
        if not self.year and other.year:
            self.year = other.year
        if not self.genre and other.genre:
            self.genre = other.genre
        if missing_artist(self.artist) and not missing_artist(other.artist):
            self.artist = other.artist

    def copy(self) -> SongMeta:
        return SongMeta(self.album, self.year, self.genre, self.artist)


_lookup_cache: dict[tuple[str, str, bool], SongMeta] = {}
_lookup_lock = threading.Lock()


def year_from_date(value: str) -> str:
    match = re.search(r"\b((?:19|20)\d{2})\b", value or "")
    return match.group(1) if match else ""


def pretty_genre(raw: str) -> str:
    genre = (raw or "").strip()
    if genre and genre == genre.lower():
        return genre.title()
    return genre


def http_get(url: str, *, headers: dict | None = None, params: dict | None = None, timeout: int = 30):
    import requests

    last = None
    for _ in range(3):
        try:
            last = requests.get(url, headers=headers, params=params, timeout=timeout)
        except requests.RequestException:
            last = None
            time.sleep(0.4)
            continue
        if last.status_code != 429:
            return last
        try:
            wait = float(last.headers.get("Retry-After", "1"))
        except ValueError:
            wait = 1.0
        time.sleep(min(max(wait, 0.2), 5))
    return last


def _chunks(items: list[str], size: int):
    for i in range(0, len(items), size):
        yield items[i:i + size]


def fetch_spotify_track_metas(track_ids: list[str], headers: dict | None) -> dict[str, SongMeta]:
    """Album name and release year from the track, genre from the primary artist."""
    if not headers:
        return {}
    unique = list(dict.fromkeys(tid for tid in track_ids if tid))
    if not unique:
        return {}
    out: dict[str, SongMeta] = {}
    artist_for_track: dict[str, str] = {}
    try:
        for batch in _chunks(unique, 50):
            response = http_get(
                "https://api.spotify.com/v1/tracks",
                headers=headers,
                params={"ids": ",".join(batch)},
            )
            if response is None or response.status_code != 200:
                continue
            for track in response.json().get("tracks") or []:
                if not track:
                    continue
                album = track.get("album") or {}
                artists = track.get("artists") or []
                artist_id = artists[0].get("id") if artists else ""
                if artist_id:
                    artist_for_track[track["id"]] = artist_id
                artist_name = ", ".join(
                    (a.get("name") or "").strip()
                    for a in artists
                    if (a.get("name") or "").strip() and not missing_artist(a.get("name") or "")
                )
                out[track["id"]] = SongMeta(
                    album=(album.get("name") or "").strip(),
                    year=year_from_date(album.get("release_date") or ""),
                    artist=artist_name,
                )
        genre_by_artist: dict[str, str] = {}
        for batch in _chunks(list(dict.fromkeys(artist_for_track.values())), 50):
            response = http_get(
                "https://api.spotify.com/v1/artists",
                headers=headers,
                params={"ids": ",".join(batch)},
            )
            if response is None or response.status_code != 200:
                continue
            for artist in response.json().get("artists") or []:
                if not artist:
                    continue
                genres = artist.get("genres") or []
                genre_by_artist[artist["id"]] = pretty_genre(genres[0]) if genres else ""
        for track_id, artist_id in artist_for_track.items():
            if track_id in out and not out[track_id].genre:
                out[track_id].genre = genre_by_artist.get(artist_id, "")
    except Exception:
        return out
    return out


def canonical_title(value: str) -> str:
    """Drop feat. credits and parentheticals so 'Crazy in Love (feat. …)' matches 'Crazy in Love'."""
    text = value or ""
    text = re.sub(r"\s*[\(\[][^)\]]*[\)\]]", " ", text)
    text = re.sub(r"\s+(feat\.|ft\.|featuring)\s+.*$", "", text, flags=re.I)
    return norm(text)


def _match_penalty(row: dict, title_key: str, album_key: str) -> int:
    """Down-rank compilations, singles, remixes, and live cuts when a studio album is also a match."""
    penalty = 0
    album = f" {norm(str(row.get(album_key) or ''))} " if album_key else ""
    if album.strip() and any(
        hint in album
        for hint in (
            " greatest hits ",
            " best of ",
            " essentials ",
            " anthology ",
            " box set ",
            " karaoke ",
            " tribute ",
            " hits ",
            " lullaby ",
            " single ",
            " live ",
            " remix ",
        )
    ):
        penalty += 1
    raw_title = str(row.get(title_key) or "")
    if re.search(
        r"[\(\[][^)\]]*\b(remix|live|instrumental|radio edit|karaoke|film version|alternate|demo)\b",
        raw_title,
        flags=re.I,
    ):
        penalty += 1
    coll_artist = norm(str(row.get("collectionArtistName") or row.get("album_artist") or ""))
    if coll_artist in {"various artists", "various artist", "various"}:
        penalty += 1
    return penalty


def _best_public_hit(
    rows: list[dict],
    artist: str,
    title: str,
    title_key: str,
    artist_key: str,
    album_key: str = "",
) -> dict | None:
    want_title = canonical_title(title)
    want_artist = norm(artist)
    best = None
    best_score = 0
    for row in rows:
        got_title = canonical_title(str(row.get(title_key) or ""))
        got_artist = norm(str(row.get(artist_key) or ""))
        title_score = 3 if want_title and got_title == want_title else (
            2 if want_title and (want_title in got_title or got_title in want_title) else 0
        )
        if title_score < 2:
            continue
        artist_score = 0
        if want_artist and want_artist != "unknown":
            artist_score = 3 if got_artist == want_artist else (
                2 if want_artist in got_artist or got_artist in want_artist else 0
            )
            if artist_score < 2 and title_score < 3:
                continue
        score = title_score + artist_score - _match_penalty(row, title_key, album_key)
        if score > best_score:
            best_score = score
            best = row
    return best


_CONTAINER_GENRES = {"soundtrack", "compilation", "karaoke", "instrumental", "lullabies"}


def _itunes_genre(rows: list[dict], artist: str, title: str, hit: dict) -> str:
    """Use a real genre when the chosen album is only tagged Soundtrack or similar."""
    genre = pretty_genre(hit.get("primaryGenreName") or "")
    if genre.lower() not in _CONTAINER_GENRES:
        return genre
    want_title = canonical_title(title)
    want_artist = norm(artist)
    for row in rows:
        if canonical_title(str(row.get("trackName") or "")) != want_title:
            continue
        got_artist = norm(str(row.get("artistName") or ""))
        if want_artist and want_artist not in got_artist and got_artist not in want_artist:
            continue
        alt = pretty_genre(row.get("primaryGenreName") or "")
        if alt and alt.lower() not in _CONTAINER_GENRES:
            return alt
    return genre


def _keep_featured_matches(rows: list[dict], title: str, title_key: str, artist_key: str) -> list[dict]:
    """Drop title-only hits that don't share the featured names on this recording."""
    people = featured_people(title)
    want = canonical_title(title)
    if not people or not want:
        return rows
    kept = []
    for row in rows:
        raw_title = str(row.get(title_key) or "")
        raw_artist = str(row.get(artist_key) or "")
        if canonical_title(raw_title) != want:
            continue
        if any(_person_mentioned(person, f"{raw_title} {raw_artist}") for person in people):
            kept.append(row)
    return kept


def fetch_itunes_meta(artist: str, title: str, require_features: bool = False) -> SongMeta | None:
    term = f"{artist} {title}".strip()
    if not term:
        return None
    response = http_get(
        "https://itunes.apple.com/search",
        headers={"User-Agent": "OzDownloader/1.0"},
        params={"term": term, "entity": "song", "limit": 15},
        timeout=20,
    )
    if response is None or response.status_code != 200:
        return None
    results = response.json().get("results") or []
    if require_features:
        results = _keep_featured_matches(results, title, "trackName", "artistName")
    hit = _best_public_hit(
        results,
        artist,
        title,
        "trackName",
        "artistName",
        album_key="collectionName",
    )
    if not hit:
        return None
    genre = _itunes_genre(results, artist, title, hit)
    return SongMeta(
        album=(hit.get("collectionName") or "").strip(),
        year=year_from_date(hit.get("releaseDate") or ""),
        genre=genre,
        artist=(hit.get("artistName") or "").strip(),
    )


def fetch_deezer_meta(artist: str, title: str, require_features: bool = False) -> SongMeta | None:
    queries = []
    if not missing_artist(artist):
        queries.append(f'artist:"{artist}" track:"{title}"')
    queries.append(f"{artist} {title}".strip())
    hit = None
    for query in queries:
        if not query:
            continue
        response = http_get(
            "https://api.deezer.com/search",
            params={"q": query, "limit": 8},
            timeout=20,
        )
        if response is None or response.status_code != 200:
            continue
        rows = []
        for track in response.json().get("data") or []:
            album = track.get("album") or {}
            rows.append({
                "title": track.get("title") or "",
                "artist": (track.get("artist") or {}).get("name") or "",
                "album": album.get("title") or "",
                "album_id": album.get("id"),
            })
        if require_features:
            rows = _keep_featured_matches(rows, title, "title", "artist")
        hit = _best_public_hit(rows, artist, title, "title", "artist", album_key="album")
        if hit:
            break
    if not hit:
        return None
    meta = SongMeta(
        album=(hit.get("album") or "").strip(),
        artist=(hit.get("artist") or "").strip(),
    )
    album_id = hit.get("album_id")
    if not album_id:
        return meta
    album_response = http_get(f"https://api.deezer.com/album/{album_id}", timeout=20)
    if album_response is None or album_response.status_code != 200:
        return meta
    album = album_response.json()
    if album.get("error"):
        return meta
    meta.album = (album.get("title") or meta.album).strip()
    meta.year = year_from_date(album.get("release_date") or "")
    genres = (album.get("genres") or {}).get("data") or []
    for genre in genres:
        name = pretty_genre(genre.get("name") or "")
        if name and name.lower() != "all":
            meta.genre = name
            break
    return meta


def cached_public_meta(artist: str, title: str, require_features: bool = False) -> SongMeta:
    if missing_artist(artist):
        artist = ""
    key = (norm(artist), norm(title), bool(require_features))
    with _lookup_lock:
        cached = _lookup_cache.get(key)
        if cached is not None:
            return cached.copy()
    meta = SongMeta()
    try:
        itunes = fetch_itunes_meta(artist, title, require_features=require_features)
        if itunes:
            meta.fill_missing(itunes)
    except Exception:
        pass
    if not meta.complete():
        try:
            deezer = fetch_deezer_meta(artist, title, require_features=require_features)
            if deezer:
                meta.fill_missing(deezer)
        except Exception:
            pass
    primary = primary_artist(artist)
    if primary and norm(primary) != norm(artist) and not meta.genre:
        meta.fill_missing(cached_public_meta(primary, title))
    with _lookup_lock:
        _lookup_cache[key] = meta.copy()
    return meta.copy()


_embed_cache: dict[str, SongMeta] = {}
_embed_lock = threading.Lock()


def fetch_spotify_embed(track_id: str) -> SongMeta | None:
    """Artist and release year from Spotify's public embed page. No login required."""
    track_id = (track_id or "").strip()
    if not track_id:
        return None
    with _embed_lock:
        cached = _embed_cache.get(track_id)
        if cached is not None:
            return cached.copy()
    response = http_get(
        f"https://open.spotify.com/embed/track/{track_id}",
        headers={"User-Agent": "Mozilla/5.0"},
        timeout=20,
    )
    meta = SongMeta()
    if response is not None and response.status_code == 200:
        text = unescape(response.text)
        match = re.search(r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>', text)
        entity = None
        if match:
            try:
                entity = json.loads(match.group(1))["props"]["pageProps"]["state"]["data"]["entity"]
            except Exception:
                entity = None
        names: list[str] = []
        if isinstance(entity, dict):
            for artist in entity.get("artists") or []:
                name = (artist.get("name") or "").strip()
                if name and not missing_artist(name):
                    names.append(name)
            release = entity.get("releaseDate") or {}
            iso = release.get("isoString") if isinstance(release, dict) else str(release or "")
            meta.year = year_from_date(iso or "")
        if not names:
            names = [
                unescape(name).strip()
                for name in re.findall(
                    r'href="https://open\.spotify\.com/artist/[^"]*"[^>]*>([^<]+)',
                    text,
                )
                if name.strip() and not missing_artist(name)
            ]
        meta.artist = ", ".join(dict.fromkeys(names))
    with _embed_lock:
        _embed_cache[track_id] = meta.copy()
    return meta.copy()


def index_song_ids(folder: Path) -> dict:
    by_stem: dict[str, str] = {}
    by_at: dict[tuple[str, str], str] = {}
    by_title: dict[str, list[str]] = defaultdict(list)
    artist_by_stem: dict[str, str] = {}
    artist_by_title: dict[str, list[str]] = defaultdict(list)
    for entry in load_song_ids(folder / ".song_ids"):
        track_id = (entry.get("id") or "").strip()
        if not track_id:
            continue
        raw_artist = (entry.get("artist") or "").strip()
        stem = Path(entry.get("path") or "").stem.lower()
        if stem:
            by_stem[stem] = track_id
            if not missing_artist(raw_artist):
                artist_by_stem[stem] = raw_artist
        key = (norm(raw_artist), norm(entry.get("title") or ""))
        by_at[key] = track_id
        if key[1]:
            by_title[key[1]].append(track_id)
            if not missing_artist(raw_artist):
                artist_by_title[key[1]].append(raw_artist)
    return {
        "stem": by_stem,
        "at": by_at,
        "title": by_title,
        "artist_by_stem": artist_by_stem,
        "artist_by_title": artist_by_title,
    }


def archived_artist_for(item: dict, index: dict) -> str:
    stem = item["path"].stem.lower()
    name = index.get("artist_by_stem", {}).get(stem, "")
    if not missing_artist(name):
        return name
    title = norm(item.get("title") or "")
    names = [n for n in index.get("artist_by_title", {}).get(title, []) if not missing_artist(n)]
    unique = list(dict.fromkeys(names))
    if len(unique) == 1:
        return unique[0]
    return ""


def spotify_id_for(item: dict, index: dict) -> str:
    stem = item["path"].stem.lower()
    if stem in index["stem"]:
        return index["stem"][stem]
    key = (norm(item.get("artist") or ""), norm(item.get("title") or ""))
    if key in index["at"]:
        return index["at"][key]
    matches = index["title"].get(key[1], [])
    if len(matches) == 1:
        return matches[0]
    return ""


def _remember_artist(item: dict, meta: SongMeta, name: str) -> None:
    name = (name or "").strip()
    if missing_artist(name):
        return
    if missing_artist(meta.artist):
        meta.artist = name
    if missing_artist(item.get("artist")):
        item["artist"] = name


def _note_metadata_skip(item: dict, source: str, exc: Exception) -> None:
    print(
        f"  metadata skip ({source}): {item.get('artist')} - {item.get('title')}: {exc}",
        file=sys.stderr,
    )


def _fill_item_meta(item: dict, headers: dict | None) -> None:
    """Spotify first. A failed Spotify read must not skip iTunes and Deezer."""
    meta: SongMeta = item["meta"]
    track_id = item.get("spotify_id") or ""
    try:
        if headers and track_id and (not meta.album or not meta.year or missing_artist(item.get("artist"))):
            found = fetch_spotify_track_metas([track_id], headers)
            if track_id in found:
                meta.fill_missing(found[track_id])
                _remember_artist(item, meta, found[track_id].artist)
        elif headers and not track_id and not missing_artist(item.get("artist")):
            track_id = lookup_spotify_id(item.get("artist") or "", item.get("title") or "", headers) or ""
            if track_id:
                item["spotify_id"] = track_id
                found = fetch_spotify_track_metas([track_id], headers)
                if track_id in found:
                    meta.fill_missing(found[track_id])
                    _remember_artist(item, meta, found[track_id].artist)
    except Exception as exc:
        _note_metadata_skip(item, "spotify", exc)
    try:
        if track_id and (
            missing_artist(item.get("artist")) or not meta.year or not meta.album
        ):
            embed = fetch_spotify_embed(track_id)
            if embed:
                meta.fill_missing(embed)
                _remember_artist(item, meta, embed.artist)
    except Exception as exc:
        _note_metadata_skip(item, "spotify page", exc)
    if meta.complete() and not missing_artist(item.get("artist")):
        return
    try:
        # Prefer the artist Spotify stored on this track id over a long credit list.
        lookup_artist = item.get("spotify_artist") or item.get("artist") or ""
        public = cached_public_meta(
            lookup_artist,
            item.get("title") or "",
            require_features=bool(item.get("require_feature_match")),
        )
        meta.fill_missing(public)
        if item.get("require_feature_match") and not missing_artist(public.artist):
            item["artist"] = public.artist
            meta.artist = public.artist
        else:
            _remember_artist(item, meta, public.artist)
    except Exception as exc:
        _note_metadata_skip(item, "itunes", exc)


_spotify_session = None


def open_spotify_session():
    """Playback login. Used to read the artist linked to a track id."""
    global _spotify_session
    if _spotify_session is not None:
        return _spotify_session or None
    path = creds_path()
    if not path:
        _spotify_session = False
        return None
    try:
        from librespot.core import Session
        _spotify_session = Session.Builder().stored_file(str(path)).create()
    except Exception as exc:
        print(f"  spotify login skipped: {exc}", file=sys.stderr)
        _spotify_session = False
    return _spotify_session or None


def close_spotify_session() -> None:
    global _spotify_session
    session = _spotify_session if _spotify_session not in (None, False) else None
    _spotify_session = None
    if session is None:
        return
    try:
        session.close()
    except Exception:
        pass


def _spotify_web_artist_genres(session, artist_ids: list[str]) -> dict[str, str]:
    """Artist genres from Spotify's API, keyed by artist id. No title search."""
    if not artist_ids:
        return {}
    try:
        import requests
        token = session.tokens().get("user-read-email")
    except Exception as exc:
        print(f"  spotify genre token skipped: {exc}", file=sys.stderr)
        return {}
    found: dict[str, str] = {}
    for batch in _chunks(artist_ids, 50):
        for _attempt in range(4):
            try:
                response = requests.get(
                    "https://api.spotify.com/v1/artists",
                    headers={"Authorization": f"Bearer {token}"},
                    params={"ids": ",".join(batch)},
                    timeout=30,
                )
            except Exception as exc:
                print(f"  spotify genre request failed: {exc}", file=sys.stderr)
                break
            if response.status_code == 429:
                try:
                    wait = float(response.headers.get("Retry-After", "2"))
                except ValueError:
                    wait = 2.0
                time.sleep(min(max(wait, 1.0), 30.0))
                continue
            if response.status_code != 200:
                print(f"  spotify genre request HTTP {response.status_code}", file=sys.stderr)
                break
            for artist in response.json().get("artists") or []:
                if not artist:
                    continue
                genres = artist.get("genres") or []
                found[artist["id"]] = pretty_genre(genres[0]) if genres else ""
            break
    return found


def fetch_spotify_linked_genres(track_ids: list[str]) -> dict[str, tuple[str, str]]:
    """Map each Spotify track id to (genre, primary artist).

    The song is the saved track id. Genre is that track's artist on Spotify,
    so a long feature credit cannot point the lookup at a different song.
    """
    session = open_spotify_session()
    unique = list(dict.fromkeys(tid for tid in track_ids if tid))
    if session is None or not unique:
        return {}
    from librespot.metadata import ArtistId, TrackId

    try:
        tracks = session.api().get_metadata_4_multiple(
            [TrackId.from_base62(tid) for tid in unique]
        )
    except Exception as exc:
        print(f"  spotify track metadata skipped: {exc}", file=sys.stderr)
        return {}

    artist_for_track: dict[str, str] = {}
    artist_ids: list = []
    seen: set[str] = set()
    names: dict[str, str] = {}
    for tid, track in zip(unique, tracks):
        if not getattr(track, "artist", None) or not track.artist[0].gid:
            continue
        aid = ArtistId.from_hex(track.artist[0].gid.hex())
        artist_for_track[tid] = aid.id()
        name = (track.artist[0].name or "").strip()
        if name:
            names[aid.id()] = name
        if aid.id() not in seen:
            seen.add(aid.id())
            artist_ids.append(aid)

    proto_genre: dict[str, str] = {}
    try:
        artists = session.api().get_metadata_4_multiple(artist_ids)
    except Exception:
        artists = []
    for aid, artist in zip(artist_ids, artists):
        if not names.get(aid.id()):
            names[aid.id()] = (getattr(artist, "name", "") or "").strip()
        if getattr(artist, "genre", None):
            proto_genre[aid.id()] = pretty_genre(artist.genre[0])
    web_genre = _spotify_web_artist_genres(session, [aid.id() for aid in artist_ids])

    out: dict[str, tuple[str, str]] = {}
    for tid, aid in artist_for_track.items():
        out[tid] = (web_genre.get(aid) or proto_genre.get(aid) or "", names.get(aid, ""))
    return out


def attach_song_metadata(folder: Path, items: list[dict]) -> None:
    """Look up year, album, and genre for each song. Spotify track ids win; iTunes then Deezer fill gaps."""
    headers = spotify_headers()
    index = index_song_ids(folder)
    ids: list[str] = []
    for item in items:
        track_id = spotify_id_for(item, index)
        item["spotify_id"] = track_id
        item["meta"] = SongMeta()
        if missing_artist(item.get("artist")):
            archived = archived_artist_for(item, index)
            if archived:
                item["artist"] = archived
        if track_id:
            ids.append(track_id)
    by_id = fetch_spotify_track_metas(ids, headers) if ids else {}
    linked = fetch_spotify_linked_genres(ids) if ids else {}
    close_spotify_session()
    pending: list[dict] = []
    for item in items:
        found = by_id.get(item["spotify_id"])
        if found:
            item["meta"] = found.copy()
            _remember_artist(item, item["meta"], found.artist)
        genre, artist_name = linked.get(item.get("spotify_id") or "", ("", ""))
        if artist_name:
            item["spotify_artist"] = artist_name
        if genre and not item["meta"].genre:
            item["meta"].genre = genre
        if not item["meta"].complete() or missing_artist(item.get("artist")):
            pending.append(item)
    if not pending:
        return
    workers = min(6, len(pending))
    with ThreadPoolExecutor(max_workers=workers) as pool:
        list(pool.map(lambda item: _fill_item_meta(item, headers), pending))


def read_easy_tags(path: Path) -> tuple[str, str]:
    audio = MutagenFile(path, easy=True)
    if audio is None:
        return "", path.stem
    title = (audio.get("title") or [path.stem])[0]
    artist = (audio.get("artist") or [""])[0]
    return str(artist or ""), str(title or path.stem)


def read_embedded_meta(path: Path) -> SongMeta:
    audio = MutagenFile(path, easy=True)
    if audio is None:
        return SongMeta()

    def first(key: str) -> str:
        values = audio.get(key) or []
        return str(values[0]).strip() if values else ""

    return SongMeta(
        album=first("album"),
        year=year_from_date(first("date") or first("year")),
        genre=first("genre"),
    )


def update_song_ids(folder: Path, ext: str = ".flac") -> None:
    archive = folder / ".song_ids"
    entries = load_song_ids(archive)
    files = []
    for f in sorted(folder.glob(f"*{ext}")):
        artist, title = read_easy_tags(f)
        files.append({"path": f, "title": title, "artist": artist})

    by_at = {(norm(fl["artist"]), norm(fl["title"])): fl for fl in files}
    by_title: dict[str, list] = defaultdict(list)
    for fl in files:
        by_title[norm(fl["title"])].append(fl)

    used = set()
    final = []
    for e in entries:
        key = (norm(e["artist"]), norm(e["title"]))
        fl = by_at.get(key)
        if not fl:
            cands = by_title.get(norm(e["title"]), [])
            if len(cands) == 1:
                fl = cands[0]
            else:
                for c in cands:
                    if norm(e["artist"]) in norm(c["artist"]) or norm(c["artist"]) in norm(e["artist"]):
                        fl = c
                        break
        if fl and fl["path"] not in used:
            final.append(
                {
                    "id": e["id"],
                    "date": e["date"],
                    "artist": fl["artist"] or e["artist"],
                    "title": fl["title"] or e["title"],
                    "path": str(fl["path"]),
                }
            )
            used.add(fl["path"])

    orphans = [fl for fl in files if fl["path"] not in used]
    headers = spotify_headers() if orphans else None
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    for fl in orphans:
        tid = lookup_spotify_id(fl["artist"], fl["title"], headers)
        if not tid:
            print(f"  warning: no Spotify ID for {fl['artist']} - {fl['title']}")
            continue
        final.append(
            {
                "id": tid,
                "date": now,
                "artist": fl["artist"],
                "title": fl["title"],
                "path": str(fl["path"]),
            }
        )
        print(f"  song_ids +: {fl['artist']} - {fl['title']}")

    seen_ids = set()
    unique = []
    for e in final:
        if e["id"] in seen_ids:
            continue
        seen_ids.add(e["id"])
        unique.append(e)

    with open(archive, "w", encoding="utf-8") as f:
        for e in unique:
            f.write(f"{e['id']}\t{e['date']}\t{e['artist']}\t{e['title']}\t{e['path']}\n")
    print(f"  song_ids: {len(unique)} entries")


def process_folder(folder: Path, genre: str, fmt: str = "flac", retag: bool = False) -> None:
    if not folder.is_dir():
        print(f"Skip (not a directory): {folder}", file=sys.stderr)
        return

    fmt = (fmt or "flac").lower()
    if fmt not in OUTPUT_FORMATS:
        raise SystemExit(f"Unsupported --format {fmt}. Choose from: {', '.join(sorted(OUTPUT_FORMATS))}")

    album = folder.name
    ext = f".{fmt}"
    print(f"\n=== {folder} ({fmt}) ===")
    if retag:
        print("  refresh: names and tags")

    converted, failed, preserved = convert_folder(folder, fmt)
    print(f"  convert: {converted} ok, {failed} failed")

    media = sorted(folder.glob(f"*{ext}"))
    if not media:
        print(f"  no {fmt.upper()} files found")
        return

    items = []
    for f in media:
        tag_artist, tag_title = read_easy_tags(f)
        saved_artist, saved_title = preserved.get(f.stem.lower(), ("", ""))
        if missing_artist(tag_artist) and not missing_artist(saved_artist):
            tag_artist = saved_artist
        if not (tag_title or "").strip() and (saved_title or "").strip():
            tag_title = saved_title
        tag_album = ""
        try:
            easy = MutagenFile(f, easy=True)
            if easy is not None:
                tag_album = str((easy.get("album") or [""])[0] or "")
        except Exception:
            tag_album = ""
        track, artist, title, require_features = decide_metadata(
            f.stem, tag_artist, tag_title, tag_album
        )
        already_clean = track is None and "_" not in f.stem and not (
            tag_title and tag_artist and tag_title.lower().startswith(tag_artist.lower() + "_")
        )
        items.append(
            {
                "path": f,
                "track": track,
                "artist": artist,
                "title": title or clean_title(f.stem),
                "already_clean": already_clean,
                "require_feature_match": require_features,
            }
        )

    if not retag:
        seen_hash = {}
        unique_items = []
        for item in sorted(items, key=lambda x: (x["track"] is None, x["track"] or 999, x["path"].name)):
            h = file_md5(item["path"])
            key = (norm(item["artist"]), norm(item["title"]), h)
            if key in seen_hash:
                print(f"  removed identical: {item['path'].name}")
                item["path"].unlink()
                continue
            seen_hash[key] = item
            unique_items.append(item)
        items = unique_items

    tracks = [x["track"] for x in items if x["track"] is not None]
    total_tracks = max(tracks) if tracks else len(items)

    title_counts = Counter(i["title"] for i in items)
    lyrics_embedded = renamed = art_embedded = 0
    art_headers = spotify_headers()

    print(
        "  metadata: refreshing artist, album, year, and genre…"
        if retag
        else "  metadata: fetching artist, year, album, and genre…"
    )
    attach_song_metadata(folder, items)
    tagged = len(items)
    print(
        "  metadata: "
        f"artist {sum(1 for item in items if not missing_artist(item.get('artist')))}/{tagged}, "
        f"year {sum(1 for item in items if item['meta'].year)}/{tagged}, "
        f"album {sum(1 for item in items if item['meta'].album)}/{tagged}, "
        f"genre {sum(1 for item in items if item['meta'].genre)}/{tagged}"
    )

    planned_names = {}
    for item in sorted(items, key=lambda x: (x["track"] is None, x["track"] or 999, x["path"].name)):
        artist = clean_artist(item["artist"])
        title = clean_title(item["title"])
        item["artist"] = artist
        item["title"] = title

        # Song title first (e.g. "Big Poppa - 2005 Remaster.flac").
        base = sanitize_filename(title)
        if title_counts.get(title, 0) > 1 and artist and artist.lower() != "unknown":
            base = sanitize_filename(f"{title} - {artist}")
        name = base + ext
        if name in planned_names:
            name = sanitize_filename(f"{title} - {item['artist']}") + ext
            n = 2
            while name in planned_names:
                name = sanitize_filename(f"{title} - {item['artist']} ({n})") + ext
                n += 1
        planned_names[name] = True
        item["new_name"] = name

    total_items = len(items)
    for index, item in enumerate(items, start=1):
        if retag and (index == 1 or index == total_items or index % 10 == 0):
            print(f"  tagging: {int(index * 100 / total_items)}%")
        src: Path = item["path"]
        lrc = find_lrc(folder, item["artist"], item["title"])
        lyrics = lrc.read_text(encoding="utf-8", errors="replace").strip() if lrc else ""

        if not lyrics and item.get("already_clean"):
            try:
                easy = MutagenFile(src, easy=True)
                if easy is not None:
                    lyrics = (easy.get("lyrics") or [""])[0]
            except Exception:
                lyrics = ""

        pictures = read_pictures(src)
        meta: SongMeta = item.get("meta") or SongMeta()
        _remember_artist(item, meta, meta.artist)
        embedded = read_embedded_meta(src)
        album_name = meta.album or embedded.album or album
        year = meta.year or embedded.year
        song_genre = meta.genre or embedded.genre or genre
        write_tags(
            src,
            title=item["title"],
            artist=item["artist"],
            album=album_name,
            track=item["track"],
            total_tracks=total_tracks,
            genre=song_genre,
            year=year,
            lyrics=lyrics,
            comment=f"Source: {album}",
            pictures=pictures,
        )
        if not pictures and ext == ".flac" and not retag:
            pic = None
            if art_headers:
                tid = lookup_spotify_id(item["artist"], item["title"], art_headers)
                if tid:
                    pic = fetch_track_art(tid, art_headers)
            if pic is None:
                pic = fetch_cover_fallback(item["artist"], item["title"])
            if pic:
                audio = FLAC(src)
                audio.clear_pictures()
                audio.add_picture(pic)
                audio.save()
                pictures = [pic]
                art_embedded += 1
        if lyrics:
            lyrics_embedded += 1

        dst = folder / item["new_name"]
        if src.resolve() != dst.resolve():
            if retag and dst.exists() and dst.resolve() != src.resolve():
                print(f"  kept both: {src.name}")
                continue
            if dst.exists() and dst.resolve() != src.resolve():
                try:
                    if src.stat().st_size <= dst.stat().st_size:
                        print(f"  removed duplicate: {src.name} (kept {dst.name})")
                        src.unlink()
                        continue
                    print(f"  replaced smaller: {dst.name} -> {src.name}")
                    dst.unlink()
                except OSError as exc:
                    raise SystemExit(f"Target exists: {dst} (from {src}): {exc}") from exc
            src.rename(dst)
            renamed += 1

    for lrc in folder.glob("*.lrc"):
        lrc.unlink()

    removed_smaller = 0
    if not retag:
        groups = defaultdict(list)
        for f in folder.glob(f"*{ext}"):
            artist, title = read_easy_tags(f)
            key = (norm(artist), norm(title))
            groups[key].append(f)

        for key, paths in groups.items():
            if len(paths) < 2:
                continue
            paths = sorted(paths, key=lambda p: p.stat().st_size, reverse=True)
            keep, *delete = paths
            for p in delete:
                print(f"  removed smaller dup: {p.name}")
                p.unlink()
                removed_smaller += 1
            clean = re.sub(r" \(\d+\)$", "", keep.stem)
            target = folder / f"{sanitize_filename(clean)}{ext}"
            if keep.name != target.name and not target.exists():
                keep.rename(target)

    print(f"  renamed: {renamed}")
    print(f"  lyrics embedded: {lyrics_embedded}")
    print(f"  artwork embedded: {art_embedded}")
    print(f"  smaller dups removed: {removed_smaller}")
    print(f"  total {fmt.upper()}: {len(list(folder.glob(f'*{ext}')))}")

    update_song_ids(folder, ext=ext)


def find_download_folders(root: Path) -> list[Path]:
    folders = []
    for p in sorted(root.rglob("*")):
        if not p.is_dir():
            continue
        if (
            any(p.glob("*.ogg"))
            or any(p.glob("*.flac"))
            or any(p.glob("*.mp3"))
            or any(p.glob("*.m4a"))
            or any(p.glob("*.lrc"))
            or (p / ".song_ids").exists()
        ):
            folders.append(p)
    return folders


def main():
    parser = argparse.ArgumentParser(description="Post-process Zotify downloads (convert, rename, tag)")
    parser.add_argument("paths", nargs="*", help="Folder(s) to process")
    parser.add_argument("--all", action="store_true", help="Process all download folders under Zotify Music")
    parser.add_argument(
        "--root",
        default=str(Path.home() / "Music/Zotify Music"),
        help="Root used with --all (default: ~/Music/Zotify Music)",
    )
    parser.add_argument(
        "--genre",
        default="",
        help="Fallback genre when a song's genre cannot be looked up (e.g. \"R&B\")",
    )
    parser.add_argument(
        "--format",
        default="flac",
        dest="fmt",
        choices=sorted(OUTPUT_FORMATS),
        help="Output audio format (default: flac)",
    )
    parser.add_argument(
        "--retag",
        action="store_true",
        help="Refresh artist, album, year, and genre on songs already saved",
    )
    args = parser.parse_args()

    folders: list[Path] = []
    if args.all:
        folders = find_download_folders(Path(args.root).expanduser())
    elif args.paths:
        folders = [Path(p).expanduser().resolve() for p in args.paths]
    else:
        parser.print_help()
        print('\nExample:\n  zotify-postprocess "~/Music/Zotify Music/Dj RnB" --genre "R&B" --format flac')
        sys.exit(1)

    if not folders:
        print("No folders to process.")
        sys.exit(1)

    for folder in folders:
        process_folder(folder, args.genre, fmt=args.fmt, retag=args.retag)

    print("\nDone.")


if __name__ == "__main__":
    main()
