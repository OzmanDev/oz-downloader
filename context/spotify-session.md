# Spotify session

## 2026-10-09 — What “Spotify session error” is

The line “Spotify session error — retrying…” is zotify’s `LOGIN FAILED` from a `ConnectionError` while opening a librespot session. It is not a wrong password. The usual message is that Spotify’s access point did not answer the handshake.

Each download starts a new zotify process, and that process logs in again. Zotify already tries login twice (`RETRY_ATTEMPTS` default 1). The app then starts another process, and the outer loop can do that up to 5 times. Those back-to-back logins are what the screen is retrying.

Do not open a session when the track list is known and every song is already on disk. That case was Dj Afro: 105 songs already in the folder, and the installer build still logged in and showed the error. The Applications build stops before that login.

Opening another session is useful. A failed try is one access point that accepted TCP and then sent no handshake reply. The next try asks apresolve again and usually gets an access point that answers. Do not replace that with a single sign-in.

## 2026-10-09 — Why the handshake gets no reply

Checked from this Mac with the bundled librespot 0.0.14 client (build version 117300517, 154-byte ClientHello). apresolve returned 6 access points, on ports 4070, 443, and 80. All 6 answered the handshake in under 1.1 seconds. The account and the client version are not being refused.

Login picks one of those addresses at random and speaks raw TCP, not HTTP. It then waits 20 seconds for the first 4 bytes of the reply. “Did not answer the handshake” means those bytes never came, or the socket reset and the app rewrote that error into the same sentence.

There is no VPN in use. The silent attempt is an access point from Spotify’s own list that completes TCP and then sends no handshake reply. librespot added a handshake timeout for this. Another session resolves the list again and usually lands on one that replies. Port 4070 is on that same list, next to 443 and 80.

`ConnectionHolder.flush` sends the whole ClientHello. `read_int` and the reply body use an exact read. Login tries port 443, then 80, then the rest. A socket failure moves to the next address. A signature failure does not. The ClientHello bytes are unchanged.
