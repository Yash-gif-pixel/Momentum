"""Tests for backend/model/scorecard.py: analyze_profile's contract conformance
and its gate-first behavior.

These use a small hand-built artifact (backend.tests.model_helpers), not a
real trained one, so they run without a training run and assert exact,
predictable numbers.
"""

from __future__ import annotations

import unittest
from datetime import timedelta

from backend.contract.api_schema import AnalyzeResponse, Band, Confidence, Outcome
from backend.model.scorecard import analyze_profile
from backend.tests.helpers import SEEN_START, add_months, income_tx, make_profile, rent_tx
from backend.tests.model_helpers import make_artifact

# monthly_profile (Y2's helper) places only ~2 transactions/month, well under
# the sufficiency gate's density floor. These tests need to move a profile
# across NOT_ASSESSABLE / LOW_CONFIDENCE / FULL deliberately, so density has
# to be a controlled knob, not an accident of a helper built for a different
# purpose. dense_profile() spaces `tx_per_month` income transactions evenly
# across each month, well above the 15/month FULL threshold by default.


def dense_profile(
    n_months: int,
    monthly_income: float = 10_000.0,
    tx_per_month: int = 20,
    essentials_per_month: float = 1_000.0,
):
    seen = []
    per_tx = monthly_income / tx_per_month
    for i in range(n_months):
        month = add_months(SEEN_START, i)
        for d in range(tx_per_month):
            day = min(1 + d, 28)
            seen.append(income_tx(month.replace(day=day), per_tx))
        seen.append(rent_tx(month.replace(day=27), essentials_per_month))
    end = add_months(SEEN_START, n_months) - timedelta(days=1)
    return make_profile(seen, [], start=SEEN_START, split_date=None, end=end)


def full_profile(monthly_income: float = 10_000.0, essentials: float = 1_000.0):
    return dense_profile(24, monthly_income=monthly_income, essentials_per_month=essentials)


class TestGateShortCircuit(unittest.TestCase):
    """LOW_CONFIDENCE / NOT_ASSESSABLE must never reach the model."""

    def test_not_assessable_profile_never_calls_the_model(self):
        short = dense_profile(3)  # 3 months -> NOT_ASSESSABLE
        # No artifact is passed AND none is trained on disk in a clean test
        # environment; if the gate branch tried to load one, this would raise
        # FileNotFoundError instead of returning a response.
        response = analyze_profile(short)
        self.assertEqual(response.outcome, Outcome.NOT_ASSESSABLE)
        self.assertIsNone(response.vitality_score)
        self.assertIsNone(response.band)
        self.assertIsNone(response.confidence)
        self.assertEqual(response.reason_codes.strengths, [])
        self.assertEqual(response.reason_codes.concerns, [])
        self.assertIsNotNone(response.coverage_reason)

    def test_low_confidence_profile_never_calls_the_model(self):
        thin = dense_profile(9)  # 9 months, dense -> LOW_CONFIDENCE (months rule)
        response = analyze_profile(thin)
        self.assertEqual(response.outcome, Outcome.LOW_CONFIDENCE)
        self.assertIsNone(response.vitality_score)
        self.assertIsNone(response.band)
        self.assertIsNotNone(response.coverage_reason)

    def test_full_profile_with_injected_artifact_reaches_the_model(self):
        profile = full_profile()
        artifact = make_artifact(
            coefficients={"months_would_cover_emi_of_last_24": 1.0}, intercept=0.0
        )
        response = analyze_profile(profile, artifact=artifact)
        self.assertEqual(response.outcome, Outcome.SCORED)
        self.assertIsNotNone(response.vitality_score)
        self.assertIsNotNone(response.band)
        self.assertEqual(response.confidence, Confidence.HIGH)
        self.assertIsNone(response.coverage_reason)


