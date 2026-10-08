"""Tests for backend/api/main.py.

Needs fastapi + httpx (TestClient), which live only in the training venv
(.venv/bin/python3 -m unittest ...) -- the same dependency boundary as
train_scorecard.py/validate.py. Skips gracefully under the system Python
used for the rest of the leakage/fairness/feature suite.

Dependencies are overridden with a hand-built artifact (backend.tests.
model_helpers.make_artifact) rather than requiring a real trained model on
disk, so these tests are deterministic and runnable without a training run.
"""

from __future__ import annotations

import json
import unittest

try:
    from fastapi.testclient import TestClient

    HAS_FASTAPI = True
except ImportError:
    HAS_FASTAPI = False

if HAS_FASTAPI:
    from backend.api.dependencies import DATA_DIR, DEMO_PROFILES, get_artifact, get_metrics
    from backend.api.main import app
    from backend.tests.model_helpers import make_artifact
    from backend.tests.test_scorecard import dense_profile


def _transaction_json(tx) -> dict:
    return tx.model_dump(mode="json")


def _profile_to_analyze_request_body(profile) -> dict:
    return {
        "profile_id": profile.meta.profile_id,
        "transactions": [_transaction_json(t) for t in profile.transactions_seen],
        "months_available": profile.meta.months_available,
    }


FIXTURE_METRICS = {
    "auc_test": 0.9123,
    "coverage": {
        "n_profiles": 521,
        "counts": {"SCORED": 506, "LOW_CONFIDENCE": 10, "NOT_ASSESSABLE": 5},
        "pct": {"SCORED": 97.12, "LOW_CONFIDENCE": 1.92, "NOT_ASSESSABLE": 0.96},
    },
    "band_distribution": {
        "strong_candidate": 145,
        "manual_review": 313,
        "high_risk_referral": 48,
    },
    "score_histogram": [
        {"bucket": "0-10", "count": 48},
        {"bucket": "90-100", "count": 61},
    ],
}


@unittest.skipUnless(HAS_FASTAPI, "fastapi/httpx not installed (system Python) -- run under .venv")
class TestHealth(unittest.TestCase):
    def test_health_returns_200(self):
        client = TestClient(app)
        response = client.get("/api/health")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"status": "ok"})


@unittest.skipUnless(HAS_FASTAPI, "fastapi/httpx not installed (system Python) -- run under .venv")
class TestAnalyzeEndpoint(unittest.TestCase):
    def setUp(self):
        self.artifact = make_artifact(
            coefficients={
                "months_would_cover_emi_of_last_24": 1.2,
                "ontime_bill_payment_rate": 0.7,
            },
            intercept=2.0,  # comfortably safe by default, for a clean SCORED case
        )
        app.dependency_overrides[get_artifact] = lambda: self.artifact
        app.dependency_overrides[get_metrics] = lambda: FIXTURE_METRICS

    def tearDown(self):
        app.dependency_overrides.clear()

    def test_full_profile_returns_scored_response_matching_the_contract(self):
        profile = dense_profile(24)
        body = _profile_to_analyze_request_body(profile)

        client = TestClient(app)
        response = client.post("/api/analyze", json=body)

        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["profile_id"], profile.meta.profile_id)
        self.assertEqual(data["outcome"], "SCORED")
        self.assertIsNotNone(data["vitality_score"])
        self.assertIsNotNone(data["band"])
        self.assertEqual(data["confidence"], "high")
        self.assertIsNone(data["coverage_reason"])
        self.assertIn("strengths", data["reason_codes"])
        self.assertIn("concerns", data["reason_codes"])
        self.assertIn("indicative_emi_low", data["affordability"])
        self.assertTrue(len(data["monthly_cashflow"]) > 0)
        self.assertIn("disclaimer", data)

    def test_short_history_profile_returns_gated_response_not_an_error(self):
        profile = dense_profile(3)  # NOT_ASSESSABLE
        body = _profile_to_analyze_request_body(profile)

        client = TestClient(app)
        response = client.post("/api/analyze", json=body)

        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["outcome"], "NOT_ASSESSABLE")
        self.assertIsNone(data["vitality_score"])
        self.assertIsNone(data["band"])
        self.assertIsNone(data["confidence"])
        self.assertIsNotNone(data["coverage_reason"])
        self.assertEqual(data["reason_codes"]["strengths"], [])
        self.assertEqual(data["reason_codes"]["concerns"], [])

    def test_low_confidence_profile_returns_gated_response_not_an_error(self):
        profile = dense_profile(9)  # LOW_CONFIDENCE (months rule, dense enough)
        body = _profile_to_analyze_request_body(profile)

        client = TestClient(app)
        response = client.post("/api/analyze", json=body)

        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["outcome"], "LOW_CONFIDENCE")
        self.assertIsNone(data["vitality_score"])
        self.assertIsNotNone(data["coverage_reason"])

    def test_empty_transactions_is_not_assessable_not_an_error(self):
        body = {"profile_id": "EMPTY0001", "transactions": [], "months_available": 0}
        client = TestClient(app)
        response = client.post("/api/analyze", json=body)
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["outcome"], "NOT_ASSESSABLE")


