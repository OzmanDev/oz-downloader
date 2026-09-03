#!/usr/bin/env python3
"""Patch zotify duplicate detection:
1) Treat any matching audio stem (flac/ogg/…) as already present.
2) Skip on path_exists even when directory archives are enabled.
"""

from __future__ import annotations

import sys
from pathlib import Path

IMPORT_OLD = "import music_tag\nimport requests"
IMPORT_NEW = "import music_tag\nimport re\nimport requests"
IMPORT_ALREADY = "import re\nimport requests"

STEM_OLD = '''        path = self.output_path(parent_stack)
        path_exists = Path(path).is_file() and Path(path).stat().st_size
        if isinstance(self, Episode) and path.suffix == ".copy":'''

STEM_NEW = '''        path = self.output_path(parent_stack)
        path_exists = Path(path).is_file() and Path(path).stat().st_size
        if not path_exists:
            parent = Path(path.parent)
            stems = [path.stem]
            m = re.match(r'^\\d+_(.+)$', path.stem)
            if m:
                stems.append(m.group(1))
            if '_' in path.stem:
                parts = path.stem.split('_', 1)
                if len(parts) == 2 and parts[1]:
                    stems.append(parts[1])
            for stem in stems:
                for file_match in parent.glob(stem + ".*"):
                    if file_match.is_file() and file_match.stat().st_size:
                        path_exists = True
                        break
                if path_exists:
                    break
        if isinstance(self, Episode) and path.suffix == ".copy":'''

COND_OLD = (
    "if path_exists and Zotify.CONFIG.get_skip_existing() "
    "and Zotify.CONFIG.get_no_dir_archives():"
)
COND_NEW = "if path_exists and Zotify.CONFIG.get_skip_existing():"

STEM_MARKER = "for file_match in parent.glob(stem + \".*\"):"


def find_api_files() -> list[Path]:
    files: list[Path] = []
    try:
        import zotify

        pkg = Path(zotify.__file__).resolve().parent
        cand = pkg / "api.py"
        if cand.exists():
            files.append(cand)
    except Exception:
        pass

    for base in [Path(sys.prefix) / "lib", Path.home() / ".local/lib"]:
        if not base.exists():
            continue
        for cand in base.rglob("zotify/api.py"):
            if cand not in files:
                files.append(cand)
    return files


def patch_file(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    changed = False

    if STEM_MARKER not in text:
        if STEM_OLD not in text:
            return "unexpected-content"
        text = text.replace(STEM_OLD, STEM_NEW)
        changed = True
        if IMPORT_ALREADY not in text:
            if IMPORT_OLD in text:
                text = text.replace(IMPORT_OLD, IMPORT_NEW)
            elif "import re\n" not in text:
                return "missing-import-anchor"

    if COND_OLD in text:
        text = text.replace(COND_OLD, COND_NEW)
        changed = True
    elif COND_NEW not in text:
        return "unexpected-skip-condition"

    if not changed:
        return "already-patched"

    path.write_text(text, encoding="utf-8")
    return "patched"


def main() -> int:
    files = find_api_files()
    if not files:
        print("WARNING: could not find zotify/api.py to patch", file=sys.stderr)
        return 1

    status = 0
    for path in files:
        result = patch_file(path)
        print(f"{result}: {path}")
        if result in {"unexpected-content", "missing-import-anchor", "unexpected-skip-condition"}:
            status = 1
    return status


if __name__ == "__main__":
    raise SystemExit(main())
