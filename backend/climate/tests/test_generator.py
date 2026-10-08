from pathlib import Path
import json

from backend.climate.generate_rainfall import DATA_DIR, generate


def test_generator_is_deterministic():
    generate()
    before = {path.name: path.read_bytes() for path in DATA_DIR.glob("rainfall_*.csv")}
    generate()
    after = {path.name: path.read_bytes() for path in DATA_DIR.glob("rainfall_*.csv")}
    assert before == after
    assert len(before) == 3


def test_scenario_grid_cells_are_inside_india_on_quarter_degree_grid():
    generate()
    scenarios = json.loads((DATA_DIR / "scenarios.json").read_text(encoding="utf-8"))
    assert len(scenarios) == 3
    for scenario in scenarios:
        lat = scenario["grid_cell"]["lat"]
        lon = scenario["grid_cell"]["lon"]
        assert 68.0 <= lon <= 97.5
        assert 6.5 <= lat <= 37.5
        assert (lat * 4).is_integer()
        assert (lon * 4).is_integer()


def test_generated_csvs_use_lf_line_endings():
    generate()
    csv_files = list(DATA_DIR.glob("rainfall_*.csv"))
    assert len(csv_files) == 3
    for path in csv_files:
        assert b"\r" not in path.read_bytes()
