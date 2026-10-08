from fastapi.testclient import TestClient

from backend.api.main import app


def test_climate_routes_are_mounted_on_live_app():
    with TestClient(app) as client:
        scenarios = client.get("/api/climate/scenarios")
        assert scenarios.status_code == 200
        assert len(scenarios.json()["scenarios"]) == 3

        impact = client.get(
            "/api/climate/impact/lakshmi_vendor_001?scenario_id=heavy_rain_week"
        )
        assert impact.status_code == 200
        assert impact.json()["affects_credit_score"] is False

        assert client.get("/api/health").status_code == 200
