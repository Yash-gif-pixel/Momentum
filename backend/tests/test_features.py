"""Feature correctness tests against hand-computable profiles.

Every expected value below can be worked out on paper from the fixture, so a
failure points at the feature logic rather than at drift in the generated
dataset.
"""

from __future__ import annotations

import unittest
from datetime import date

from backend.common.cashflow import (
    indicative_emi,
    monthly_business_income,
    monthly_essential_expenses,
)
from backend.common.windows import seen_window
from backend.features.feature_engine import (
    FEATURE_FAMILIES,
    FEATURE_NAMES,
    FeatureSet,
    extract_features,
)
from backend.generator.schema import Channel, CounterpartyType, Direction
from backend.tests.helpers import (
    SEEN_START,
    add_months,
    income_tx,
    make_profile,
    monthly_profile,
    noise_tx,
    rent_tx,
    tx,
)

JAN = date(2024, 1, 1)
JAN_END = date(2024, 1, 31)


def one_month(transactions):
    """A profile covering exactly January 2024, with no held-out window."""
    return make_profile(transactions, [], start=JAN, split_date=None, end=JAN_END)


class TestAffordabilityFlagship(unittest.TestCase):
    """The single most important feature -- implemented and tested first."""

    def test_emi_is_twenty_percent_of_median_monthly_income(self):
        profile = monthly_profile([10_000.0] * 24)
        income = monthly_business_income(profile.transactions_seen, seen_window(profile))
        self.assertAlmostEqual(indicative_emi(income), 2_000.0)

    def test_all_months_cover_emi_when_income_is_comfortable(self):
        # income 10,000/mo, rent 2,000/mo -> EMI 2,000, required 4,000.
        profile = monthly_profile([10_000.0] * 24, essentials_per_month=2_000.0)
        features = extract_features(profile)
        self.assertEqual(features.months_would_cover_emi_of_last_24, 24)

    def test_months_below_emi_plus_essentials_do_not_count(self):
        # 18 months at 10,000 and 6 at 3,000 -> median still 10,000 -> EMI 2,000.
        # Required = 2,000 EMI + 2,000 rent = 4,000, so the six 3,000 months fail.
        profile = monthly_profile(
            [10_000.0] * 18 + [3_000.0] * 6, essentials_per_month=2_000.0
        )
        features = extract_features(profile)
        self.assertEqual(features.months_would_cover_emi_of_last_24, 18)

    def test_a_month_exactly_meeting_the_requirement_counts_as_covered(self):
        # median 10,000 -> EMI 2,000; rent 8,000 -> required exactly 10,000.
        profile = monthly_profile([10_000.0] * 24, essentials_per_month=8_000.0)
        self.assertEqual(extract_features(profile).months_would_cover_emi_of_last_24, 24)

    def test_zero_income_months_are_counted_as_real_zeros(self):
        """A month with no transactions must not vanish from the denominator."""
        profile = monthly_profile([10_000.0] * 20 + [0.0] * 4)
        income = monthly_business_income(profile.transactions_seen, seen_window(profile))
        self.assertEqual(len(income), 24)
        self.assertEqual(sorted(income.values())[:4], [0.0, 0.0, 0.0, 0.0])


class TestRegularityFamily(unittest.TestCase):
    def test_pct_weeks_with_income(self):
        # January 2024 starts on a Monday and spans 5 ISO weeks.
        # Income on Jan 1 only -> exactly one of those five weeks earns.
        profile = one_month([income_tx(JAN, 100.0)])
        self.assertAlmostEqual(extract_features(profile).pct_weeks_with_income, 1 / 5)

    def test_pct_weeks_with_income_is_one_when_every_week_earns(self):
        transactions = [income_tx(date(2024, 1, day), 100.0) for day in range(1, 32)]
        self.assertAlmostEqual(
            extract_features(one_month(transactions)).pct_weeks_with_income, 1.0
        )

    def test_longest_dry_streak_counts_trailing_silence(self):
        # Earns on Jan 1, then nothing for the remaining 30 days of the window.
        profile = one_month([income_tx(JAN, 100.0)])
        self.assertEqual(extract_features(profile).longest_dry_streak_days, 30)

    def test_income_coefficient_of_variation(self):
        # Sample stdev of [5000, 15000] is 7071.07; mean is 10000.
        profile = monthly_profile([5_000.0, 15_000.0])
        cv = extract_features(profile).income_coefficient_of_variation
        self.assertAlmostEqual(cv, 7071.0678 / 10_000.0, places=4)

    def test_coefficient_of_variation_is_zero_for_flat_income(self):
        profile = monthly_profile([10_000.0] * 6)
        self.assertAlmostEqual(extract_features(profile).income_coefficient_of_variation, 0.0)