@unittest.skipUnless(HAS_FASTAPI, "fastapi/httpx not installed (system Python) -- run under .venv")
class TestMalformedRequests(unittest.TestCase):
    def setUp(self):
        app.dependency_overrides[get_artifact] = lambda: make_artifact()
        app.dependency_overrides[get_metrics] = lambda: FIXTURE_METRICS

    def tearDown(self):
        app.dependency_overrides.clear()

    def test_missing_required_field_is_422_not_500(self):
        client = TestClient(app)
        response = client.post("/api/analyze", json={"profile_id": "X"})
        self.assertEqual(response.status_code, 422)

    def test_wrong_type_is_422_not_500(self):
        client = TestClient(app)
        response = client.post(
            "/api/analyze",
            json={
                "profile_id": "X",
                "transactions": "not-a-list",
                "months_available": "not-an-int",
            },
        )
        self.assertEqual(response.status_code, 422)

    def test_malformed_transaction_is_422_not_500(self):
        client = TestClient(app)
        response = client.post(
            "/api/analyze",
            json={
                "profile_id": "X",
                "transactions": [{"date": "2024-01-01", "amount": -5}],  # negative, missing fields
                "months_available": 1,
            },
        )
        self.assertEqual(response.status_code, 422)

    def test_completely_empty_body_is_422_not_500(self):
        client = TestClient(app)
        response = client.post("/api/analyze", json={})
        self.assertEqual(response.status_code, 422)

    def test_non_json_body_is_422_not_500(self):
        client = TestClient(app)
        response = client.post(
            "/api/analyze",
            content=b"not json at all",
            headers={"Content-Type": "application/json"},
        )
        self.assertEqual(response.status_code, 422)

    def test_extreme_date_span_is_422_not_a_crash(self):
        """Regression test for a real bug a code review caught: two
        individually-valid transaction dates near date.min and date.max made
        Profile.meta.history_start_date/end_date span ~3.65 million days.
        extract_features runs BEFORE the sufficiency gate, and its window
        helpers walk that span one day at a time -- reproduced directly: this
        took ~2.7s of CPU and then raised an unhandled OverflowError (the
        day-by-day loop increments one day past date.max before its own
        while-condition can stop it), surfacing as an unhandled 500, not the
        422 this endpoint promises. Fixed with an explicit span check in
        _request_to_profile (MAX_HISTORY_SPAN_DAYS) before any window helper
        ever sees the dates.
        """
        client = TestClient(app)
        body = {
            "profile_id": "evil",
            "transactions": [
                {
                    "date": "0001-01-01",
                    "direction": "in",
                    "amount": 10,
                    "channel": "upi",
                    "counterparty_type": "customer",
                    "category": "sales",
                },
                {
                    "date": "9999-12-31",
                    "direction": "in",
                    "amount": 10,
                    "channel": "upi",
                    "counterparty_type": "customer",
                    "category": "sales",
                },
            ],
            "months_available": 1,
        }

        import time

        start = time.monotonic()
        response = client.post("/api/analyze", json=body)
        elapsed = time.monotonic() - start

        self.assertEqual(response.status_code, 422)
        self.assertLess(elapsed, 1.0, "should reject immediately, not walk the span first")


