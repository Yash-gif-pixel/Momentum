import json
from pathlib import Path

from fastapi import FastAPI
from fastapi.testclient import TestClient

from backend.api.dependencies import get_demo_profiles
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
