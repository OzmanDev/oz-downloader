"""Which Spotify access point to try, and which handshake failures may move on."""

from __future__ import annotations


def order_access_points(urls: list[str]) -> list[str]:
    """Keep every address. Port 443, then 80, then the rest, stable within a group."""

    def port_rank(url: str) -> int:
        port = url.rpartition(":")[2]
        if port == "443":
            return 0
        if port == "80":
            return 1
        return 2

    return sorted(urls, key=port_rank)


def is_retryable_handshake_error(error: BaseException) -> bool:
    """True when the socket failed before Spotify answered the handshake.

    ConnectionError, TimeoutError, and OSError (reset, timeout, broken pipe)
    are retryable. A handshake Spotify already answered is not.
    """
    return isinstance(error, OSError)