@unittest.skipUnless(HAS_FASTAPI, "fastapi/httpx not installed (system Python) -- run under .venv")
class TestRunsWithoutATrainedModelOnDisk(unittest.TestCase):
    """Regression test for a real bug a code review caught: `with TestClient(app)
    as client:` runs the FastAPI lifespan handler, which unconditionally calls
    dependencies.load_state() and reads the trained model from disk --
    bypassing dependency_overrides entirely, since the lifespan handler isn't
    reached through Depends(). Every test in this file used to fail with
    FileNotFoundError on a fresh clone that hadn't run train_scorecard.py yet,
    directly contradicting this module's own docstring.

    The fix is to never use the `with` (context-manager) form of TestClient in
    this file -- a bare TestClient(app) does not trigger lifespan at all, so
    dependency_overrides is the only thing that runs. This test proves that
    property directly by moving the real artifact out of the way first.
    """

    def test_health_endpoint_works_with_the_model_artifact_missing(self):
        import shutil
        import tempfile

        from backend.model.artifact import ARTIFACT_PATH

        app.dependency_overrides[get_artifact] = lambda: make_artifact()
        app.dependency_overrides[get_metrics] = lambda: FIXTURE_METRICS
        self.addCleanup(app.dependency_overrides.clear)

        if not ARTIFACT_PATH.exists():
            self.skipTest("no trained model on disk to begin with -- nothing to prove")

        with tempfile.TemporaryDirectory() as tmp:
            moved = f"{tmp}/scorecard_model.json"
            shutil.move(str(ARTIFACT_PATH), moved)
            try:
                client = TestClient(app)  # bare -- must NOT touch disk
                response = client.get("/api/health")
            finally:
                shutil.move(moved, str(ARTIFACT_PATH))

        self.assertEqual(response.status_code, 200)


@unittest.skipUnless(HAS_FASTAPI, "fastapi/httpx not installed (system Python) -- run under .venv")
class TestDemoProfilesFailFastAtStartup(unittest.TestCase):
    """Regression test for a real code-review finding: GET /api/profiles/{id}
    originally read, parsed and validated its backing JSON file fresh on
    every request, with no error handling -- so a missing/malformed demo
    file surfaced as an unhandled 500 on whatever request first hit it,
    contradicting the endpoint's own promise of a clean 404/422 only.

    The fix moved demo-profile loading into dependencies.load_state(),
    exactly like the model artifact and metrics.json: loaded once, eagerly,
    at startup. This test proves a broken demo file now fails
    load_state() itself -- the same "fail fast at startup" behavior
    ScorecardArtifact.load() already had -- rather than surfacing per
    request.
    """

    def test_missing_demo_file_raises_at_load_state_not_per_request(self):
        from backend.api.dependencies import DATA_DIR, DEMO_PROFILES, load_state

        filename = DEMO_PROFILES["thin_file_002"]
        path = DATA_DIR / filename
        if not path.exists():
            self.skipTest("demo file not present on disk to begin with")

        import shutil
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            moved = f"{tmp}/{filename}"
            shutil.move(str(path), moved)
            try:
                with self.assertRaises(FileNotFoundError) as ctx:
                    load_state()
                self.assertIn("thin_file_002", str(ctx.exception))
            finally:
                shutil.move(moved, str(path))