class TestResponseShapeMatchesTheContract(unittest.TestCase):
    def test_response_is_a_real_analyze_response_instance(self):
        profile = full_profile()
        artifact = make_artifact()
        response = analyze_profile(profile, artifact=artifact)
        self.assertIsInstance(response, AnalyzeResponse)

    def test_disclaimer_is_the_contract_constant(self):
        from backend.contract.api_schema import DISCLAIMER

        response = analyze_profile(dense_profile(3))
        self.assertEqual(response.disclaimer, DISCLAIMER)

    def test_profile_id_is_preserved(self):
        profile = full_profile()
        response = analyze_profile(profile, artifact=make_artifact())
        self.assertEqual(response.profile_id, profile.meta.profile_id)

    def test_vitality_score_is_within_the_contracts_bounds(self):
        # Pydantic's Field(ge=0, le=100) on AnalyzeResponse already enforces
        # this at construction time; an extreme logit must still clip cleanly.
        profile = full_profile()
        extreme_artifact = make_artifact(
            coefficients={"months_would_cover_emi_of_last_24": 1000.0}, intercept=1000.0
        )
        response = analyze_profile(profile, artifact=extreme_artifact)
        self.assertGreaterEqual(response.vitality_score, 0.0)
        self.assertLessEqual(response.vitality_score, 100.0)

    def test_monthly_cashflow_entries_match_the_contract_shape(self):
        response = analyze_profile(full_profile(), artifact=make_artifact())
        self.assertTrue(len(response.monthly_cashflow) > 0)
        for row in response.monthly_cashflow:
            self.assertRegex(row.month, r"^\d{4}-\d{2}$")
            self.assertAlmostEqual(row.net, row.inflow - row.outflow, places=2)

    def test_affordability_is_always_present_even_when_not_assessable(self):
        response = analyze_profile(dense_profile(3))
        self.assertIsNotNone(response.affordability)
        self.assertGreaterEqual(response.affordability.indicative_emi_low, 0.0)
        self.assertLessEqual(
            response.affordability.indicative_emi_low, response.affordability.indicative_emi_high
        )


class TestBandAssignment(unittest.TestCase):
    def test_strong_candidate_band(self):
        # All-zero coefficients -> logit == intercept. A strongly positive
        # intercept on the vitality target forces p_default near 0.
        low_risk_artifact = make_artifact(
            intercept=10.0, strong_candidate_max=0.5, high_risk_referral_min=0.9
        )
        response = analyze_profile(full_profile(), artifact=low_risk_artifact)
        self.assertEqual(response.band, Band.STRONG_CANDIDATE)

    def test_high_risk_referral_band(self):
        high_risk_artifact = make_artifact(
            intercept=-10.0, strong_candidate_max=0.1, high_risk_referral_min=0.5
        )
        response = analyze_profile(full_profile(), artifact=high_risk_artifact)
        self.assertEqual(response.band, Band.HIGH_RISK_REFERRAL)


class TestAffordabilityBlock(unittest.TestCase):
    def test_emi_range_is_centered_on_the_twenty_percent_figure(self):
        # income 10,000/mo -> median 10,000 -> base EMI 2,000.
        profile = full_profile(monthly_income=10_000.0)
        response = analyze_profile(profile, artifact=make_artifact())
        low, high = response.affordability.indicative_emi_low, response.affordability.indicative_emi_high
        midpoint = (low + high) / 2
        self.assertAlmostEqual(midpoint, 2_000.0, delta=5.0)
        self.assertLess(low, 2_000.0)
        self.assertGreater(high, 2_000.0)

    def test_months_would_cover_emi_matches_the_feature(self):
        from backend.features.feature_engine import extract_features

        profile = full_profile()
        expected = extract_features(profile).months_would_cover_emi_of_last_24
        response = analyze_profile(profile, artifact=make_artifact())
        self.assertEqual(response.affordability.months_would_cover_emi_of_last_24, expected)


if __name__ == "__main__":
    unittest.main()
