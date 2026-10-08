# Momentum — VISTERA 2026

Momentum is a hackathon prototype for Indian micro-enterprises with three modules. It is a research prototype on synthetic data, decision support, not a lending decision system.

| Module | Purpose | Main folders |
|---|---|---|
| Scam Guard (PS-F01) | Pure-Dart, on-device heuristic warning before payment authorization; warnings do not block payments. | `packages/scam_guard/`, `frontend/lib/features/scam_guard/` |
| Credify Underwriting (PS-F02) | Alternative-data cash-flow scoring with an explicit sufficiency gate and plain-language reasons. | `backend/` except `backend/climate/`, `frontend/` app shell |
| Climate Cash-Flow (PS-F03) | Estimate cash-flow impacts from simulated rainfall scenarios, isolated from the credit score. | `backend/climate/`, `data/climate/`, `frontend/lib/features/climate/` |

All borrower data is synthetic. Climate fixtures are simulated examples, not measured weather or forecasts.

## Quick start

Run from the repository root. A fresh checkout needs generated data and model artifacts before the API can start:

```bash
python3 -m venv .venv && source .venv/bin/activate    # Windows: .venv\Scripts\activate
pip install -r backend/requirements.txt
python3 -m backend.generator.generate_dataset
python3 -m backend.scripts.build_feature_table
python3 -m backend.model.train_scorecard
python3 -m backend.model.validate
uvicorn backend.api.main:app --reload
```

The API uses `http://localhost:8000`. Climate fixture generation is optional and uses:

```bash
python -m backend.climate.generate_rainfall
```

In a separate terminal, start the main Flutter app:

```bash
cd frontend && flutter pub get && flutter run -d chrome
```

`frontend/lib/main.dart` reads `CREDIFY_USE_MOCK` (default `false`) and `CREDIFY_API_URL` (default `http://localhost:8000`). For example:

```bash
flutter run -d chrome --dart-define=CREDIFY_USE_MOCK=true
flutter run -d chrome --dart-define=CREDIFY_API_URL=http://localhost:8000
```

The mock omits `score_breakdown`, so the score-decomposition card is hidden in mock mode.

### Feature previews

Run these from `frontend/`:

```bash
flutter run -d chrome -t lib/features/scam_guard/preview_main.dart
flutter run -d chrome -t lib/features/climate/preview_main.dart
flutter run -d chrome -t lib/features/climate/preview_main.dart --dart-define=CLIMATE_LIVE=true --dart-define=CLIMATE_API_URL=http://localhost:8000
```

The climate preview reads `CLIMATE_LIVE` (default `false`, so it uses its mock service) and `CLIMATE_API_URL` (default `http://localhost:8000`). The Scam Guard preview has no environment defines. `google_fonts` fetches Inter at runtime, so the first frontend load needs network access.

### Scam Guard package

```bash
cd packages/scam_guard
dart pub get
dart test
```

## API

The main FastAPI app exposes these routes:

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/api/health` | Liveness check |
| `POST` | `/api/analyze` | Score a transaction history (`profile_id`, `transactions`, `months_available`) |
| `POST` | `/api/analyze-aggregate` | Score caller-computed aggregates |
| `GET` | `/api/profiles/{profile_id}` | Score a known demo profile by ID |
| `GET` | `/api/portfolio` | Return committed portfolio metrics |
| `GET` | `/api/climate/scenarios` | List rainfall scenarios and demo profile IDs |
| `GET` | `/api/climate/impact/{profile_id}?scenario_id={scenario_id}` | Estimate impact for one profile in a scenario |
| `GET` | `/api/climate/portfolio?scenario_id={scenario_id}` | Summarize estimates for demo profiles in a scenario |

Climate responses set `affects_credit_score` to `false`. The climate tests enforce that isolation. Credify's sufficiency gate returns `NOT_ASSESSABLE` for thin data, and fairness tests guard excluded location and demographic fields from becoming features.

## Running tests

The backend suite uses Python `unittest`:

```bash
python3 -m unittest discover -s backend/tests -t .
```

Run the Flutter app-shell tests:

```bash
cd frontend && flutter test
```

Run Scam Guard package tests:

```bash
cd packages/scam_guard && dart test
```

## More context

See [CONTEXT.md](CONTEXT.md) for the detailed route and SDK contracts, config, design rules, and ownership. See [AGENTS.md](AGENTS.md) for repository instructions. Module references: `backend/api/README.md`, `backend/climate/README.md`, and `packages/scam_guard/README.md`.
