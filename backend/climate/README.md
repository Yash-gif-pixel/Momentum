# Climate cash-flow impact prototype

This separate package estimates the cash-flow effect of simulated local heavy-rain scenarios for small businesses. It does not connect to the Credify scorecard.

Regenerate its small deterministic fixtures from the repository root:

```bash
python -m backend.climate.generate_rainfall
```

The data is clearly simulated and is not real IMD data. The three scenarios use one 30-day period and one 0.25-degree grid cell each.

## Endpoints

`GET /api/climate/scenarios` lists scenarios and available demo profile IDs:

```bash
curl http://localhost:8000/api/climate/scenarios
```

`GET /api/climate/impact/{profile_id}?scenario_id={scenario_id}` returns the daily rain series and estimated impact:

```bash
curl 'http://localhost:8000/api/climate/impact/lakshmi_vendor_001?scenario_id=heavy_rain_week'
```

`GET /api/climate/portfolio?scenario_id={scenario_id}` summarizes the estimate for every demo borrower in the scenario grid cell:

```bash
curl 'http://localhost:8000/api/climate/portfolio?scenario_id=heavy_rain_week'
```

The portfolio response includes borrower-level estimates, affected-borrower count, aggregate impact and suggested buffers. The real API app mounts these climate routes.

## Assumptions and caveats

- `HEAVY_RAIN_MM_PER_DAY = 64.5` mm, the stated lower bound of the IMD heavy-rain category (64.5–115.5 mm in 24 hours). A day at or above this value is disrupted.
- `DISRUPTION_REVENUE_LOSS_FRACTION = 0.6` assumes 60% of business inflow is lost on a disrupted day. This is a prototype assumption, not an empirical estimate.
- Baseline daily inflow uses `backend.common.cashflow.monthly_business_income`: customer inflows net of reversals, excluding noise, averaged over the latest up to six calendar months and divided by 30.
- The rainfall fixtures are fixed-seed simulated examples, not measured weather, forecasts, or official IMD grids. Local impacts vary by business and location.
- A profile without positive recent business inflow receives zero impact and zero suggested buffer.

This module never reads or changes the credit score.
