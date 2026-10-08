# Song tags

Decisions for convert and refetch, 2026-10-08.

Both buttons run `scripts/zotify-postprocess.py` on a playlist folder. Convert omits `--retag`. Refetch passes `--retag`. Neither button writes tags itself.

## Terms

- **Song title**: the recording name. A feature credit may sit inside it, as in `What's Luv (feat. Ja-Rule & Ashanti)`.
- **Feature credit**: text that is only `feat.`, `ft.`, or `featuring` plus names. It is not a song title and not an artist.
- **Track index**: a playlist number such as `66`. It is not a song title.
- **Primary artist**: the first credited name, before a comma, `&`, or a feature credit.
- **Lookup**: iTunes, then Deezer, after Spotify. A failed Spotify page read must not skip the lookup.

## Rules

- A feature credit stored as the title, with the song name stored as the artist, is rebuilt into the song title. The artist is filled only by a lookup that mentions those featured names.
- A normal title that already contains a feature credit, with a real artist, is left as it is.
- A filename or title that is only a track index is not the song title when the song name is in the artist field or in the album before a trailing `/number`.
- A real numeric title with an artist that is not inside that album prefix stays as it is (`7` by Drake on `Scorpion`).
- Spotify having no genre does not block iTunes. An empty result stays empty.

## Seam

`decide_metadata(stem, tag_artist, tag_title, tag_album)` returns the track index, artist, title, and whether the lookup must match featured names. Convert and refetch both call it before writing tags. Tests call this function only. They do not call iTunes.
