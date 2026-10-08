from pathlib import Path

from backend.climate.generate_rainfall import DATA_DIR, generate


def test_generator_is_deterministic():
    generate()
    before = {path.name: path.read_bytes() for path in DATA_DIR.glob("rainfall_*.csv")}
    generate()
    after = {path.name: path.read_bytes() for path in DATA_DIR.glob("rainfall_*.csv")}
    assert before == after
    assert len(before) == 3
