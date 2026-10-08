"""Label-leakage tests.

The single most damaging bug this pipeline could have is a feature that can
see the held-out months. It would not crash, it would not look wrong -- it
would just quietly produce a model that scores brilliantly in validation and
fails in production, and nobody would notice until it was lending money.

So these tests attack the boundary from both sides:

  * the tripwire tests prove the guard fires when transactions cross the line
  * the invariance test proves the actual guarantee -- that held-out data
    cannot change a single feature value, no matter how violently it changes

The invariance test is the one that matters most. It would catch a future edit
that reads `profile.transactions_holdout` inside feature code even if that edit
carefully kept the dates inside the window and slipped past the tripwire.
"""

from __future__ import annotations

import json
import unittest
from datetime import date, timedelta
from pathlib import Path

from backend.common.cashflow import indicative_emi, monthly_business_income
from backend.common.windows import (
    LeakageError,
    assert_within_window,
    holdout_window,
    seen_window,
)
from backend.features.feature_engine import extract_features
from backend.generator.schema import Channel, Profile
from backend.labels.label_engine import derive_label
from backend.tests.helpers import SPLIT_DATE, income_tx, make_profile, monthly_profile

REPO_ROOT = Path(__file__).resolve().parents[2]
DEMO_PROFILE = REPO_ROOT / "data" / "demo_profile_lakshmi.json"


class TestLeakageTripwire(unittest.TestCase):
    """The guard must fire when a transaction crosses the seen/held-out line."""

    def test_feature_engine_rejects_a_holdout_transaction_in_the_seen_list(self):
        # A transaction dated inside the held-out window, smuggled into the
        # list the feature engine reads.
        profile = monthly_profile(
            [10_000.0] * 24,
            holdout_income_per_month=[10_000.0] * 6,
        )
        smuggled = income_tx(SPLIT_DATE + timedelta(days=5), 999_999.0)
        profile.transactions_seen.append(smuggled)

        with self.assertRaises(LeakageError) as ctx:
            extract_features(profile)
        self.assertIn("feature_engine", str(ctx.exception))
        self.assertIn("leakage", str(ctx.exception).lower())

    def test_label_engine_rejects_a_seen_transaction_in_the_holdout_list(self):
        profile = monthly_profile(
            [10_000.0] * 24,
            holdout_income_per_month=[10_000.0] * 6,
        )
        smuggled = income_tx(SPLIT_DATE - timedelta(days=5), 999_999.0)
        profile.transactions_holdout.append(smuggled)

        with self.assertRaises(LeakageError):
            derive_label(profile, indicative_emi={"m": 1.0}.get("m", 1.0))

    def test_guard_reports_the_offending_date_and_window(self):
        profile = monthly_profile([10_000.0] * 24, holdout_income_per_month=[1.0] * 6)
        window = seen_window(profile)
        stray = income_tx(date(2030, 1, 1), 5.0)

        with self.assertRaises(LeakageError) as ctx:
            assert_within_window([stray], window, caller="unit_test")
        message = str(ctx.exception)
        self.assertIn("2030-01-01", message)
        self.assertIn("unit_test", message)

    def test_guard_is_not_disabled_by_python_optimize_flag(self):
        # LeakageError must be raised explicitly, not via a bare `assert`
        # statement, which `python -O` strips out entirely.
        self.assertTrue(issubclass(LeakageError, AssertionError))
        source = (REPO_ROOT / "backend" / "common" / "windows.py").read_text()
        self.assertIn("raise LeakageError", source)


