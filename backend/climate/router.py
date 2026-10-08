"""HTTP adapter for simulated rainfall cash-flow impact estimates."""

from __future__ import annotations

import csv
import json
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException

from backend.api.dependencies import get_demo_profiles
from backend.generator.schema import Profile
from backend.climate.impact import calculate_impact
from backend.climate.schemas import ImpactResponse, ScenariosResponse

router = APIRouter(prefix="/api/climate", tags=["climate"])
DATA_DIR = Path(__file__).resolve().parents[2] / "data" / "climate"


def _scenarios() -> list[dict]:
    return json.loads((DATA_DIR / "scenarios.json").read_text(encoding="utf-8"))


def _rainfall(scenario_id: str) -> list[dict]:
    path = DATA_DIR / f"rainfall_{scenario_id}.csv"
    if not path.is_file():
        raise HTTPException(status_code=404, detail=f"Unknown scenario_id '{scenario_id}'.")
    with path.open(newline="", encoding="utf-8") as handle:
        return [{"date": row["date"], "rain_mm": float(row["rain_mm"])} for row in csv.DictReader(handle)]


@router.get("/scenarios", response_model=ScenariosResponse)
def get_scenarios(profiles: dict[str, Profile] = Depends(get_demo_profiles)) -> dict:
    return {"scenarios": _scenarios(), "profile_ids": sorted(profiles)}


@router.get("/impact/{profile_id}", response_model=ImpactResponse)
def get_impact(profile_id: str, scenario_id: str, profiles: dict[str, Profile] = Depends(get_demo_profiles)) -> dict:
    profile = profiles.get(profile_id)
    if profile is None:
        raise HTTPException(status_code=404, detail=f"Unknown profile_id '{profile_id}'.")
    scenario = next((item for item in _scenarios() if item["scenario_id"] == scenario_id), None)
    if scenario is None:
        raise HTTPException(status_code=404, detail=f"Unknown scenario_id '{scenario_id}'.")
    result = calculate_impact(profile, _rainfall(scenario_id))
    return {
        "profile_id": profile_id,
        "scenario_id": scenario_id,
        "grid_cell": scenario["grid_cell"],
        "period_start": scenario["period_start"],
        "period_end": scenario["period_end"],
        **result,
        "affects_credit_score": False,
    }
