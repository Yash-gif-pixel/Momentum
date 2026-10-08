"""Tests for backend/model/reason_codes.py: templates and ranked selection."""

from __future__ import annotations

import re
import unittest

from backend.features.feature_engine import FEATURE_NAMES
from backend.model.artifact import PREDICTIVE_FEATURES
from backend.model.reason_codes import TEMPLATES, rank_reason_codes
from backend.tests.model_helpers import make_artifact, neutral_feature_values

_HAS_DIGIT = re.compile(r"\d")


class TestTemplateCompleteness(unittest.TestCase):
    def test_every_one_of_the_twelve_features_has_a_template(self):
        self.assertEqual(set(TEMPLATES), set(FEATURE_NAMES))
        self.assertEqual(len(TEMPLATES), 12)

    def test_every_predictive_feature_has_a_template(self):
        self.assertTrue(set(PREDICTIVE_FEATURES) <= set(TEMPLATES))


class TestTemplatesProduceRealSentences(unittest.TestCase):
    """Every template, both directions, with a real value -> a specific,
    non-vague sentence containing the actual number."""

    # A representative value per feature, chosen inside its plausible range.
    SAMPLE_VALUES = {
        "pct_weeks_with_income": 0.86,
        "income_coefficient_of_variation": 0.42,
        "longest_dry_streak_days": 7,
        "trend_last_6_months": 0.15,
        "year_over_year_change": -0.08,
        "expense_to_income_ratio": 0.55,
        "ontime_bill_payment_rate": 0.7,
        "cash_buffer_days": 12.0,
        "worst_monthly_dip_pct": 0.33,
        "months_would_cover_emi_of_last_24": 19,
        "digital_share": 0.65,
        "cash_share": 0.35,
    }

    def test_positive_and_negative_are_non_empty_and_distinct(self):
        for feature, value in self.SAMPLE_VALUES.items():
            with self.subTest(feature=feature):
                template = TEMPLATES[feature]
                pos = template.positive(value)
                neg = template.negative(value)
                self.assertTrue(pos.strip())
                self.assertTrue(neg.strip())
                self.assertNotEqual(pos, neg)

    def test_every_statement_contains_a_real_number(self):
        """Never vague: the actual value must show up in the rendered text."""
        for feature, value in self.SAMPLE_VALUES.items():
            with self.subTest(feature=feature):
                template = TEMPLATES[feature]
                self.assertRegex(template.positive(value), _HAS_DIGIT)
                self.assertRegex(template.negative(value), _HAS_DIGIT)

    def test_negative_value_growth_templates_render_correctly(self):
        # trend_last_6_months / year_over_year_change flip wording by sign.
        for feature in ("trend_last_6_months", "year_over_year_change"):
            template = TEMPLATES[feature]
            self.assertIn("down", template.negative(-0.2).lower())
            self.assertIn("up", template.positive(0.2).lower())

    def test_negative_cash_buffer_reads_as_burning_cash_not_a_thin_buffer(self):
        template = TEMPLATES["cash_buffer_days"]
        statement = template.negative(-15.0)
        self.assertIn("burns cash", statement.lower())
        self.assertIn("15", statement)

    def test_percent_style_values_are_rendered_as_percentages(self):
        template = TEMPLATES["pct_weeks_with_income"]
        self.assertIn("96%", template.positive(0.96))
        self.assertIn("60%", template.negative(0.60))
        # matches the brief's own example almost exactly
        self.assertEqual(
            template.positive(0.96), "Income arrived in 96% of weeks — a steady trading rhythm."
        )


class TestIsFavorableThresholds(unittest.TestCase):
    def test_pct_weeks_with_income(self):
        self.assertTrue(TEMPLATES["pct_weeks_with_income"].is_favorable(0.9))
        self.assertFalse(TEMPLATES["pct_weeks_with_income"].is_favorable(0.3))

    def test_months_would_cover_emi(self):
        self.assertTrue(TEMPLATES["months_would_cover_emi_of_last_24"].is_favorable(24))
        self.assertFalse(TEMPLATES["months_would_cover_emi_of_last_24"].is_favorable(3))

    def test_expense_to_income_ratio_lower_is_favorable(self):
        self.assertTrue(TEMPLATES["expense_to_income_ratio"].is_favorable(0.2))
        self.assertFalse(TEMPLATES["expense_to_income_ratio"].is_favorable(0.9))

    def test_cash_share_is_always_favorable_informational_only(self):
        self.assertTrue(TEMPLATES["cash_share"].is_favorable(0.99))
        self.assertTrue(TEMPLATES["cash_share"].is_favorable(0.01))


