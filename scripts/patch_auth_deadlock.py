#!/usr/bin/env python3
"""Stop librespot from deadlocking while saving credentials during login.

Session.authenticate keeps __auth_lock_bool set until __authenticate_partial
returns. With store_credentials enabled, that method calls credentials(),
which waits on the same lock. The packet receiver is also waiting to send
a pong, so both threads block and Spotify sign-in never finishes.

A silent access point must not fail that login while another address in the
same list would answer. ClientHello construction is left unchanged.
"""

from __future__ import annotations

import sys
from pathlib import Path

OLD = '''    def ap_welcome(self):
        """ """
        self.__wait_auth_lock()
        if self.__ap_welcome is None:
            raise RuntimeError("Session isn't authenticated!")
        return self.__ap_welcome
'''

NEW = '''    def ap_welcome(self):
        """ """
        # Already parsed during login. Waiting on the auth lock here deadlocks
        # credential saving against the receiver thread that must be released
        # by the same login.
        if self.__ap_welcome is None:
            self.__wait_auth_lock()
        if self.__ap_welcome is None:
            raise RuntimeError("Session isn't authenticated!")
        return self.__ap_welcome
'''

ALREADY = "Already parsed during login."

HANDSHAKE_OLD = '''        # Read APResponseMessage
        try:
            ap_response_message_length = self.connection.read_int()
        except struct.error:
            time.sleep(1)
            ap_response_message_length = self.connection.read_int()
'''

HANDSHAKE_NEW = '''        # Read APResponseMessage. A silent access point used to block forever,
        # which left downloads on "retrying" while the login spinner kept running.
        self.connection.set_timeout(20)
        try:
            try:
                ap_response_message_length = self.connection.read_int()
            except struct.error:
                time.sleep(1)
                ap_response_message_length = self.connection.read_int()
        except (socket.timeout, TimeoutError, OSError) as ex:
            raise ConnectionError(
                "Spotify access point did not answer the handshake") from ex
'''

HANDSHAKE_ALREADY = "Spotify access point did not answer the handshake"

CREATE_OLD = '''            session.connect()
            session.authenticate(self.login_credentials)
            return session
'''

CREATE_NEW = '''            try:
                session.connect()
                session.authenticate(self.login_credentials)
            except Exception:
                try:
                    session.close()
                except Exception:
                    pass
                raise
            return session
'''

CREATE_ALREADY = "session.close()"

# Same port order as scripts/spotify_access.order_access_points, inlined because
# librespot cannot import that script.
ORDERED_ALREADY = "def ordered_accesspoints("
ORDERED_OLD = '''        return ApResolver.get_random_of("accesspoint")


class DealerClient(Closeable):'''
ORDERED_NEW = '''        return ApResolver.get_random_of("accesspoint")

    @staticmethod
    def ordered_accesspoints() -> list[str]:
        """Ports 443, then 80, then every other address. Empty if resolve fails."""
        try:
            pool = ApResolver.request("accesspoint")
            urls = pool.get("accesspoint")
            if not urls:
                return []

            def port_rank(url: str) -> int:
                port = url.rpartition(":")[2]
                if port == "443":
                    return 0
                if port == "80":
                    return 1
                return 2

            return sorted(urls, key=port_rank)
        except Exception:
            return []


class DealerClient(Closeable):'''

CREATE_MULTI_ALREADY = """                except OSError as ex:
                    last_error = ex
                    continue"""
CREATE_CURRENT = '''        def create(self) -> Session:
            """Create the Session instance


            :returns: Session instance

            """
            if self.login_credentials is None:
                raise RuntimeError("You must select an authentication method.")
            session = Session(
                Session.Inner(
                    self.device_type,
                    self.device_name,
                    self.preferred_locale,
                    self.conf,
                    self.device_id,
                ),
                ApResolver.get_random_accesspoint(),
            )
            try:
                session.connect()
                session.authenticate(self.login_credentials)
            except Exception:
                try:
                    session.close()
                except Exception:
                    pass
                raise
            return session
'''
CREATE_LOOP_OLD = '''        def create(self) -> Session:
            """Create the Session instance


            :returns: Session instance

            """
            if self.login_credentials is None:
                raise RuntimeError("You must select an authentication method.")
            addresses = ApResolver.ordered_accesspoints()
            if not addresses:
                addresses = [ApResolver.get_random_accesspoint()]
            last_error = None
            for address in addresses:
                session = Session(
                    Session.Inner(
                        self.device_type,
                        self.device_name,
                        self.preferred_locale,
                        self.conf,
                        self.device_id,
                    ),
                    address,
                )
                try:
                    session.connect()
                    session.authenticate(self.login_credentials)
                    return session
                except OSError as ex:
                    last_error = ex
                    try:
                        session.close()
                    except Exception:
                        pass
                except Exception:
                    try:
                        session.close()
                    except Exception:
                        pass
                    raise
            if last_error is None:
                raise RuntimeError("No Spotify access point available")
            raise last_error
'''
CREATE_MULTI = '''        def create(self) -> Session:
            """Create the Session instance


            :returns: Session instance

            """
            if self.login_credentials is None:
                raise RuntimeError("You must select an authentication method.")
            addresses = ApResolver.ordered_accesspoints()
            if not addresses:
                addresses = [ApResolver.get_random_accesspoint()]
            last_error = None
            for address in addresses:
                try:
                    session = Session(
                        Session.Inner(
                            self.device_type,
                            self.device_name,
                            self.preferred_locale,
                            self.conf,
                            self.device_id,
                        ),
                        address,
                    )
                except OSError as ex:
                    last_error = ex
                    continue
                try:
                    session.connect()
                    session.authenticate(self.login_credentials)
                    return session
                except OSError as ex:
                    last_error = ex
                    try:
                        session.close()
                    except Exception:
                        pass
                except Exception:
                    try:
                        session.close()
                    except Exception:
                        pass
                    raise
            if last_error is None:
                raise RuntimeError("No Spotify access point available")
            raise last_error
'''

