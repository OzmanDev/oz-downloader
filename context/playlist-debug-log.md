# Playlist debug log

## 2026-10-10 — One small log per playlist

Mac only. After each playlist download finishes, overwrite `debug.log` inside that playlist’s folder. An empty playlist name does not write a file. The app does not upload, email, or attach the file.

The file is the minimum needed to investigate:

```
v2.1.2
downloaded 18
skipped 4
failed 1
3 skipped Already here
19 failed No audio stream
```

Counts come first. Only songs that were not downloaded are listed, as `number outcome detail`. Detail is one of: Already here, Downloaded previously, Already downloaded, Filtered, Duplicate, Cancelled, Unavailable, Local file, No audio stream, Failed, Skipped. Any other detail is omitted. No song titles, file paths, account names, email, tokens, cookies, or links.

Version is 2.1.2 so What’s new shows again. Keep the existing four notes and add:

Each playlist saves a small debug log. It keeps only the minimum needed to investigate, leaves private data out, and is never shared unless you choose to send it.
