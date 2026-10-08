from datetime import date
from pathlib import Path
import json

from backend.climate.impact import calculate_impact, is_disrupted
from backend.generator.schema import Profile, Transaction

ROOT = Path(__file__).resolve().parents[3]


def _profile_with_inflow(amount: float) -> Profile:
    raw = json.loads((ROOT / "data" / "demo_profile_lakshmi.json").read_text())
    profile = Profile.model_validate(raw)
    profile.transactions_seen = []
    if amount:
        profile.transactions_seen.append(Transaction.model_validate({
            "date": date(2025, 6, 15), "direction": "in", "amount": amount,
            "channel": "upi", "counterparty_type": "customer", "category": "sale",
        }))
    return profile


def test_threshold_boundary():
    assert not is_disrupted(64.4)
    assert is_disrupted(64.5)


def test_zero_inflow_has_zero_impact_and_buffer():
    result = calculate_impact(_profile_with_inflow(0), [{"date": "2025-07-01", "rain_mm": 100}])
    assert result["estimated_cashflow_impact_inr"] == 0
    assert result["suggested_resilience_buffer_inr"] == 0
    assert any("zero" in line for line in result["assumptions"])


def test_buffer_rounds_up_to_nearest_thousand():
    profile = _profile_with_inflow(50_000)
    result = calculate_impact(profile, [{"date": "2025-07-01", "rain_mm": 64.5}])
    assert result["suggested_resilience_buffer_inr"] == 1000


def test_impact_percentage_uses_monthly_baseline():
    profile = _profile_with_inflow(30_000)
    result = calculate_impact(profile, [{"date": "2025-07-01", "rain_mm": 64.5}])
    assert round(result["baseline_daily_inflow_inr"], 1) == 166.7
    assert result["impact_pct_of_monthly_inflow"] == 2.0
