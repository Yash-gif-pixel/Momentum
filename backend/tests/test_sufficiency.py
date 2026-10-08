"""Sufficiency-gate tests, including the Y1 edge cases the gate must catch."""

from __future__ import annotations

import json
import unittest
from datetime import timedelta
from pathlib import Path

from backend.features.sufficiency import (
    MIN_MONTHS_ASSESSABLE,
    MIN_MONTHS_FULL_CONFIDENCE,
    MIN_TX_PER_MONTH_ASSESSABLE,
    MIN_TX_PER_MONTH_FULL_CONFIDENCE,
    SufficiencyOutcome,
    assess_sufficiency,
)
from backend.generator.schema import Profile
from backend.tests.helpers import (
    SEEN_START,
    add_months,
    income_tx,
    make_profile,
    noise_tx,
)

REPO_ROOT = Path(__file__).resolve().parents[2]
SAMPLE_PROFILE = REPO_ROOT / "data" / "sample_profile.json"
GENERATED_DIR = REPO_ROOT / "data" / "generated"


def build(months: int, tx_per_month: int, noise_per_month: int = 0) -> Profile:
    """A profile with a controlled month count and transaction density."""
    transactions = []
    for month_index in range(months):
        month = add_months(SEEN_START, month_index)
        for n in range(tx_per_month):
            day = min(1 + n, 28)
            transactions.append(income_tx(month.replace(day=day), 1_000.0))
        for n in range(noise_per_month):
            transactions.append(noise_tx(month.replace(day=min(1 + n, 28))))
    # The window must end on the last day of the last month, so that `months`
    # months of history really span `months` calendar months.
    end = add_months(SEEN_START, months) - timedelta(days=1)
    return make_profile(transactions, [], start=SEEN_START, split_date=None, end=end)


class TestHistoryLengthRule(unittest.TestCase):
    def test_below_six_months_is_not_assessable(self):
        for months in (1, 3, 5):
            with self.subTest(months=months):
                result = assess_sufficiency(build(months, tx_per_month=30))
                self.assertEqual(result.outcome, SufficiencyOutcome.NOT_ASSESSABLE)
                self.assertIn("months of history", result.reason)

    def test_six_to_twelve_months_is_low_confidence(self):
        for months in (MIN_MONTHS_ASSESSABLE, 9, MIN_MONTHS_FULL_CONFIDENCE):
            with self.subTest(months=months):
                result = assess_sufficiency(build(months, tx_per_month=30))
                self.assertEqual(result.outcome, SufficiencyOutcome.LOW_CONFIDENCE)

    def test_beyond_twelve_months_with_a_dense_trail_is_full(self):
        result = assess_sufficiency(build(24, tx_per_month=30))
        self.assertEqual(result.outcome, SufficiencyOutcome.FULL)
        self.assertTrue(result.is_full_assessment_eligible)


class TestDensityRule(unittest.TestCase):
    """The density branch: no Y1 profile is this sparse, so it is tested here."""

    def test_below_eight_transactions_a_month_is_not_assessable(self):
        result = assess_sufficiency(build(24, tx_per_month=4))
        self.assertEqual(result.outcome, SufficiencyOutcome.NOT_ASSESSABLE)
        self.assertIn("transactions/month", result.reason)

    def test_eight_to_fifteen_transactions_a_month_is_low_confidence(self):
        for density in (8, 12, 15):
            with self.subTest(density=density):
                result = assess_sufficiency(build(24, tx_per_month=density))
                self.assertEqual(result.outcome, SufficiencyOutcome.LOW_CONFIDENCE)
                self.assertIn("sparse trail", result.reason)

    def test_above_fifteen_transactions_a_month_passes_the_density_test(self):
        result = assess_sufficiency(build(24, tx_per_month=16))
        self.assertEqual(result.outcome, SufficiencyOutcome.FULL)

    def test_thresholds_are_the_documented_values(self):
        self.assertEqual(MIN_MONTHS_ASSESSABLE, 6)
        self.assertEqual(MIN_MONTHS_FULL_CONFIDENCE, 12)
        self.assertEqual(MIN_TX_PER_MONTH_ASSESSABLE, 8.0)
        self.assertEqual(MIN_TX_PER_MONTH_FULL_CONFIDENCE, 15.0)


class TestNoiseCannotBuyDensity(unittest.TestCase):
    def test_settlement_and_rounding_artifacts_do_not_lift_a_sparse_trail(self):
        """A trail must not clear the density bar on rounding artifacts alone."""
        sparse_but_noisy = build(24, tx_per_month=4, noise_per_month=40)
        result = assess_sufficiency(sparse_but_noisy)
        self.assertEqual(result.outcome, SufficiencyOutcome.NOT_ASSESSABLE)
        self.assertLess(result.transactions_per_month, MIN_TX_PER_MONTH_ASSESSABLE)


class TestEitherRuleCanGate(unittest.TestCase):
    def test_long_history_cannot_rescue_a_sparse_trail(self):
        self.assertEqual(
            assess_sufficiency(build(36, tx_per_month=3)).outcome,
            SufficiencyOutcome.NOT_ASSESSABLE,
        )

    def test_dense_trail_cannot_rescue_a_short_history(self):
        self.assertEqual(
            assess_sufficiency(build(4, tx_per_month=200)).outcome,
            SufficiencyOutcome.NOT_ASSESSABLE,
        )


class TestPlantedEdgeCases(unittest.TestCase):
    """The Y1 edge cases must never come back as full assessment eligible."""

    def test_committed_short_history_sample_is_gated(self):
        profile = Profile.model_validate(json.loads(SAMPLE_PROFILE.read_text()))
        self.assertTrue(profile.meta.is_short_history_edge_case)
        result = assess_sufficiency(profile)
        self.assertNotEqual(result.outcome, SufficiencyOutcome.FULL)
        self.assertFalse(result.is_full_assessment_eligible)

    @unittest.skipUnless(
        GENERATED_DIR.exists(), "bulk dataset not generated (it is gitignored)"
    )
    def test_no_short_history_profile_is_full_assessment_eligible(self):
        checked = 0
        for path in GENERATED_DIR.glob("*.json"):
            profile = Profile.model_validate(json.loads(path.read_text()))
            if not profile.meta.is_short_history_edge_case:
                continue
            checked += 1
            self.assertFalse(
                assess_sufficiency(profile).is_full_assessment_eligible,
                f"{profile.meta.profile_id} is short-history but passed the gate",
            )
        self.assertGreater(checked, 0, "expected planted short-history profiles")

    @unittest.skipUnless(
        GENERATED_DIR.exists(), "bulk dataset not generated (it is gitignored)"
    )
    def test_cash_heavy_profiles_are_not_gated_for_being_cash_heavy(self):
        """Cash-heavy is not a deficiency. These must still be assessable."""
        checked = 0
        for path in GENERATED_DIR.glob("*.json"):
            profile = Profile.model_validate(json.loads(path.read_text()))
            if not profile.meta.is_cash_heavy_edge_case:
                continue
            checked += 1
            self.assertTrue(
                assess_sufficiency(profile).is_full_assessment_eligible,
                f"{profile.meta.profile_id} was gated merely for being cash-heavy",
            )
        self.assertGreater(checked, 0, "expected planted cash-heavy profiles")


if __name__ == "__main__":
    unittest.main()
