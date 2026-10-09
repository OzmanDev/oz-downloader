# Progress columns

## 2026-10-09 — Failed column and exact skip/fail labels

A song that Spotify does not send is a Failed row. It is not Skipped and its label is not Already here.

zotify lines and the label the row must show:

| Line contains | Column | Label |
|---|---|---|
| FAILED TO GET CONTENT STREAM | Failed | No audio stream |
| IS UNAVAILABLE | Failed | Unavailable |
| IS A LOCAL FILE | Failed | Local file |
| FILE ALREADY EXISTS | Skipped | Already here |
| DOWNLOADED PREVIOUSLY | Skipped | Downloaded previously |
| ALREADY DOWNLOADED THIS SESSION | Skipped | Already downloaded |
| MATCHES REGEX FILTER | Skipped | Filtered |

A line that only says SKIPPING, including a lyrics skip, does not move the row. Failed to get the content stream is checked before any skip, because that error line also contains SKIPPING TRACK. When the line quotes a song name, that song moves. A missing audio stream has no song name, so the row in progress moves.

Progress details columns, in order: Waiting, In progress, Skipped, Failed, Downloaded. A failed song is only in Failed. The summary counts a failed song as failed, not as skipped and not as left. With no failures the summary stays `N skipped · N left`. With failures it is `N skipped · N failed · N left`.

Duplicate stays Duplicate. Cancelled stays Cancelled. A real file on disk can still be Already here.

Do not special-case a song, playlist, or account. Do not change Spotify login, the handshake timeout, or the unapproved library-check screen.
