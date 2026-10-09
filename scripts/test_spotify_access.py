"""Access-point order and which handshake errors may try the next address."""

import unittest

from scripts.spotify_access import (
    is_retryable_handshake_error,
    order_access_points,
)


class OrderAccessPointsTests(unittest.TestCase):
    def test_ports_443_then_80_then_the_rest_keep_every_address(self):
        ordered = order_access_points([
            "ap.example:4070",
            "ap.example:443",
            "ap.example:80",
            "ap-b.example:443",
        ])
        self.assertEqual(
            ordered,
            [
                "ap.example:443",
                "ap-b.example:443",
                "ap.example:80",
                "ap.example:4070",
            ],
        )

    def test_empty_list_stays_empty(self):
        self.assertEqual(order_access_points([]), [])

    def test_single_4070_address_is_kept(self):
        self.assertEqual(
            order_access_points(["ap.example:4070"]),
            ["ap.example:4070"],
        )

    def test_relative_order_stays_stable_within_each_port_group(self):
        ordered = order_access_points([
            "ap-z.example:4070",
            "ap-z.example:80",
            "ap-z.example:443",
            "ap-a.example:443",
            "ap-m.example:57621",
            "ap-a.example:80",
            "ap-a.example:4070",
        ])
        self.assertEqual(
            ordered,
            [
                "ap-z.example:443",
                "ap-a.example:443",
                "ap-z.example:80",
                "ap-a.example:80",
                "ap-z.example:4070",
                "ap-m.example:57621",
                "ap-a.example:4070",
            ],
        )


class RetryableHandshakeErrorTests(unittest.TestCase):
    def test_connection_error_is_retryable(self):
        self.assertIs(
            is_retryable_handshake_error(ConnectionError("reset")),
            True,
        )

    def test_timeout_error_is_retryable(self):
        self.assertIs(is_retryable_handshake_error(TimeoutError()), True)

    def test_oserror_is_retryable(self):
        self.assertIs(
            is_retryable_handshake_error(OSError(54, "Connection reset by peer")),
            True,
        )
        self.assertIs(is_retryable_handshake_error(BrokenPipeError()), True)

    def test_signature_failure_is_not_retryable(self):
        self.assertIs(
            is_retryable_handshake_error(RuntimeError("Failed signature check!")),
            False,
        )
