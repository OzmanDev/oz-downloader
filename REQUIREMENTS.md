# Library check should explain itself

## Problem statement

On Get Music, a playlist that is already mostly on this Mac spends a long time checking the library before the remaining songs start. During that wait the screen shows a spinner, “Checking library…”, a count such as “62 of 64 on disk”, and “62 skipped - 2 left”. The songs still to come sit under Waiting with the word “Waiting” repeated. In progress says “None yet”. Nothing tells the person that the app is comparing files, or which songs that wait is for. It looks stuck.

## Goals

While the library check is running, a person can tell what the app is doing, how many songs are already here, how many are left, and which songs those are. When a remaining song actually starts, the screen shows that song in progress.

## Non-goals

- Making the library check faster.
- Changing which songs are skipped or downloaded.
- Redesigning Get Music, the four columns, or other steps (sign-in, convert, tag refresh).
- The Windows app.
- A new setting to hide this explanation.

## Target users

Someone downloading a playlist they already partly have, on the Mac app’s Get Music screen.

## Business requirements

1. During the library check, the screen says in plain language that the app is checking which songs are already on this Mac. A spinner and “Checking library…” are not enough on their own.
2. That explanation includes how many songs are already here and how many are still left.
3. The songs still left are named, so the wait is clearly for those tracks.
4. A song that has not started does not show a bare “Waiting”. Its status says the library check is still going, or that the song is next when the check finishes.
5. In progress does not say “None yet” during the check in a way that looks idle. The song being checked appears there, or the empty state says downloading starts after the check.
6. Songs already on disk stay listed as already here. They are not shown as downloading.
7. When a remaining song starts downloading, that song shows as in progress and the library-check explanation goes away.
8. Cancel still works during this step.

## Priority

High. This is the step people sit on after choosing a saved playlist, and today it reads as a stall.

## Known constraints

- The Mac app already shows the four progress columns, the playlist row, and the top-right status. The explanation has to fit that screen.
- The check can run for a long time on a large playlist that is mostly already saved.
- Download behavior from the saved-playlist fix stays as it is: leftover songs are still downloaded, and the playlist is not Done while any song is still waiting.

## Assumptions

- The moment in the DJ Pop screenshot is the one to fix: 62 songs already here, 2 not started, In progress empty, spinner running.
- One short explanation on the progress card is enough. No second screen or tutorial.