class TestGrowthFamily(unittest.TestCase):
    def test_year_over_year_change(self):
        profile = monthly_profile([1_000.0] * 12 + [2_000.0] * 12)
        self.assertAlmostEqual(extract_features(profile).year_over_year_change, 1.0)

    def test_year_over_year_is_none_without_two_full_years(self):
        profile = monthly_profile([1_000.0] * 23)
        self.assertIsNone(extract_features(profile).year_over_year_change)

    def test_trend_is_season_matched_when_history_allows(self):
        # Months 7-12 earn 1,000; months 19-24 earn 2,000 -> +100% year on year
        # for the same six calendar months.
        income = [1_000.0] * 24
        for i in range(18, 24):
            income[i] = 2_000.0
        profile = monthly_profile(income)
        self.assertAlmostEqual(extract_features(profile).trend_last_6_months, 1.0)

    def test_season_matched_trend_ignores_a_seasonal_dip(self):
        """A business with an identical seasonal shape year on year is flat.

        A raw 6-month slope would report this as a steep decline; the
        season-matched comparison correctly reports no change.
        """
        season = [3_000.0, 3_000.0, 3_000.0, 9_000.0, 9_000.0, 9_000.0,
                  9_000.0, 9_000.0, 9_000.0, 3_000.0, 3_000.0, 3_000.0]
        profile = monthly_profile(season * 2)
        self.assertAlmostEqual(extract_features(profile).trend_last_6_months, 0.0)

    def test_trend_falls_back_to_slope_on_short_history(self):
        # Six months rising 100 -> 600: slope 100, mean 350.
        profile = monthly_profile([100.0, 200.0, 300.0, 400.0, 500.0, 600.0])
        self.assertAlmostEqual(
            extract_features(profile).trend_last_6_months, 100.0 / 350.0, places=6
        )

    def test_trend_is_none_below_six_months(self):
        profile = monthly_profile([100.0] * 5)
        self.assertIsNone(extract_features(profile).trend_last_6_months)


class TestDisciplineFamily(unittest.TestCase):
    def test_expense_to_income_ratio(self):
        profile = monthly_profile([10_000.0] * 12, essentials_per_month=2_000.0)
        self.assertAlmostEqual(extract_features(profile).expense_to_income_ratio, 0.2)

    def test_ontime_bill_payment_rate(self):
        # Day 3 is on time (<= 7), day 15 is late.
        profile = one_month(
            [income_tx(JAN, 10_000.0), rent_tx(date(2024, 1, 3), 500.0), rent_tx(date(2024, 1, 15), 500.0)]
        )
        self.assertAlmostEqual(extract_features(profile).ontime_bill_payment_rate, 0.5)

    def test_ontime_rate_is_none_without_any_bills(self):
        profile = one_month([income_tx(JAN, 10_000.0)])
        self.assertIsNone(extract_features(profile).ontime_bill_payment_rate)

    def test_bill_reversals_are_not_counted_as_separate_bills(self):
        reversal = tx(
            date(2024, 1, 3), 500.0, Direction.OUT, CounterpartyType.RENT, "upi_reversal"
        )
        profile = one_month(
            [income_tx(JAN, 10_000.0), rent_tx(date(2024, 1, 3), 500.0), reversal]
        )
        # Only the real bill counts, and it was on time.
        self.assertAlmostEqual(extract_features(profile).ontime_bill_payment_rate, 1.0)


