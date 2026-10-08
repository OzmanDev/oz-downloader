"""Metadata decisions shared by convert and refetch."""

import importlib.util
import sys
import unittest
from pathlib import Path


def _load_postprocess():
    path = Path(__file__).with_name("zotify-postprocess.py")
    spec = importlib.util.spec_from_file_location("zotify_postprocess", path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


decide_metadata = _load_postprocess().decide_metadata


class DecideMetadataTests(unittest.TestCase):
    def test_feature_credit_in_artist_and_title_becomes_song_title(self):
        track, artist, title, require_feature_match = decide_metadata(
            "(feat. Ja-Rule & Ashanti)",
            "What's Luv",
            "(feat. Ja-Rule & Ashanti)",
            "Dj RnB",
        )
        self.assertIsNone(track)
        self.assertEqual(artist, "")
        self.assertEqual(title, "What's Luv (feat. Ja-Rule & Ashanti)")
        self.assertIs(require_feature_match, True)

    def test_underscore_splits_song_name_from_feature_credit(self):
        track, artist, title, require_feature_match = decide_metadata(
            "What's Luv_(feat. Ja-Rule & Ashanti)",
            "",
            "",
            "",
        )
        self.assertIsNone(track)
        self.assertEqual(artist, "")
        self.assertEqual(title, "What's Luv (feat. Ja-Rule & Ashanti)")
        self.assertIs(require_feature_match, True)

    def test_real_artist_and_featured_title_stay_unchanged(self):
        track, artist, title, require_feature_match = decide_metadata(
            "Best Friend (feat. Doja Cat)",
            "Saweetie",
            "Best Friend (feat. Doja Cat)",
            "",
        )
        self.assertIsNone(track)
        self.assertEqual(artist, "Saweetie")
        self.assertEqual(title, "Best Friend (feat. Doja Cat)")
        self.assertIs(require_feature_match, False)

    def test_real_artist_with_feature_in_title_stays_unchanged(self):
        track, artist, title, require_feature_match = decide_metadata(
            "What's Luv (feat. Ja-Rule & Ashanti)",
            "Fat Joe",
            "What's Luv (feat. Ja-Rule & Ashanti)",
            "",
        )
        self.assertIsNone(track)
        self.assertEqual(artist, "Fat Joe")
        self.assertEqual(title, "What's Luv (feat. Ja-Rule & Ashanti)")
        self.assertIs(require_feature_match, False)

    def test_feature_only_filename_keeps_real_tag_title(self):
        track, artist, title, require_feature_match = decide_metadata(
            "(feat. Ja-Rule & Ashanti)",
            "Fat Joe",
            "What's Luv (feat. Ja-Rule & Ashanti)",
            "",
        )
        self.assertIsNone(track)
        self.assertEqual(artist, "Fat Joe")
        self.assertEqual(title, "What's Luv (feat. Ja-Rule & Ashanti)")
        self.assertIs(require_feature_match, False)

    def test_trailing_index_is_not_the_song_title(self):
        track, artist, title, require_feature_match = decide_metadata(
            "Bzrp Music Sessions, Vol. 53_66",
            "",
            "",
            "",
        )
        self.assertIsNone(track)
        self.assertEqual(artist, "")
        self.assertEqual(title, "Bzrp Music Sessions, Vol. 53")
        self.assertIs(require_feature_match, False)

    def test_album_holds_title_when_tags_are_only_a_track_index(self):
        track, artist, title, require_feature_match = decide_metadata(
            "66",
            "Bzrp Music Sessions, Vol. 53",
            "66",
            "Shakira: Bzrp Music Sessions, Vol. 53/66",
        )
        self.assertIsNone(track)
        self.assertEqual(artist, "")
        self.assertEqual(title, "Shakira: Bzrp Music Sessions, Vol. 53")
        self.assertIs(require_feature_match, False)

    def test_numeric_title_stays_when_album_is_not_that_song(self):
        track, artist, title, require_feature_match = decide_metadata(
            "7",
            "Drake",
            "7",
            "Scorpion",
        )
        self.assertIsNone(track)
        self.assertEqual(artist, "Drake")
        self.assertEqual(title, "7")
        self.assertIs(require_feature_match, False)

    def test_leading_index_is_the_track_number(self):
        track, artist, title, require_feature_match = decide_metadata(
            "66_Shakira: Bzrp Music Sessions, Vol. 53",
            "",
            "",
            "",
        )
        self.assertEqual(track, 66)
        self.assertEqual(artist, "")
        self.assertEqual(title, "Shakira: Bzrp Music Sessions, Vol. 53")
        self.assertIs(require_feature_match, False)

    def test_playlist_stem_splits_track_artist_and_title(self):
        track, artist, title, require_feature_match = decide_metadata(
            "01_Shakira_Hips Don't Lie",
            "",
            "",
            "",
        )
        self.assertEqual(track, 1)
        self.assertEqual(artist, "Shakira")
        self.assertEqual(title, "Hips Don't Lie")
        self.assertIs(require_feature_match, False)

    def test_empty_stem_and_tags_have_no_artist_or_title(self):
        track, artist, title, require_feature_match = decide_metadata(
            "",
            "",
            "",
            "",
        )
        self.assertIsNone(track)
        self.assertEqual(artist, "")
        self.assertEqual(title, "")
        self.assertIs(require_feature_match, False)

    def test_ft_credit_in_artist_and_title_becomes_song_title(self):
        track, artist, title, require_feature_match = decide_metadata(
            "(ft. Ashanti)",
            "What's Luv",
            "(ft. Ashanti)",
            "Dj RnB",
        )
        self.assertIsNone(track)
        self.assertEqual(artist, "")
        self.assertEqual(title, "What's Luv (ft. Ashanti)")
        self.assertIs(require_feature_match, True)

    def test_leading_index_and_feature_credit_keep_the_song_name(self):
        track, artist, title, require_feature_match = decide_metadata(
            "04_What's Luv_(feat. Ja-Rule & Ashanti)",
            "",
            "",
            "",
        )
        self.assertEqual(track, 4)
        self.assertEqual(artist, "")
        self.assertEqual(title, "What's Luv (feat. Ja-Rule & Ashanti)")
        self.assertIs(require_feature_match, True)

    def test_album_prefix_matching_artist_replaces_index_title(self):
        track, artist, title, require_feature_match = decide_metadata(
            "3",
            "Calm Down",
            "3",
            "Calm Down/3",
        )
        self.assertIsNone(track)
        self.assertEqual(artist, "")
        self.assertEqual(title, "Calm Down")
        self.assertIs(require_feature_match, False)


if __name__ == "__main__":
    unittest.main()
