#!/usr/bin/env python3
"""Post-process Zotify downloads.

For each given folder:
  1. Convert audio (.ogg/.mp3/.m4a/...) to FLAC
  2. Rename to song-title-only filenames
  3. Embed title/artist/album/track/lyrics into FLAC tags
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
import subprocess
import sys
from collections import Counter, defaultdict
from datetime import datetime, timedelta
from pathlib import Path

from mutagen import File as MutagenFile
from mutagen.flac import FLAC, Picture
from mutagen.id3 import APIC, ID3, TIT2, TPE1, TALB, TPE2, TRCK, TCON, COMM, USLT
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
    name = name.strip().rstrip(".")
    for ch in ':/\\?*|"<>':
        name = name.replace(ch, "_")
    return name


def norm(s: str) -> str:
    return "".join(c.lower() for c in (s or "") if c.isalnum() or c.isspace()).strip()


def clean_title(title: str) -> str:
    t = (title or "").strip()
    while t.startswith("_"):
        t = t[1:].strip()
    return t or title or "Unknown"


def clean_artist(artist: str) -> str:
    a = (artist or "").strip()
    if a in ("_", "-", "Unknown"):
        return ""
    return a


def resolve_metadata(stem: str, tag_artist: str, tag_title: str) -> tuple[int | None, str, str]:
    """Prefer parsed filename parts over zotify tags that echo Artist_Title stems."""
    track, parsed_artist, parsed_title = parse_name(stem)
    parsed_artist = clean_artist(parsed_artist or "")
    parsed_title = clean_title(parsed_title or "")
    tag_artist = clean_artist(tag_artist or "")
    tag_title = clean_title(tag_title or "")

    artist = parsed_artist or tag_artist or "Unknown"
    title = parsed_title or tag_title or clean_title(stem)

    if parsed_artist and parsed_title:
        bad = f"{parsed_artist}_{parsed_title}"
        if tag_title == bad or tag_title.lower().startswith(parsed_artist.lower() + "_"):
            title = parsed_title
            artist = parsed_artist
    elif tag_title and "_" in tag_title:
        _, pa, pt = parse_name(tag_title)
        if pt:
            title = clean_title(pt)
            artist = clean_artist(pa or tag_artist) or tag_artist or "Unknown"

    if tag_artist.endswith(" - From"):
        title = clean_title(parsed_title or tag_title.replace("_", " ").strip()) or title
        artist = clean_artist(tag_artist[:-6].strip()) or artist

    return track, artist, title


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


def parse_name(stem: str):
    stem = (stem or "").strip()
    # Playlist: 01_Artist_Title
    m = re.match(r"^(\d{2})_(.+?)_(.+)$", stem)
    if m:
        return int(m.group(1)), m.group(2), m.group(3)
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


def convert_folder(folder: Path, fmt: str) -> tuple[int, int]:
    """Convert non-target audio files in folder to fmt."""
    fmt = fmt.lower()
    if fmt not in OUTPUT_FORMATS:
        raise ValueError(f"Unsupported format: {fmt}")
    target_ext = f".{fmt}"
    converted = failed = 0
    for f in sorted(folder.iterdir()):
        if f.suffix.lower() not in AUDIO_EXTS:
            continue
        if f.suffix.lower() == target_ext:
            continue
        out = f.with_suffix(target_ext)
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
    return converted, failed


def write_tags(path: Path, *, title: str, artist: str, album: str, track: int | None,
               total_tracks: int, genre: str, lyrics: str, comment: str,
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
        tags.add(TIT2(encoding=3, text=title))
        tags.add(TPE1(encoding=3, text=artist))
        tags.add(TALB(encoding=3, text=album))
        tags.add(TPE2(encoding=3, text=artist))
        if track is not None:
            tags.add(TRCK(encoding=3, text=f"{track}/{total_tracks}"))
        if genre:
            tags.add(TCON(encoding=3, text=genre))
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


def read_easy_tags(path: Path) -> tuple[str, str]:
    audio = MutagenFile(path, easy=True)
    if audio is None:
        return "", path.stem
    title = (audio.get("title") or [path.stem])[0]
    artist = (audio.get("artist") or [""])[0]
    return str(artist or ""), str(title or path.stem)


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


def process_folder(folder: Path, genre: str, fmt: str = "flac") -> None:
    if not folder.is_dir():
        print(f"Skip (not a directory): {folder}", file=sys.stderr)
        return

    fmt = (fmt or "flac").lower()
    if fmt not in OUTPUT_FORMATS:
        raise SystemExit(f"Unsupported --format {fmt}. Choose from: {', '.join(sorted(OUTPUT_FORMATS))}")

    album = folder.name
    ext = f".{fmt}"
    print(f"\n=== {folder} ({fmt}) ===")

    converted, failed = convert_folder(folder, fmt)
    print(f"  convert: {converted} ok, {failed} failed")

    media = sorted(folder.glob(f"*{ext}"))
    if not media:
        print(f"  no {fmt.upper()} files found")
        return

    items = []
    for f in media:
        tag_artist, tag_title = read_easy_tags(f)
        track, artist, title = resolve_metadata(f.stem, tag_artist, tag_title)
        already_clean = track is None and "_" not in f.stem and not (
            tag_title and tag_artist and tag_title.lower().startswith(tag_artist.lower() + "_")
        )
        items.append(
            {
                "path": f,
                "track": track,
                "artist": artist or "Unknown",
                "title": title or clean_title(f.stem),
                "already_clean": already_clean,
            }
        )

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

    planned_names = {}
    for item in sorted(items, key=lambda x: (x["track"] is None, x["track"] or 999, x["path"].name)):
        artist = clean_artist(item["artist"])
        title = clean_title(item["title"])
        item["artist"] = artist or item["artist"]
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

    for item in items:
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
        write_tags(
            src,
            title=item["title"],
            artist=item["artist"],
            album=album,
            track=item["track"],
            total_tracks=total_tracks,
            genre=genre,
            lyrics=lyrics,
            comment=f"Source: {album}",
            pictures=pictures,
        )
        if not pictures and ext == ".flac":
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

    groups = defaultdict(list)
    for f in folder.glob(f"*{ext}"):
        artist, title = read_easy_tags(f)
        key = (norm(artist), norm(title))
        groups[key].append(f)

    removed_smaller = 0
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
    parser.add_argument("--genre", default="", help='Genre tag to embed (e.g. "R&B", "Afrobeats")')
    parser.add_argument(
        "--format",
        default="flac",
        dest="fmt",
        choices=sorted(OUTPUT_FORMATS),
        help="Output audio format (default: flac)",
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
        process_folder(folder, args.genre, fmt=args.fmt)

    print("\nDone.")


if __name__ == "__main__":
    main()
