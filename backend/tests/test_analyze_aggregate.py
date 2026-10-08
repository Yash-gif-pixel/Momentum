"""Tests for the privacy-minimized submission path.

The load-bearing test here is `TestTheTwoPathsAreEquivalent`: submitting a
demo profile's aggregates by hand must produce a response byte-for-byte
identical to scoring the same profile from its transactions. Anything weaker
(a 200, a plausible-looking score) would pass just as happily if the two
paths had quietly diverged, which is the whole risk of having two of them.
"""

from __future__ import annotations

import json
import unittest

from fastapi.testclient import TestClient

from backend.api.dependencies import DATA_DIR, DEMO_PROFILES
from backend.common.cashflow import (
    is_noise,
    monthly_business_income,
    monthly_gross_cashflow,
)
from backend.common.windows import iter_month_keys, month_key, seen_window
from backend.contract.api_schema import AnalyzeAggregateRequest
from backend.features.feature_engine import extract_features
from backend.features.sufficiency import (
    MIN_TX_PER_MONTH_ASSESSABLE,
    assess_sufficiency,
    assess_sufficiency_from_counts,
)
from backend.generator.schema import Profile
from backend.model.scorecard import analyze_from_aggregates, analyze_profile
from backend.tests.model_helpers import make_artifact


def load_demo(profile_id: str) -> Profile:
    profile = Profile.model_validate(
        json.loads((DATA_DIR / DEMO_PROFILES[profile_id]).read_text())
    )
    # Match what the API does: cache under the frontend-facing id rather than
    # whatever internal id the committed file carries.
    profile.meta.profile_id = profile_id
    return profile


def aggregates_from_profile(profile: Profile) -> AnalyzeAggregateRequest:
    """Build the aggregate request a privacy-conscious caller would send.

    This is deliberately written against the SAME primitives the transaction
    path uses (monthly_business_income, monthly_gross_cashflow, is_noise),
    because that is exactly what a real caller has to replicate on their own
    infrastructure. If those definitions ever drift, the equivalence test
    below fails -- which is the point.
    """
    window = seen_window(profile)
    income = monthly_business_income(profile.transactions_seen, window)
    gross = monthly_gross_cashflow(profile.transactions_seen, window)

    counts = {key: 0 for key in iter_month_keys(window)}
    for tx in profile.transactions_seen:
        if is_noise(tx):
            continue
        key = month_key(tx.date)
        if key in counts:
            counts[key] += 1

    months = [
        {
            "month": key,
            "real_transaction_count": counts[key],
            "business_income": income[key],
            "gross_inflow": gross[key]["inflow"],
            "gross_outflow": gross[key]["outflow"],
        }
        for key in sorted(counts)
    ]

    return AnalyzeAggregateRequest(
        profile_id=profile.meta.profile_id,
        months_available=len(months),
        features=extract_features(profile).as_dict(),
        months=months,
    )


class TestTheTwoPathsAreEquivalent(unittest.TestCase):
    """Same business, same numbers, two submission formats -> same response."""

    def test_every_demo_profile_scores_identically_from_aggregates(self):
        artifact = make_artifact()
        for profile_id in DEMO_PROFILES:
            with self.subTest(profile_id=profile_id):
                profile = load_demo(profile_id)
                from_transactions = analyze_profile(profile, artifact=artifact)
                from_aggregates = analyze_from_aggregates(
                    aggregates_from_profile(profile), artifact=artifact
                )
                self.assertEqual(
                    from_transactions.model_dump(mode="json"),
                    from_aggregates.model_dump(mode="json"),
                )

    def test_equivalence_holds_for_the_real_trained_artifact_too(self):
        # make_artifact() has all-zero coefficients, so it would mask a
        # divergence that only shows up once features actually carry weight.
        # This repeats the comparison through the real model.
        profile = load_demo("lakshmi_vendor_001")
        self.assertEqual(
            analyze_profile(profile).model_dump(mode="json"),
            analyze_from_aggregates(aggregates_from_profile(profile)).model_dump(mode="json"),
        )

    def test_a_gated_profile_is_equivalent_too(self):
        # thin_file_002 is NOT_ASSESSABLE, which takes the other branch of
        # _assemble_response, including the coverage_reason string.
        profile = load_demo("thin_file_002")
        from_transactions = analyze_profile(profile, artifact=make_artifact())
        from_aggregates = analyze_from_aggregates(
            aggregates_from_profile(profile), artifact=make_artifact()
        )
        self.assertEqual(from_transactions.outcome.value, "NOT_ASSESSABLE")
        self.assertEqual(
            from_transactions.model_dump(mode="json"),
            from_aggregates.model_dump(mode="json"),
        )

    def test_the_endpoint_agrees_with_the_demo_profile_endpoint(self):
        # End to end through FastAPI, not just the function, so a serialization
        # difference between the two routes would also be caught.
        from backend.api.main import app

        with TestClient(app) as client:
            profile = load_demo("arjun_kirana_006")
            direct = client.get("/api/profiles/arjun_kirana_006")
            aggregate = client.post(
                "/api/analyze-aggregate",
                json=aggregates_from_profile(profile).model_dump(mode="json"),
            )
            self.assertEqual(direct.status_code, 200)
            self.assertEqual(aggregate.status_code, 200)
            self.assertEqual(direct.json(), aggregate.json())


