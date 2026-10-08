"""Pure rainfall-to-cash-flow calculations; this module has no scorecard access."""

from __future__ import annotations

import math
from datetime import date
from types import SimpleNamespace

from backend.common.cashflow import monthly_business_income
from backend.generator.schema import Profile

# IMD "heavy rain" lower bound, 64.5-115.5 mm in 24h.
HEAVY_RAIN_MM_PER_DAY = 64.5
# Assumed share of a day's business inflow lost on a disrupted day (prototype assumption).
DISRUPTION_REVENUE_LOSS_FRACTION = 0.6


def baseline_daily_inflow_inr(profile: Profile) -> float:
    """Average monthly_business_income over up to six recent calendar months, / 30."""
    transactions = profile.transactions_seen
    if not transactions:
        return 0.0
    latest = max(tx.date for tx in transactions)
    end_month = date(latest.year, latest.month, 1)
    start_index = max(0, (end_month.year * 12 + end_month.month - 1) - 5)
    start_month = date(start_index // 12, start_index % 12 + 1, 1)
    # monthly_business_income only needs the start/end fields its window iterator
    # consumes. Keep this package's imports within the explicitly allowed set.
    window = SimpleNamespace(start=start_month, end=latest)
    income = monthly_business_income(transactions, window)
    average_monthly = sum(income.values()) / len(income) if income else 0.0
    return max(0.0, average_monthly / 30.0)


def is_disrupted(rain_mm: float) -> bool:
    return rain_mm >= HEAVY_RAIN_MM_PER_DAY


def calculate_impact(profile: Profile, rainfall: list[dict]) -> dict:
    """Calculate impact metrics from daily {date, rain_mm} records."""
    baseline = baseline_daily_inflow_inr(profile)
    disrupted_days = sum(is_disrupted(float(day["rain_mm"])) for day in rainfall)
    impact = disrupted_days * baseline * DISRUPTION_REVENUE_LOSS_FRACTION if baseline > 0 else 0.0
    monthly_inflow = baseline * 30
    pct = round(impact / monthly_inflow * 100, 1) if monthly_inflow > 0 else 0.0
    buffer = float(math.ceil(impact / 1000.0) * 1000) if impact > 0 else 0.0
    assumptions = [
        "Baseline uses backend.common.cashflow.monthly_business_income: customer business inflows net of reversals, excluding noise; average of the latest up to six calendar months, divided by 30.",
        "Each day at or above 64.5 mm is treated as disrupted; 60% of baseline daily business inflow is assumed lost on each such day.",
        "Rainfall is deterministic simulated scenario data, not observed IMD data; the estimate is an illustrative prototype, not a forecast.",
    ]
    if baseline == 0:
        assumptions.append("No positive business inflow was found in the recent window; estimated impact and resilience buffer are zero.")
    return {
        "daily": [{"date": str(day["date"]), "rain_mm": float(day["rain_mm"]), "disrupted": is_disrupted(float(day["rain_mm"]))} for day in rainfall],
        "disrupted_days": disrupted_days,
        "baseline_daily_inflow_inr": float(baseline),
        "estimated_cashflow_impact_inr": float(impact),
        "impact_pct_of_monthly_inflow": float(pct),
        "suggested_resilience_buffer_inr": buffer,
        "assumptions": assumptions,
    }