class TestFeatureInvarianceToHeldOutData(unittest.TestCase):
    """Features must not move when the held-out window changes. At all."""

    def _mutations(self, profile: Profile) -> list[tuple[str, Profile]]:
        window = holdout_window(profile)
        assert window is not None

        inflated = profile.model_copy(deep=True)
        for transaction in inflated.transactions_holdout:
            transaction.amount *= 1000

        emptied = profile.model_copy(deep=True)
        emptied.transactions_holdout = []

        # Cash channel on purpose: if a channel-share feature ever leaked, a
        # holdout made entirely of cash would shift digital_share/cash_share
        # even when the amounts look unremarkable.
        collapsed = profile.model_copy(deep=True)
        collapsed.transactions_holdout = [
            income_tx(window.start, 50_000.0, channel=Channel.CASH),
        ]

        return [
            ("holdout amounts inflated 1000x", inflated),
            ("holdout window emptied", emptied),
            ("holdout collapsed to a single rupee", collapsed),
        ]

    def test_synthetic_profile_features_ignore_holdout(self):
        profile = monthly_profile(
            [10_000.0 + 100 * i for i in range(24)],
            essentials_per_month=2_000.0,
            holdout_income_per_month=[10_000.0] * 6,
            holdout_essentials_per_month=2_000.0,
        )
        baseline = extract_features(profile).as_dict()

        for description, mutated in self._mutations(profile):
            with self.subTest(mutation=description):
                self.assertEqual(
                    extract_features(mutated).as_dict(),
                    baseline,
                    f"a feature changed when {description} -- held-out data is "
                    "reaching the feature engine",
                )

    def test_real_demo_profile_features_ignore_holdout(self):
        profile = Profile.model_validate(json.loads(DEMO_PROFILE.read_text()))
        baseline = extract_features(profile).as_dict()

        for description, mutated in self._mutations(profile):
            with self.subTest(mutation=description):
                self.assertEqual(
                    extract_features(mutated).as_dict(),
                    baseline,
                    f"a feature changed when {description}",
                )

    def test_label_does_move_with_holdout(self):
        """Control: proves the invariance above is a real constraint.

        If the label were also blind to the held-out window, the invariance
        test would pass trivially and prove nothing.
        """
        good = monthly_profile(
            [10_000.0] * 24,
            holdout_income_per_month=[10_000.0] * 6,
            holdout_essentials_per_month=1_000.0,
        )
        bad = monthly_profile(
            [10_000.0] * 24,
            holdout_income_per_month=[100.0] * 6,
            holdout_essentials_per_month=1_000.0,
        )
        emi = indicative_emi(
            monthly_business_income(good.transactions_seen, seen_window(good))
        )

        good_label = derive_label(good, emi)
        bad_label = derive_label(bad, emi)
        assert good_label is not None and bad_label is not None
        self.assertEqual(good_label.label, 0)
        self.assertEqual(bad_label.label, 1)


class TestWindowBoundaries(unittest.TestCase):
    def test_seen_window_stops_the_day_before_the_split(self):
        profile = monthly_profile([10_000.0] * 24, holdout_income_per_month=[1.0] * 6)
        window = seen_window(profile)
        self.assertEqual(window.end, SPLIT_DATE - timedelta(days=1))
        self.assertFalse(window.contains(SPLIT_DATE))

    def test_holdout_window_starts_on_the_split(self):
        profile = monthly_profile([10_000.0] * 24, holdout_income_per_month=[1.0] * 6)
        window = holdout_window(profile)
        assert window is not None
        self.assertEqual(window.start, SPLIT_DATE)
        self.assertTrue(window.contains(SPLIT_DATE))

    def test_windows_do_not_overlap(self):
        profile = monthly_profile([10_000.0] * 24, holdout_income_per_month=[1.0] * 6)
        seen, held = seen_window(profile), holdout_window(profile)
        assert held is not None
        self.assertLess(seen.end, held.start)

    def test_short_history_profile_has_no_holdout_window(self):
        profile = monthly_profile([10_000.0] * 5)
        self.assertIsNone(holdout_window(profile))
        self.assertIsNone(derive_label(profile, 1_000.0))

    def test_seen_window_covers_whole_history_when_there_is_no_split(self):
        profile = monthly_profile([10_000.0] * 5)
        window = seen_window(profile)
        self.assertEqual(window.start, profile.meta.history_start_date)
        self.assertEqual(window.end, profile.meta.history_end_date)


if __name__ == "__main__":
    unittest.main()