class TestSufficiencyFromCounts(unittest.TestCase):
    """The parallel gate must agree with the real one, reason strings included."""

    def test_it_matches_assess_sufficiency_on_every_demo_profile(self):
        for profile_id in DEMO_PROFILES:
            with self.subTest(profile_id=profile_id):
                profile = load_demo(profile_id)
                request = aggregates_from_profile(profile)
                counts = {m.month: m.real_transaction_count for m in request.months}
                self.assertEqual(
                    assess_sufficiency_from_counts(counts),
                    assess_sufficiency(profile),
                )

    def test_empty_submission_is_not_assessable_rather_than_an_error(self):
        result = assess_sufficiency_from_counts({})
        self.assertEqual(result.outcome.value, "NOT_ASSESSABLE")
        self.assertEqual(result.months_available, 0)

    def test_density_is_averaged_across_the_window_including_silent_months(self):
        # 12 months, all the activity in one of them. The average is what the
        # gate reads, so this must fail the density bar even though one month
        # looks busy -- same as the transaction path.
        counts = {f"2025-{m:02d}": 0 for m in range(1, 13)}
        counts["2025-06"] = 60
        result = assess_sufficiency_from_counts(counts)
        self.assertLess(60 / 12, MIN_TX_PER_MONTH_ASSESSABLE)
        self.assertEqual(result.outcome.value, "NOT_ASSESSABLE")


class TestAuthenticityAppliesToThisPathToo(unittest.TestCase):
    """Self-reported features are the easier thing to fabricate, so the
    uniformity check matters more here, not less."""

    def _uniform_request(self, cv: float) -> AnalyzeAggregateRequest:
        profile = load_demo("lakshmi_vendor_001")
        request = aggregates_from_profile(profile)
        features = request.features.model_dump()
        features["income_coefficient_of_variation"] = cv
        return AnalyzeAggregateRequest(
            profile_id=request.profile_id,
            months_available=request.months_available,
            features=features,
            months=[m.model_dump() for m in request.months],
        )

    def test_a_hand_set_near_zero_cv_is_flagged(self):
        response = analyze_from_aggregates(
            self._uniform_request(0.001), artifact=make_artifact()
        )
        self.assertIsNotNone(response.authenticity_check)
        self.assertEqual(response.authenticity_check.status, "unusually_uniform")
        self.assertAlmostEqual(response.authenticity_check.observed, 0.001)

    def test_the_same_profiles_real_cv_is_not_flagged(self):
        response = analyze_from_aggregates(
            aggregates_from_profile(load_demo("lakshmi_vendor_001")),
            artifact=make_artifact(),
        )
        self.assertEqual(response.authenticity_check.status, "natural")

    def test_a_flagged_submission_is_still_scored_normally(self):
        # The check annotates; it does not gate. A fabricated-looking
        # submission still gets whatever score its features imply.
        response = analyze_from_aggregates(
            self._uniform_request(0.001), artifact=make_artifact()
        )
        self.assertEqual(response.outcome.value, "SCORED")
        self.assertIsNotNone(response.vitality_score)

    def test_it_is_reachable_through_the_endpoint(self):
        from backend.api.main import app

        with TestClient(app) as client:
            response = client.post(
                "/api/analyze-aggregate",
                json=self._uniform_request(0.001).model_dump(mode="json"),
            )
            self.assertEqual(response.status_code, 200)
            self.assertEqual(
                response.json()["authenticity_check"]["status"], "unusually_uniform"
            )


