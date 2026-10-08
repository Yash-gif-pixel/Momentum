import ast
from pathlib import Path

CLIMATE_DIR = Path(__file__).resolve().parents[1]
FORBIDDEN = ("backend.model", "backend.features", "backend.labels")


def test_climate_has_no_forbidden_imports():
    for path in CLIMATE_DIR.rglob("*.py"):
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        for node in ast.walk(tree):
            names = []
            if isinstance(node, ast.Import):
                names.extend(alias.name for alias in node.names)
            elif isinstance(node, ast.ImportFrom) and node.module:
                names.append(node.module)
            for name in names:
                assert not any(name == prefix or name.startswith(prefix + ".") for prefix in FORBIDDEN), (
                    f"Forbidden import {name!r} in {path}"
                )
