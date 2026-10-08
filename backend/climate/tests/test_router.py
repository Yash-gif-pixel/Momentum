import json
from pathlib import Path

from fastapi import FastAPI
from fastapi.testclient import TestClient

from backend.api.dependencies import get_demo_profiles
from backend.climate import router as climate_router
from backend.climate.impact import calculate_impact
from backend.climate.router import router
from backend.generator.schema import Profile

ROOT = Path(__file__).resolve().parents[3]
DEMO_PROFILE_FILES = {
    "lakshmi_vendor_001": "demo_profile_lakshmi.json",
    "thin_file_002": "demo_profile_thin_file.json",
    "dormancy_gap_003": "demo_profile_dormancy_gap.json",
    "ramesh_carpentry_004": "demo_profile_ramesh_carpentry.json",
    "meera_tailor_005": "demo_profile_meera_tailor.json",
    "arjun_kirana_006": "demo_profile_arjun_kirana.json",
    "uniform_trail_007": "demo_profile_uniform_trail.json",
}


_DEMO_PROFILES = None


def _profiles():
    """Load the committed fixtures once using the API dependency's mapping."""
    global _DEMO_PROFILES
    if _DEMO_PROFILES is None:
        _DEMO_PROFILES = {}
        for profile_id, filename in DEMO_PROFILE_FILES.items():
            path = ROOT / "data" / filename
            profile = Profile.model_validate(json.loads(path.read_text(encoding="utf-8")))
            profile.meta.profile_id = profile_id
            _DEMO_PROFILES[profile_id] = profile
    return _DEMO_PROFILES


def _client():
    app = FastAPI()
    app.include_router(router)
    app.dependency_overrides[get_demo_profiles] = _profiles
    return TestClient(app)


def test_scenarios_endpoint():
    response = _client().get("/api/climate/scenarios")
    assert response.status_code == 200
    body = response.json()
    assert len(body["scenarios"]) == 3
    assert body["profile_ids"] == sorted(body["profile_ids"])


def test_impact_endpoint_and_score_isolation_flag():
    profile_id = next(iter(_profiles()))
    response = _client().get(f"/api/climate/impact/{profile_id}?scenario_id=heavy_rain_week")
    assert response.status_code == 200
    assert len(response.json()["daily"]) == 30
    assert response.json()["affects_credit_score"] is False


def test_unknown_profile_is_404():
    response = _client().get("/api/climate/impact/no_such_profile?scenario_id=normal_monsoon")
    assert response.status_code == 404
    assert "profile_id" in response.json()["detail"]


def test_unknown_scenario_is_404():
    profile_id = next(iter(_profiles()))
    response = _client().get(f"/api/climate/impact/{profile_id}?scenario_id=unknown")
    assert response.status_code == 404
    assert "scenario_id" in response.json()["detail"]


def test_portfolio_totals_sorting_and_heavy_rain_affected_count():
    response = _client().get("/api/climate/portfolio?scenario_id=heavy_rain_week")
    assert response.status_code == 200
    body = response.json()
    borrowers = body["borrowers"]
    assert [b["profile_id"] for b in borrowers] == [b["profile_id"] for b in sorted(
        borrowers, key=lambda b: (not b["exposed"], -b["estimated_cashflow_impact_inr"], b["profile_id"])
    )]
    exposed = [b for b in borrowers if b["exposed"]]
    assert body["borrowers_exposed"] == 3
    assert next(b for b in borrowers if b["profile_id"] == "lakshmi_vendor_001")["exposed"]
    assert all(b["estimated_cashflow_impact_inr"] == 0 for b in borrowers if not b["exposed"])
    assert body["total_estimated_impact_inr"] == round(
        sum(b["estimated_cashflow_impact_inr"] for b in exposed), 2
    )
    assert body["total_suggested_buffer_inr"] == sum(
        b["suggested_resilience_buffer_inr"] for b in exposed
    )
    assert body["borrowers_affected"] == sum(
        b["estimated_cashflow_impact_inr"] > 0 for b in borrowers
    )
    assert body["borrowers_affected"] > 0
    assert body["affects_credit_score"] is False
    assert any("Borrower locations are synthetic demo data" in line for line in body["assumptions"])


def test_every_demo_profile_has_a_valid_synthetic_scenario_location():
    locations = climate_router.BORROWER_LOCATIONS
    assert set(locations) == set(_profiles())
    cells = {tuple(scenario["grid_cell"].values()) for scenario in climate_router._scenarios()}
    assert all(tuple(location["grid_cell"].values()) in cells for location in locations.values())
    assert sum(location["city"] == "Kolkata" for location in locations.values()) == 3
    assert sum(location["city"] == "Mumbai" for location in locations.values()) == 2
    assert sum(location["city"] == "Chennai" for location in locations.values()) == 2


def test_impact_endpoint_matches_calculate_impact_without_schema_changes():
    profile_id = "lakshmi_vendor_001"
    response = _client().get(f"/api/climate/impact/{profile_id}?scenario_id=heavy_rain_week")
    expected = calculate_impact(_profiles()[profile_id], climate_router._rainfall("heavy_rain_week"))
    body = response.json()
    for field, value in expected.items():
        assert body[field] == value
    assert set(body) == {
        "profile_id", "scenario_id", "grid_cell", "period_start", "period_end", "daily",
        "disrupted_days", "baseline_daily_inflow_inr", "estimated_cashflow_impact_inr",
        "impact_pct_of_monthly_inflow", "suggested_resilience_buffer_inr", "assumptions",
        "affects_credit_score",
    }


def test_missing_location_is_not_exposed_and_does_not_crash(monkeypatch):
    locations = dict(climate_router.BORROWER_LOCATIONS)
    locations.pop("lakshmi_vendor_001")
    monkeypatch.setattr(climate_router, "BORROWER_LOCATIONS", locations)
    response = _client().get("/api/climate/portfolio?scenario_id=heavy_rain_week")
    assert response.status_code == 200
    lakshmi = next(b for b in response.json()["borrowers"] if b["profile_id"] == "lakshmi_vendor_001")
    assert lakshmi["city"] == "Unknown"
    assert lakshmi["exposed"] is False
    assert lakshmi["estimated_cashflow_impact_inr"] == 0


def test_normal_monsoon_has_no_affected_borrowers_and_unknown_scenario_is_404():
    response = _client().get("/api/climate/portfolio?scenario_id=normal_monsoon")
    assert response.status_code == 200
    assert response.json()["borrowers_affected"] == 0

    response = _client().get("/api/climate/portfolio?scenario_id=unknown")
    assert response.status_code == 404
    assert "scenario_id" in response.json()["detail"]


def test_portfolio_requires_scenario_id():
    assert _client().get("/api/climate/portfolio").status_code == 422