class TestRequestValidation(unittest.TestCase):
    """Malformed bodies must be 422 from the model's own validation, never 500."""

    def setUp(self):
        from backend.api.main import app

        self.client = TestClient(app)
        self.client.__enter__()
        self.addCleanup(lambda: self.client.__exit__(None, None, None))
        self.base = aggregates_from_profile(load_demo("lakshmi_vendor_001")).model_dump(
            mode="json"
        )

    def _post(self, body) -> int:
        return self.client.post("/api/analyze-aggregate", json=body).status_code

    def test_months_available_disagreeing_with_months_is_422(self):
        body = dict(self.base, months_available=99)
        self.assertEqual(self._post(body), 422)

    def test_a_gap_in_the_month_run_is_422(self):
        # Dropping a middle month would otherwise shorten the window the gate
        # measures and raise the apparent density.
        body = dict(self.base)
        body["months"] = [m for i, m in enumerate(body["months"]) if i != 5]
        body["months_available"] = len(body["months"])
        self.assertEqual(self._post(body), 422)

    def test_a_duplicate_month_is_422(self):
        body = dict(self.base)
        body["months"] = body["months"] + [body["months"][-1]]
        body["months_available"] = len(body["months"])
        self.assertEqual(self._post(body), 422)

    def test_a_malformed_month_key_is_422(self):
        body = dict(self.base)
        body["months"] = [dict(body["months"][0], month="2025-13")]
        body["months_available"] = 1
        self.assertEqual(self._post(body), 422)

    def test_a_negative_transaction_count_is_422(self):
        body = dict(self.base)
        body["months"] = [dict(m) for m in body["months"]]
        body["months"][0]["real_transaction_count"] = -1
        self.assertEqual(self._post(body), 422)

    def test_a_missing_features_block_is_422(self):
        body = {k: v for k, v in self.base.items() if k != "features"}
        self.assertEqual(self._post(body), 422)

    def test_an_empty_submission_is_scored_as_not_assessable_not_rejected(self):
        # Zero months is a legitimate, if degenerate, request -- it must come
        # back as a well-formed NOT_ASSESSABLE response, not a 4xx or a 500.
        body = {
            "profile_id": "empty",
            "months_available": 0,
            "features": {},
            "months": [],
        }
        response = self.client.post("/api/analyze-aggregate", json=body)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["outcome"], "NOT_ASSESSABLE")
        self.assertIsNone(response.json()["vitality_score"])

    def test_omitted_optional_features_default_to_none_not_zero(self):
        # The "None means not computable, never fabricate a zero" convention:
        # a caller who cannot compute year_over_year_change omits it, and that
        # must not be read as "flat".
        request = AnalyzeAggregateRequest(
            profile_id="x",
            months_available=0,
            features={"pct_weeks_with_income": 0.9},
            months=[],
        )
        self.assertIsNone(request.features.year_over_year_change)
        self.assertEqual(request.features.pct_weeks_with_income, 0.9)


class TestTheExistingContractIsUntouched(unittest.TestCase):
    def test_analyze_request_still_takes_transactions(self):
        from backend.contract.api_schema import AnalyzeRequest

        fields = set(AnalyzeRequest.model_fields)
        self.assertEqual(fields, {"profile_id", "transactions", "months_available"})

    def test_both_endpoints_are_advertised(self):
        from backend.api.main import app

        with TestClient(app) as client:
            paths = client.get("/openapi.json").json()["paths"]
            self.assertIn("/api/analyze", paths)
            self.assertIn("/api/analyze-aggregate", paths)


if __name__ == "__main__":
    unittest.main()
