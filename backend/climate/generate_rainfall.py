"""Generate small, deterministic SIMULATED rainfall fixtures (not IMD data)."""

from __future__ import annotations

import csv
import json
import random
from datetime import date, timedelta
from pathlib import Path

DATA_DIR = Path(__file__).resolve().parents[2] / "data" / "climate"
PERIOD_START = date(2025, 7, 1)
DAYS = 30
SEED = 20250701
SCENARIOS = (
    ("normal_monsoon", "Normal monsoon", "Simulated ordinary monsoon rainfall over 30 days near Mumbai.", 19.0, (19.0, 72.75)),
    ("heavy_rain_week", "Heavy rain week", "Simulated heavy rain on several days in one week near Kolkata.", 22.0, (22.5, 88.25)),
    ("flash_flood", "Flash flood", "Simulated intense short-duration rainfall event near Chennai.", 13.0, (13.0, 80.25)),
)


def generate() -> None:
    """Write three deterministic 30-day CSVs and their scenario metadata."""
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    rng = random.Random(SEED)
    scenarios = []
    for scenario_id, label, description, base, cell in SCENARIOS:
        rows = []
        for offset in range(DAYS):
            day = PERIOD_START + timedelta(days=offset)
            rain = round(max(0.0, rng.gauss(base, base * 0.55)), 1)
            if scenario_id == "heavy_rain_week" and 10 <= offset < 17:
                rain = round(rng.uniform(65.0, 110.0), 1)
            elif scenario_id == "flash_flood" and offset == 14:
                rain = 142.0
            rows.append({"date": day.isoformat(), "lat": cell[0], "lon": cell[1], "rain_mm": rain})
        with (DATA_DIR / f"rainfall_{scenario_id}.csv").open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=["date", "lat", "lon", "rain_mm"], lineterminator="\n")
            writer.writeheader()
            writer.writerows(rows)
        scenarios.append({
            "scenario_id": scenario_id,
            "label": label,
            "description": description + " Rain values are simulated, not observed IMD data.",
            "grid_cell": {"lat": cell[0], "lon": cell[1]},
            "period_start": PERIOD_START.isoformat(),
            "period_end": (PERIOD_START + timedelta(days=DAYS - 1)).isoformat(),
        })
    (DATA_DIR / "scenarios.json").write_text(json.dumps(scenarios, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    generate()
