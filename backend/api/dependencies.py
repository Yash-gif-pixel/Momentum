"""Startup-loaded state: model artifact, portfolio metrics, and demo profiles.

All three are loaded ONCE, eagerly, when the FastAPI app starts -- not lazily
on the first request, and never re-read per request. Two reasons this matters:

1. A cold load on the first real request would make that request silently
   slower than every one after it, which is exactly the kind of thing a demo
   trips over at the worst moment.
2. If the model (or a demo profile) is missing or malformed, we want
   `uvicorn` to fail immediately at startup with a clear message, not start
   "successfully" and then 500 on the first call that happens to touch it.

`get_artifact()`, `get_metrics()` and `get_demo_profiles()` are plain FastAPI
dependencies -- inject them with `Depends(...)` rather than importing the
module-level singletons directly, so tests can override them (see
backend/tests/test_api.py) without needing a real trained model on disk.
"""

from __future__ import annotations

import json
from pathlib import Path

from backend.generator.schema import Profile
from backend.model.artifact import METRICS_PATH, ScorecardArtifact

DATA_DIR = Path(__file__).resolve().parents[2] / "data"

# Frontend-facing demo profile_id -> committed profile JSON file. Bridges a
# request-shape gap: the frontend skeleton
# (frontend/lib/services/credify_http_service.dart) hardcodes these ids and
# posts only {"profile_id": ...} to /api/analyze, not Y1's full AnalyzeRequest
# shape. GET /api/profiles/{profile_id} (backend/api/main.py) resolves them
# from this cache. Every file here is a dedicated, fixed-seed demo builder in
# generate_dataset.py (build_demo_profile_*) -- never an alias to
# data/sample_profile.json, whose identity is an accident of bulk-generation
# loop order and would silently drift if that loop's logic ever changed.
DEMO_PROFILES: dict[str, str] = {
    "lakshmi_vendor_001": "demo_profile_lakshmi.json",
    "thin_file_002": "demo_profile_thin_file.json",
    "dormancy_gap_003": "demo_profile_dormancy_gap.json",
    "ramesh_carpentry_004": "demo_profile_ramesh_carpentry.json",
    "meera_tailor_005": "demo_profile_meera_tailor.json",
    "arjun_kirana_006": "demo_profile_arjun_kirana.json",
    "uniform_trail_007": "demo_profile_uniform_trail.json",
}

_artifact: ScorecardArtifact | None = None
_metrics: dict | None = None
_demo_profiles: dict[str, Profile] | None = None


def load_state() -> None:
    """Eagerly load the model artifact, metrics.json and demo profiles.
    Call once at startup.

    Raises FileNotFoundError with a clear message if the model hasn't been
    trained yet, metrics.json is missing, or a demo profile's backing file
    is missing or fails to parse/validate -- in every case, at startup, so a
    broken demo file fails `uvicorn` immediately rather than the first
    request that happens to hit it.
    """
    global _artifact, _metrics, _demo_profiles
    _artifact = ScorecardArtifact.load()
    _metrics = _load_metrics(METRICS_PATH)
    _demo_profiles = _load_demo_profiles()


def _load_metrics(path: Path) -> dict:
    if not path.exists():
        raise FileNotFoundError(
            f"{path} not found. Validate the trained model first:\n"
            "    python3 -m backend.model.validate"
        )
    return json.loads(path.read_text())


def _load_demo_profiles() -> dict[str, Profile]:
    profiles: dict[str, Profile] = {}
    for profile_id, filename in DEMO_PROFILES.items():
        path = DATA_DIR / filename
        if not path.exists():
            raise FileNotFoundError(
                f"{path} not found (backing demo profile '{profile_id}'). "
                "Regenerate with: python3 -m backend.generator.generate_dataset"
            )
        profile = Profile.model_validate(json.loads(path.read_text()))
        # Cache under the frontend-facing id, not whatever internal id the
        # committed file happens to carry (e.g. the file's own
        # "demo_lakshmi" vs. the frontend-facing "lakshmi_vendor_001").
        profile.meta.profile_id = profile_id
        profiles[profile_id] = profile
    return profiles


def get_artifact() -> ScorecardArtifact:
    if _artifact is None:
        raise RuntimeError(
            "Model artifact not loaded. load_state() must run at app startup "
            "before any request is served (see main.py's lifespan handler)."
        )
    return _artifact


def get_metrics() -> dict:
    if _metrics is None:
        raise RuntimeError(
            "metrics.json not loaded. load_state() must run at app startup "
            "before any request is served (see main.py's lifespan handler)."
        )
    return _metrics


def get_demo_profiles() -> dict[str, Profile]:
    if _demo_profiles is None:
        raise RuntimeError(
            "Demo profiles not loaded. load_state() must run at app startup "
            "before any request is served (see main.py's lifespan handler)."
        )
    return _demo_profiles