FLUSH_ALREADY = "while sent < len(pending):"
FLUSH_OLD = '''        def flush(self) -> None:
            """Flush data to socket"""
            try:
                self.__buffer.seek(0)
                self.__socket.send(self.__buffer.read())
                self.__buffer = io.BytesIO()
            except BrokenPipeError:
                pass
'''
FLUSH_NEW = '''        def flush(self) -> None:
            """Flush data to socket"""
            self.__buffer.seek(0)
            pending = memoryview(self.__buffer.read())
            sent = 0
            while sent < len(pending):
                wrote = self.__socket.send(pending[sent:])
                if wrote <= 0:
                    raise ConnectionError("socket connection broken")
                sent += wrote
            self.__buffer = io.BytesIO()
'''

READ_INT_ALREADY = 'struct.unpack(">i", self.read_exact(4))[0]'
READ_INT_OLD = 'struct.unpack(">i", self.read(4))[0]'

BODY_ALREADY = """self.connection.read_exact(
            ap_response_message_length - 4)"""
BODY_OLD = """self.connection.read(
            ap_response_message_length - 4)"""


def find_core_files() -> list[Path]:
    files: list[Path] = []
    if len(sys.argv) > 1:
        for arg in sys.argv[1:]:
            path = Path(arg)
            if path.is_dir():
                path = path / "librespot" / "core.py"
            files.append(path)
        return files

    try:
        import librespot

        cand = Path(librespot.__file__).resolve().parent / "core.py"
        if cand.exists():
            files.append(cand)
    except Exception:
        pass

    for base in (Path(sys.prefix) / "lib", Path.home() / ".local" / "lib"):
        if not base.exists():
            continue
        for cand in base.rglob("librespot/core.py"):
            if cand not in files:
                files.append(cand)
    return files


def patch_file(path: Path) -> str:
    if not path.exists():
        return "missing"
    text = path.read_text(encoding="utf-8")
    changed = False
    status: list[str] = []

    if ALREADY in text:
        status.append("auth-lock-ok")
    elif OLD not in text:
        status.append("auth-lock-unexpected")
    else:
        text = text.replace(OLD, NEW, 1)
        changed = True
        status.append("auth-lock")

    if HANDSHAKE_ALREADY in text:
        status.append("handshake-ok")
    elif HANDSHAKE_OLD not in text:
        status.append("handshake-unexpected")
    else:
        text = text.replace(HANDSHAKE_OLD, HANDSHAKE_NEW, 1)
        changed = True
        status.append("handshake")

    if CREATE_ALREADY in text and "session.authenticate(self.login_credentials)" in text:
        status.append("close-ok")
    elif CREATE_OLD not in text:
        status.append("close-unexpected")
    else:
        text = text.replace(CREATE_OLD, CREATE_NEW, 1)
        changed = True
        status.append("close")

    if ORDERED_ALREADY in text:
        status.append("ordered-ok")
    elif ORDERED_OLD not in text:
        status.append("ordered-unexpected")
    else:
        text = text.replace(ORDERED_OLD, ORDERED_NEW, 1)
        changed = True
        status.append("ordered")

    if CREATE_MULTI_ALREADY in text:
        status.append("access-order-ok")
    elif CREATE_LOOP_OLD in text:
        text = text.replace(CREATE_LOOP_OLD, CREATE_MULTI, 1)
        changed = True
        status.append("access-order")
    elif CREATE_CURRENT not in text:
        status.append("access-order-unexpected")
    else:
        text = text.replace(CREATE_CURRENT, CREATE_MULTI, 1)
        changed = True
        status.append("access-order")

    if FLUSH_ALREADY in text:
        status.append("flush-ok")
    elif FLUSH_OLD not in text:
        status.append("flush-unexpected")
    else:
        text = text.replace(FLUSH_OLD, FLUSH_NEW, 1)
        changed = True
        status.append("flush")

    if READ_INT_ALREADY in text:
        status.append("read-int-ok")
    elif READ_INT_OLD not in text:
        status.append("read-int-unexpected")
    else:
        text = text.replace(READ_INT_OLD, READ_INT_ALREADY, 1)
        changed = True
        status.append("read-int")

    if BODY_ALREADY in text:
        status.append("body-ok")
    elif BODY_OLD not in text:
        status.append("body-unexpected")
    else:
        text = text.replace(BODY_OLD, BODY_ALREADY, 1)
        changed = True
        status.append("body")

    if changed:
        path.write_text(text, encoding="utf-8")
        cache = path.parent / "__pycache__"
        if cache.is_dir():
            for pyc in cache.glob("core*.pyc"):
                pyc.unlink(missing_ok=True)
    if any(part.endswith("unexpected") for part in status):
        return "unexpected-content (" + ",".join(status) + ")"
    if not changed:
        return "already-patched"
    return "patched (" + ",".join(status) + ")"


def main() -> int:
    files = find_core_files()
    if not files:
        print("WARNING: could not find librespot/core.py to patch", file=sys.stderr)
        return 1
    status = 0
    for path in files:
        result = patch_file(path)
        print(f"{result}: {path}")
        if result == "missing" or result.startswith("unexpected-content"):
            status = 1
    return status


if __name__ == "__main__":
    raise SystemExit(main())
