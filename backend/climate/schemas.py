"""Response models for the climate impact API."""

from pydantic import BaseModel


class GridCell(BaseModel):
    lat: float
    lon: float


class Scenario(BaseModel):
    scenario_id: str
    label: str
    description: str
    grid_cell: GridCell
    period_start: str
    period_end: str


class ScenariosResponse(BaseModel):
    scenarios: list[Scenario]
    profile_ids: list[str]


class DailyRainfall(BaseModel):
    date: str
    rain_mm: float
    disrupted: bool


class ImpactResponse(BaseModel):
    profile_id: str
    scenario_id: str
    grid_cell: GridCell
    period_start: str
    period_end: str
    daily: list[DailyRainfall]
    disrupted_days: int
    baseline_daily_inflow_inr: float
    estimated_cashflow_impact_inr: float
    impact_pct_of_monthly_inflow: float
    suggested_resilience_buffer_inr: float
    assumptions: list[str]
    affects_credit_score: bool
