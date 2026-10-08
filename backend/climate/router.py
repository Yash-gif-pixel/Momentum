"""HTTP adapter for simulated rainfall cash-flow impact estimates."""

from __future__ import annotations

import csv
import json
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException

from backend.api.dependencies import get_demo_profiles
from backend.generator.schema import Profile
from backend.climate.impact import calculate_impact
from backend.climate.schemas import ClimatePortfolioResponse, ImpactResponse, ScenariosResponse

router = APIRouter(prefix="/api/climate", tags=["climate"])
DATA_DIR = Path(__file__).resolve().parents[2] / "data" / "climate"


def _scenarios() -> list[dict]:
    return json.loads((DATA_DIR / "scenarios.json").read_text(encoding="utf-8"))


def _load_borrower_locations() -> dict[str, dict]:
    return json.loads((DATA_DIR / "borrower_locations.json").read_text(encoding="utf-8"))


BORROWER_LOCATIONS = _load_borrower_locations()


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


@router.get("/portfolio", response_model=ClimatePortfolioResponse)
def get_climate_portfolio(scenario_id: str, profiles: dict[str, Profile] = Depends(get_demo_profiles)) -> dict:
    scenario = next((item for item in _scenarios() if item["scenario_id"] == scenario_id), None)
    if scenario is None:
        raise HTTPException(status_code=404, detail=f"Unknown scenario_id '{scenario_id}'.")

    rainfall = _rainfall(scenario_id)
    borrower_results = []
    assumptions: list[str] = []
    disrupted_days = 0
    for profile_id, profile in profiles.items():
        result = calculate_impact(profile, rainfall)
        disrupted_days = result["disrupted_days"]
        location = BORROWER_LOCATIONS.get(profile_id)
        exposed = bool(location and location.get("grid_cell") == scenario["grid_cell"])
        if exposed:
            assumptions.extend(line for line in result["assumptions"] if line not in assumptions)
        borrower_results.append({
            "profile_id": profile_id,
            "city": location.get("city", "Unknown") if location else "Unknown",
            "exposed": exposed,
            "baseline_daily_inflow_inr": result["baseline_daily_inflow_inr"],
            "estimated_cashflow_impact_inr": result["estimated_cashflow_impact_inr"] if exposed else 0,
            "impact_pct_of_monthly_inflow": result["impact_pct_of_monthly_inflow"] if exposed else 0,
            "suggested_resilience_buffer_inr": result["suggested_resilience_buffer_inr"] if exposed else 0,
        })
    borrower_results.sort(key=lambda borrower: (not borrower["exposed"], -borrower["estimated_cashflow_impact_inr"], borrower["profile_id"]))
    assumptions.append("Borrower locations are synthetic demo data; only borrowers in the scenario's grid cell are treated as exposed.")
    exposed_borrowers = [borrower for borrower in borrower_results if borrower["exposed"]]
    total_impact = round(sum(borrower["estimated_cashflow_impact_inr"] for borrower in exposed_borrowers), 2)
    total_buffer = sum(borrower["suggested_resilience_buffer_inr"] for borrower in exposed_borrowers)
    return {
        "scenario_id": scenario_id,
        "grid_cell": scenario["grid_cell"],
        "period_start": scenario["period_start"],
        "period_end": scenario["period_end"],
        "disrupted_days": disrupted_days,
        "borrowers": borrower_results,
        "borrowers_exposed": len(exposed_borrowers),
        "borrowers_affected": sum(borrower["estimated_cashflow_impact_inr"] > 0 for borrower in exposed_borrowers),
        "total_estimated_impact_inr": total_impact,
        "total_suggested_buffer_inr": total_buffer,
        "assumptions": assumptions,
        "affects_credit_score": False,
    }
