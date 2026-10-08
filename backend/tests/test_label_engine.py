"""Label-engine tests: the held-out default definition and its threshold."""

from __future__ import annotations

import unittest

from backend.labels.label_engine import DEFAULT_THRESHOLD_MONTHS, derive_label
from backend.tests.helpers import monthly_profile

SEEN_24 = [10_000.0] * 24
# With seen income of 10,000/month the indicative EMI is 20% = 2,000.
EMI = 2_000.0
ESSENTIALS = 1_000.0
# So a held-out month must earn at least 2,000 + 1,000 = 3,000 to be covered.
COVERED = 10_000.0
SHORTFALL = 500.0


def profile_with(holdout_income: list[float]):
    return monthly_profile(
        SEEN_24,
        essentials_per_month=ESSENTIALS,
        holdout_income_per_month=holdout_income,
        holdout_essentials_per_month=ESSENTIALS,
    )


class TestDefaultThreshold(unittest.TestCase):
    def test_no_shortfall_months_is_not_a_default(self):
        result = derive_label(profile_with([COVERED] * 6), EMI)
        assert result is not None
        self.assertEqual(result.months_failed, 0)
        self.assertEqual(result.label, 0)
        self.assertFalse(result.is_default)

    def test_a_single_bad_month_is_not_a_default(self):
        """One shortfall is a seasonal shock, not a pattern."""
        result = derive_label(profile_with([COVERED] * 5 + [SHORTFALL]), EMI)
        assert result is not None
        self.assertEqual(result.months_failed, 1)
        self.assertEqual(result.label, 0)

    def test_two_bad_months_is_a_default(self):
        result = derive_label(profile_with([COVERED] * 4 + [SHORTFALL] * 2), EMI)
        assert result is not None
        self.assertEqual(result.months_failed, 2)
        self.assertEqual(result.label, 1)
        self.assertTrue(result.is_default)

    def test_every_month_failing_is_a_default(self):
        result = derive_label(profile_with([SHORTFALL] * 6), EMI)
        assert result is not None
        self.assertEqual(result.months_failed, 6)
        self.assertEqual(result.label, 1)

    def test_threshold_constant_is_two(self):
        self.assertEqual(DEFAULT_THRESHOLD_MONTHS, 2)


class TestCoverageArithmetic(unittest.TestCase):
    def test_a_month_exactly_meeting_the_requirement_is_covered(self):
        # Requirement is EMI 2,000 + essentials 1,000 = exactly 3,000.
        result = derive_label(profile_with([3_000.0] * 6), EMI)
        assert result is not None
        self.assertEqual(result.months_failed, 0)
        self.assertEqual(result.label, 0)

    def test_a_month_one_rupee_short_fails(self):
        result = derive_label(profile_with([2_999.0] * 6), EMI)
        assert result is not None
        self.assertEqual(result.months_failed, 6)

    def test_all_six_holdout_months_are_evaluated(self):
        result = derive_label(profile_with([COVERED] * 6), EMI)
        assert result is not None
        self.assertEqual(result.months_evaluated, 6)
        self.assertEqual(len(result.monthly_shortfalls), 6)

    def test_a_month_with_no_income_at_all_still_counts_as_a_failure(self):
        result = derive_label(profile_with([COVERED] * 4 + [0.0, 0.0]), EMI)
        assert result is not None
        self.assertEqual(result.months_failed, 2)
        self.assertEqual(result.label, 1)


class TestEmiIsSuppliedNotRecomputed(unittest.TestCase):
    """The EMI comes from the seen window; the label engine must honour it."""

    def test_a_larger_emi_makes_the_same_holdout_a_default(self):
        profile = profile_with([COVERED] * 6)

        comfortable = derive_label(profile, EMI)
        punishing = derive_label(profile, 50_000.0)
        assert comfortable is not None and punishing is not None

        self.assertEqual(comfortable.label, 0)
        self.assertEqual(punishing.label, 1)
        self.assertEqual(punishing.months_failed, 6)

    def test_the_supplied_emi_is_recorded_on_the_result(self):
        result = derive_label(profile_with([COVERED] * 6), 1_234.0)
        assert result is not None
        self.assertAlmostEqual(result.indicative_emi, 1_234.0)


class TestUnlabelableProfiles(unittest.TestCase):
    def test_short_history_profile_cannot_be_labeled(self):
        """No held-out window means no label -- not a guessed one."""
        profile = monthly_profile([10_000.0] * 5)
        self.assertIsNone(derive_label(profile, EMI))

    def test_a_business_that_stopped_trading_is_a_default_not_unlabelable(self):
        """An empty held-out window is the most severe default there is.

        The window still exists -- the business simply recorded nothing in it.
        Treating that as "unlabelable" would silently drop the worst cases from
        validation and bias the measured default rate downward.
        """
        profile = profile_with([COVERED] * 6)
        profile.transactions_holdout = []

        result = derive_label(profile, EMI)
        assert result is not None
        self.assertEqual(result.months_failed, 6)
        self.assertEqual(result.months_evaluated, 6)
        self.assertEqual(result.label, 1)

    def test_profile_with_no_measurable_seen_income_is_unlabelable(self):
        """An EMI of zero cannot test repayment capacity.

        With no income across months 1-24 no lender would size an obligation,
        and a zero EMI would collapse the coverage test into `income >= 0`,
        labelling a dead business as certain to repay.
        """
        profile = profile_with([COVERED] * 6)
        self.assertIsNone(derive_label(profile, 0.0))


class TestShortfallReporting(unittest.TestCase):
    def test_shortfall_is_positive_when_short_and_negative_when_comfortable(self):
        result = derive_label(profile_with([COVERED] * 3 + [SHORTFALL] * 3), EMI)
        assert result is not None
        gaps = sorted(result.monthly_shortfalls.values())
        # Three comfortable months (negative gap) and three shortfalls (positive).
        self.assertEqual(sum(1 for g in gaps if g > 0), 3)
        self.assertEqual(sum(1 for g in gaps if g < 0), 3)

    def test_shortfall_magnitude_is_exact(self):
        # Requirement 3,000; earned 500 -> gap of 2,500.
        result = derive_label(profile_with([SHORTFALL] * 6), EMI)
        assert result is not None
        for gap in result.monthly_shortfalls.values():
            self.assertAlmostEqual(gap, 2_500.0)


if __name__ == "__main__":
    unittest.main()