class TestRankReasonCodes(unittest.TestCase):
    def test_top_three_strengths_and_concerns_by_absolute_contribution(self):
        # Favorable values on features with positive coefficients (strengths),
        # unfavorable values on features with negative coefficients (concerns),
        # magnitudes chosen so ranking order is unambiguous.
        artifact = make_artifact(
            coefficients={
                "months_would_cover_emi_of_last_24": 3.0,  # strongest strength
                "ontime_bill_payment_rate": 2.0,
                "cash_buffer_days": 1.0,
                "expense_to_income_ratio": -3.0,  # strongest concern
                "worst_monthly_dip_pct": -2.0,
                "income_coefficient_of_variation": -1.0,
            }
        )
        values = {
            **neutral_feature_values(),
            "months_would_cover_emi_of_last_24": 22,  # favorable
            "ontime_bill_payment_rate": 0.95,  # favorable
            "cash_buffer_days": 40.0,  # favorable
            "expense_to_income_ratio": 0.9,  # unfavorable
            "worst_monthly_dip_pct": 0.8,  # unfavorable
            "income_coefficient_of_variation": 0.9,  # unfavorable
        }
        strengths, concerns = rank_reason_codes(artifact, values)

        self.assertEqual(len(strengths), 3)
        self.assertEqual(len(concerns), 3)
        self.assertEqual(strengths[0].feature, "months_would_cover_emi_of_last_24")
        self.assertEqual(concerns[0].feature, "expense_to_income_ratio")
        # Strictly decreasing |contribution| within each list.
        self.assertTrue(
            all(
                abs(strengths[i].contribution) >= abs(strengths[i + 1].contribution)
                for i in range(len(strengths) - 1)
            )
        )
        self.assertTrue(
            all(
                abs(concerns[i].contribution) >= abs(concerns[i + 1].contribution)
                for i in range(len(concerns) - 1)
            )
        )

    def test_never_pads_with_filler_when_fewer_than_three_qualify(self):
        artifact = make_artifact(coefficients={"months_would_cover_emi_of_last_24": 1.0})
        values = {**neutral_feature_values(), "months_would_cover_emi_of_last_24": 22}
        strengths, concerns = rank_reason_codes(artifact, values)
        self.assertEqual(len(strengths), 1)
        self.assertEqual(len(concerns), 0)

    def test_zero_contribution_is_never_a_reason_code(self):
        artifact = make_artifact()  # all coefficients zero
        strengths, concerns = rank_reason_codes(artifact, neutral_feature_values())
        self.assertEqual(strengths, [])
        self.assertEqual(concerns, [])

    def test_missing_raw_value_cannot_produce_a_reason_code(self):
        artifact = make_artifact(coefficients={"trend_last_6_months": 5.0})
        values = neutral_feature_values()
        values["trend_last_6_months"] = None
        strengths, concerns = rank_reason_codes(artifact, values)
        self.assertEqual(strengths, [])
        self.assertEqual(concerns, [])

    def test_excluded_features_never_appear_even_with_extreme_values(self):
        artifact = make_artifact(coefficients={name: 1.0 for name in PREDICTIVE_FEATURES})
        values = {**neutral_feature_values(), "digital_share": 1.0, "cash_share": 0.0}
        strengths, concerns = rank_reason_codes(artifact, values)
        features_seen = {r.feature for r in strengths + concerns}
        self.assertNotIn("digital_share", features_seen)
        self.assertNotIn("cash_share", features_seen)


class TestCoherenceFiltering(unittest.TestCase):
    """The core mitigation for coefficient-sign instability (see reason_codes.py
    module docstring): a statistically-driven bucket that disagrees with the
    raw value's own face-value read must be skipped, not shown backwards."""

    def test_a_flipped_sign_feature_is_skipped_not_shown_backwards(self):
        # pct_weeks_with_income coefficient is POSITIVE here, but the profile's
        # raw value (0.95) is high/favorable AND the feature is BELOW its own
        # mean (negative z, since mean=0 in the fixture and raw values here are
        # all positive)... construct explicitly instead of relying on that.
        artifact = make_artifact(coefficients={"pct_weeks_with_income": -1.0})
        # z = 0.95 (mean 0, scale 1) -> contribution = -1.0 * 0.95 = negative
        # -> lands in "concerns" bucket. But is_favorable(0.95) is True, so it
        # must be skipped rather than rendered as a concern.
        values = {**neutral_feature_values(), "pct_weeks_with_income": 0.95}
        strengths, concerns = rank_reason_codes(artifact, values)
        features_seen = {r.feature for r in strengths + concerns}
        self.assertNotIn("pct_weeks_with_income", features_seen)

    def test_a_coherent_signal_still_comes_through_on_the_same_fixture(self):
        # Same artifact, but now the raw value is genuinely unfavorable (0.2),
        # which DOES agree with the "concern" bucket the flipped-looking
        # coefficient produces here -- this should be accepted.
        artifact = make_artifact(coefficients={"pct_weeks_with_income": -1.0})
        values = {**neutral_feature_values(), "pct_weeks_with_income": 0.2}
        # z = 0.2, contribution = -1.0*0.2 = negative -> concerns bucket,
        # is_favorable(0.2) is False -> coherent -> accepted.
        strengths, concerns = rank_reason_codes(artifact, values)
        self.assertEqual([r.feature for r in concerns], ["pct_weeks_with_income"])


if __name__ == "__main__":
    unittest.main()
