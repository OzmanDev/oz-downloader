# Playlist debug log

## 2026-10-10 — One small log per playlist

Mac only. After each playlist download finishes, overwrite `debug.log` inside that playlist’s folder. An empty playlist name does not write a file. The app does not upload, email, or attach the file.

The file is the minimum needed to investigate:

```
v2.3.0
downloaded 18
skipped 4
failed 1
3 skipped Already here
19 failed No audio stream
```

Counts come first. Only songs that were not downloaded are listed, as `number outcome detail`. Detail is one of: Already here, Downloaded previously, Already downloaded, Filtered, Duplicate, Cancelled, Unavailable, Local file, No audio stream, Failed, Skipped. Any other detail is omitted. No song titles, file paths, account names, email, tokens, cookies, or links.

The app version is 2.3.0. The log’s first line is that version. What’s new keeps the existing four notes and adds:

Each playlist saves a small debug log. It keeps only the minimum needed to investigate, leaves private data out, and is never shared unless you choose to send it.