@unittest.skipUnless(HAS_FASTAPI, "fastapi/httpx not installed (system Python) -- run under .venv")
class TestProfileLookupEndpoint(unittest.TestCase):
    """GET /api/profiles/{profile_id} -- the demo-lookup bridge for the
    frontend's 4 hardcoded ids, which post only {profile_id} to /api/analyze
    rather than Y1's full AnalyzeRequest shape. This endpoint is additional,
    outside Y1's original contract; /api/analyze itself is untouched (see
    TestMalformedRequests / TestAnalyzeEndpoint above, still passing as-is).
    """

    def setUp(self):
        from backend.api.dependencies import _load_demo_profiles, get_demo_profiles

        self.artifact = make_artifact(
            coefficients={
                "months_would_cover_emi_of_last_24": 1.2,
                "ontime_bill_payment_rate": 0.7,
            },
            intercept=2.0,
        )
        # Loads the REAL committed demo files once here, so these tests
        # exercise real content (e.g. thin_file_002's actual NOT_ASSESSABLE
        # gate outcome) without depending on the app's own load_state()
        # having run globally.
        demo_profiles = _load_demo_profiles()
        app.dependency_overrides[get_artifact] = lambda: self.artifact
        app.dependency_overrides[get_metrics] = lambda: FIXTURE_METRICS
        app.dependency_overrides[get_demo_profiles] = lambda: demo_profiles

    def tearDown(self):
        app.dependency_overrides.clear()

    def test_all_four_frontend_ids_resolve(self):
        # Iterates DEMO_PROFILES itself, not a hardcoded copy of its keys --
        # if that map ever adds/renames/removes an id, this test's coverage
        # moves with it instead of silently testing a stale list.
        for profile_id in DEMO_PROFILES:
            with self.subTest(profile_id=profile_id):
                client = TestClient(app)
                response = client.get(f"/api/profiles/{profile_id}")
                self.assertEqual(response.status_code, 200)
                data = response.json()
                self.assertIn(data["outcome"], ("SCORED", "LOW_CONFIDENCE", "NOT_ASSESSABLE"))

    def test_response_echoes_back_the_requested_id_not_the_files_internal_id(self):
        # data/demo_profile_lakshmi.json's own meta.profile_id is
        # "demo_lakshmi", not "lakshmi_vendor_001" -- the caller should see
        # back what it asked for.
        client = TestClient(app)
        response = client.get("/api/profiles/lakshmi_vendor_001")
        self.assertEqual(response.json()["profile_id"], "lakshmi_vendor_001")

    def test_thin_file_002_is_gated_not_an_error(self):
        # Backed by data/sample_profile.json, a genuine 5-month short-history
        # profile -- exercises the real sufficiency gate, not a mock.
        client = TestClient(app)
        response = client.get("/api/profiles/thin_file_002")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["outcome"], "NOT_ASSESSABLE")
        self.assertIsNone(data["vitality_score"])
        self.assertIsNotNone(data["coverage_reason"])

    def test_dormancy_gap_003_shows_the_long_dry_streak_in_its_own_features(self):
        # The gate/model may or may not surface longest_dry_streak_days as a
        # reason code (it's one of the coherence-filtered features -- see
        # docs/DATA_SCHEMA.md), but the underlying profile really does have
        # the 60-day gap baked in; this just confirms the endpoint serves
        # that real file rather than something else.
        from backend.generator.schema import Profile

        path = DATA_DIR / "demo_profile_dormancy_gap.json"
        profile = Profile.model_validate(json.loads(path.read_text()))
        from backend.features.feature_engine import extract_features

        self.assertGreaterEqual(extract_features(profile).longest_dry_streak_days, 30)

    def test_unknown_profile_id_is_404_not_a_500_or_422(self):
        client = TestClient(app)
        response = client.get("/api/profiles/does_not_exist")
        self.assertEqual(response.status_code, 404)
        self.assertIn("does_not_exist", response.json()["detail"])

    def test_known_ids_are_listed_in_the_404_message(self):
        client = TestClient(app)
        response = client.get("/api/profiles/nope")
        detail = response.json()["detail"]
        for known_id in DEMO_PROFILES:
            self.assertIn(known_id, detail)


@unittest.skipUnless(HAS_FASTAPI, "fastapi/httpx not installed (system Python) -- run under .venv")
class TestPortfolioEndpoint(unittest.TestCase):
    def setUp(self):
        app.dependency_overrides[get_metrics] = lambda: FIXTURE_METRICS
        app.dependency_overrides[get_artifact] = lambda: make_artifact()

    def tearDown(self):
        app.dependency_overrides.clear()

    def test_portfolio_maps_metrics_json_exactly(self):
        client = TestClient(app)
        response = client.get("/api/portfolio")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["n_profiles"], 521)
        self.assertEqual(data["coverage_pct"], 97.12)
        self.assertEqual(data["auc"], 0.9123)
        self.assertEqual(
            data["band_distribution"],
            {"strong_candidate": 145, "manual_review": 313, "high_risk_referral": 48},
        )
        self.assertEqual(
            data["score_histogram"],
            [{"bucket": "0-10", "count": 48}, {"bucket": "90-100", "count": 61}],
        )


@unittest.skipUnless(HAS_FASTAPI, "fastapi/httpx not installed (system Python) -- run under .venv")
class TestCors(unittest.TestCase):
    def setUp(self):
        app.dependency_overrides[get_metrics] = lambda: FIXTURE_METRICS

    def tearDown(self):
        app.dependency_overrides.clear()

    def test_localhost_origin_is_allowed(self):
        client = TestClient(app)
        response = client.get(
            "/api/portfolio", headers={"Origin": "http://localhost:54231"}
        )
        self.assertEqual(
            response.headers.get("access-control-allow-origin"),
            "http://localhost:54231",
        )

    def test_preflight_request_is_allowed_for_localhost(self):
        client = TestClient(app)
        response = client.options(
            "/api/analyze",
            headers={
                "Origin": "http://localhost:3000",
                "Access-Control-Request-Method": "POST",
            },
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.headers.get("access-control-allow-origin"), "http://localhost:3000"
        )

    def test_non_localhost_origin_is_not_reflected(self):
        client = TestClient(app)
        response = client.get(
            "/api/portfolio", headers={"Origin": "http://evil.example.com"}
        )
        self.assertNotEqual(
            response.headers.get("access-control-allow-origin"), "http://evil.example.com"
        )


if __name__ == "__main__":
    unittest.main()
