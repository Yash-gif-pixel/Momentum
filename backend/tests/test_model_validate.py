"""Tests for backend/model/validate.py: the pure-Python AUC implementation
and the 12-month truncation helper used by the stability check.

The AUC cross-check against scikit-learn is skipped when scikit-learn is not
installed (validate.py's own AUC computation has no such dependency; only
this test's independent verification does).
"""

from __future__ import annotations

import json
import random
import unittest
from datetime import timedelta

from backend.common.windows import assert_within_window, seen_window
from backend.generator.schema import Profile
from backend.model.validate import roc_auc, truncate_seen_window
from backend.tests.test_scorecard import dense_profile, full_profile

try:
    from sklearn.metrics import roc_auc_score as _sklearn_roc_auc_score

    HAS_SKLEARN = True
except ImportError:
    HAS_SKLEARN = False


class TestRocAuc(unittest.TestCase):
    def test_perfect_separation_is_one(self):
        y = [0, 0, 0, 1, 1, 1]
        scores = [0.1, 0.2, 0.3, 0.7, 0.8, 0.9]
        self.assertAlmostEqual(roc_auc(y, scores), 1.0)

    def test_perfectly_backwards_is_zero(self):
        y = [0, 0, 0, 1, 1, 1]
        scores = [0.9, 0.8, 0.7, 0.3, 0.2, 0.1]
        self.assertAlmostEqual(roc_auc(y, scores), 0.0)

    def test_uninformative_scores_are_one_half(self):
        y = [0, 1, 0, 1]
        scores = [0.5, 0.5, 0.5, 0.5]
        self.assertAlmostEqual(roc_auc(y, scores), 0.5)

    def test_hand_computed_example_with_one_tie(self):
        # y=1 at scores [0.4, 0.9]; y=0 at scores [0.4, 0.2].
        # Pairs where positive > negative: (0.9>0.4)=1, (0.9>0.2)=1,
        # (0.4 vs 0.4)=tie=0.5, (0.4>0.2)=1 -> (1+1+0.5+1)/4 = 0.875
        y = [1, 0, 1, 0]
        scores = [0.4, 0.4, 0.9, 0.2]
        self.assertAlmostEqual(roc_auc(y, scores), 0.875)

    def test_raises_when_a_class_is_missing(self):
        with self.assertRaises(ValueError):
            roc_auc([0, 0, 0], [0.1, 0.5, 0.9])
        with self.assertRaises(ValueError):
            roc_auc([1, 1, 1], [0.1, 0.5, 0.9])

    @unittest.skipUnless(HAS_SKLEARN, "scikit-learn not installed in this environment")
    def test_matches_sklearn_on_random_data(self):
        rng = random.Random(123)
        for _ in range(20):
            n = rng.randint(10, 60)
            y = [rng.choice([0, 1]) for _ in range(n)]
            if len(set(y)) < 2:
                continue
            scores = [rng.random() for _ in range(n)]
            self.assertAlmostEqual(
                roc_auc(y, scores), _sklearn_roc_auc_score(y, scores), places=9
            )


class TestTruncateSeenWindow(unittest.TestCase):
    def test_produces_exactly_the_requested_number_of_months(self):
        profile = full_profile()
        truncated = truncate_seen_window(profile, months=12)
        self.assertEqual(truncated.meta.months_available, 12)
        self.assertEqual(truncated.meta.split.seen_months, 12)
        self.assertEqual(truncated.meta.split.holdout_months, 0)
        self.assertIsNone(truncated.meta.split.split_date)

    def test_drops_transactions_past_the_new_end_date(self):
        profile = full_profile()
        truncated = truncate_seen_window(profile, months=12)
        window = seen_window(truncated)
        for tx in truncated.transactions_seen:
            self.assertLessEqual(tx.date, window.end)

    def test_truncated_profile_passes_its_own_leakage_guard(self):
        """The truncated profile must be internally consistent: every kept
        transaction must fall inside the window its own new metadata claims."""
        profile = full_profile()
        truncated = truncate_seen_window(profile, months=12)
        window = seen_window(truncated)
        assert_within_window(
            truncated.transactions_seen, window, caller="test_truncate_seen_window"
        )  # must not raise

    def test_truncated_profile_has_no_holdout_transactions(self):
        profile = full_profile()
        truncated = truncate_seen_window(profile, months=12)
        self.assertEqual(truncated.transactions_holdout, [])

    def test_truncation_keeps_strictly_fewer_or_equal_transactions(self):
        profile = full_profile()
        truncated = truncate_seen_window(profile, months=12)
        self.assertLessEqual(len(truncated.transactions_seen), len(profile.transactions_seen))
        self.assertGreater(len(truncated.transactions_seen), 0)

    def test_works_on_a_real_generated_profile(self):
        from pathlib import Path

        demo_path = (
            Path(__file__).resolve().parents[2] / "data" / "demo_profile_lakshmi.json"
        )
        if not demo_path.exists():
            self.skipTest("demo_profile_lakshmi.json not present")
        profile = Profile.model_validate(json.loads(demo_path.read_text()))
        truncated = truncate_seen_window(profile, months=12)
        self.assertEqual(truncated.meta.months_available, 12)
        window = seen_window(truncated)
        assert_within_window(truncated.transactions_seen, window, caller="test")


if __name__ == "__main__":
    unittest.main()