class TestResilienceFamily(unittest.TestCase):
    def test_cash_buffer_days(self):
        # January has 31 days. Income 10,000, rent 3,100 -> surplus 6,900;
        # average daily expense 3,100/31 = 100 -> 69 days of cover.
        profile = one_month([income_tx(date(2024, 1, 10), 10_000.0), rent_tx(date(2024, 1, 3), 3_100.0)])
        self.assertAlmostEqual(extract_features(profile).cash_buffer_days, 69.0)

    def test_cash_buffer_days_is_negative_when_burning_cash(self):
        profile = one_month([income_tx(date(2024, 1, 10), 1_000.0), rent_tx(date(2024, 1, 3), 3_100.0)])
        self.assertLess(extract_features(profile).cash_buffer_days, 0.0)

    def test_cash_buffer_days_is_none_without_expenses(self):
        profile = one_month([income_tx(JAN, 10_000.0)])
        self.assertIsNone(extract_features(profile).cash_buffer_days)

    def test_worst_monthly_dip_pct(self):
        profile = monthly_profile([10_000.0, 10_000.0, 5_000.0])
        self.assertAlmostEqual(extract_features(profile).worst_monthly_dip_pct, 0.5)

    def test_worst_dip_is_one_when_a_month_earns_nothing(self):
        profile = monthly_profile([10_000.0, 10_000.0, 0.0])
        self.assertAlmostEqual(extract_features(profile).worst_monthly_dip_pct, 1.0)


class TestTrailFamily(unittest.TestCase):
    def test_digital_and_cash_shares_split_by_value(self):
        profile = one_month(
            [
                income_tx(JAN, 300.0, channel=Channel.UPI),
                income_tx(JAN, 100.0, channel=Channel.CASH),
            ]
        )
        features = extract_features(profile)
        self.assertAlmostEqual(features.digital_share, 0.75)
        self.assertAlmostEqual(features.cash_share, 0.25)

    def test_shares_sum_to_one(self):
        profile = monthly_profile([10_000.0] * 6, essentials_per_month=1_000.0)
        features = extract_features(profile)
        self.assertAlmostEqual(features.digital_share + features.cash_share, 1.0)


class TestNoiseAndReversalHandling(unittest.TestCase):
    def test_rounding_artifacts_do_not_count_as_income(self):
        profile = one_month([noise_tx(JAN, 2.0)])
        income = monthly_business_income(profile.transactions_seen, seen_window(profile))
        self.assertEqual(sum(income.values()), 0.0)
        # ...and must not make the week look like it traded.
        self.assertAlmostEqual(extract_features(profile).pct_weeks_with_income, 0.0)

    def test_reversed_income_nets_to_zero(self):
        reversal = tx(
            date(2024, 1, 11), 10_000.0, Direction.OUT, CounterpartyType.CUSTOMER, "upi_reversal"
        )
        profile = one_month([income_tx(date(2024, 1, 10), 10_000.0), reversal])
        income = monthly_business_income(profile.transactions_seen, seen_window(profile))
        self.assertAlmostEqual(sum(income.values()), 0.0)

    def test_supplier_refund_reduces_essential_expenses(self):
        refund = tx(
            date(2024, 1, 20), 400.0, Direction.IN, CounterpartyType.SUPPLIER, "upi_reversal"
        )
        profile = one_month([income_tx(JAN, 10_000.0), rent_tx(date(2024, 1, 3), 1_000.0), refund])
        essentials = monthly_essential_expenses(
            profile.transactions_seen, seen_window(profile)
        )
        self.assertAlmostEqual(sum(essentials.values()), 600.0)


class TestFeatureVocabulary(unittest.TestCase):
    def test_exactly_twelve_features(self):
        self.assertEqual(len(FEATURE_NAMES), 12)
        self.assertEqual(len(set(FEATURE_NAMES)), 12)

    def test_families_cover_every_feature_exactly_once(self):
        flattened = [n for family in FEATURE_FAMILIES.values() for n in family]
        self.assertEqual(sorted(flattened), sorted(FEATURE_NAMES))

    def test_six_families(self):
        self.assertEqual(
            set(FEATURE_FAMILIES),
            {"regularity", "growth", "discipline", "resilience", "affordability", "trail"},
        )

    def test_dataclass_fields_match_the_declared_vocabulary(self):
        self.assertEqual(sorted(FeatureSet.__dataclass_fields__), sorted(FEATURE_NAMES))

    def test_as_dict_round_trips_every_feature(self):
        profile = monthly_profile([10_000.0] * 24, essentials_per_month=1_000.0)
        values = extract_features(profile).as_dict()
        self.assertEqual(sorted(values), sorted(FEATURE_NAMES))


if __name__ == "__main__":
    unittest.main()
