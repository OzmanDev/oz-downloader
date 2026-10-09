# Library check

## 2026-10-09 — Explain the wait

DJ Pop, 64 songs, 62 already on disk. Get Music showed “Checking library…”, a spinner, “62 of 64 on disk”, and “62 skipped - 2 left”. ROMANA and TaTaTa sat under Waiting. In progress said “None yet”. The check takes long enough that this reads as a stall.

Business requirements are in `REQUIREMENTS.md`. Not approved yet. No UI change until they are approved. Out of scope: speeding the check up, changing skip/download behavior, Windows, and a redesign of the other steps.

## 2026-10-09 — All skipped, then a session retry

Dj Afro’s saved count was 92. The folder already had 105 song ids and 115 audio files. Progress showed about 95 skipped and nothing waiting, then a few Waiting rows when Spotify’s longer list arrived, then all 105 skipped. The song order also changed, from the saved archive order to Spotify’s order. A Spotify session error kept the status on “Retrying” after every row was already here, because a retry is not allowed to finish the library check.

Once the track list is known and every row is already on disk, the download stops instead of launching another attempt. New rows from Spotify are matched to disk before they are shown as Waiting. The playlist’s song count updates to the longer list.
