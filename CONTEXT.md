# Momentum team context

## Stack

- Backend: Python, FastAPI (`fastapi>=0.110`), Pydantic v2 (`pydantic>=2.0,<3.0`), and Uvicorn (`uvicorn>=0.29`). `backend/requirements.txt` does not specify a Python version.
- Frontend: Flutter / Dart, SDK constraint `^3.13.3` (`frontend/pubspec.yaml`). Scam Guard is a pure-Dart package with the same Dart SDK constraint.
- NumPy (`numpy>=1.26`) and scikit-learn (`scikit-learn>=1.4`) are used for offline training and validation. The serving model inference uses standard-library math with a saved JSON artifact.

## Folder ownership

| Owner | Folders and files |
|---|---|
| Yash (lead) | `backend/api/`, `backend/common/`, `backend/contract/`, `backend/features/`, `backend/generator/`, `backend/labels/`, `backend/model/`, `backend/scripts/`, `backend/tests/`, `backend/requirements.txt`, frontend app shell (`frontend/lib/main.dart`, `frontend/lib/screens/`, `frontend/lib/widgets/`, `frontend/lib/models/`, `frontend/lib/services/`, `frontend/lib/state/`, `frontend/lib/theme/`, `frontend/lib/mock_backend.dart`, `frontend/pubspec.yaml`), `data/` except `data/climate/`, root files |
| Mohin | `packages/scam_guard/` |
| Akram | `frontend/lib/features/scam_guard/`, `frontend/test/features/scam_guard/` |
| Shanawaz | `frontend/lib/features/climate/`, `frontend/test/features/climate/` |
| Abhishiek | `backend/climate/`, `data/climate/` |

## Rule

Never edit another person's folder; ask the owner first.

## API routes

The main app is `backend/api/main.py`; it includes the router in `backend/climate/router.py`.

| Method | Path | Query parameters | Purpose |
|---|---|---|---|
| `GET` | `/api/health` | None | Return API liveness status. |
| `POST` | `/api/analyze` | None | Score a submitted transaction history. |
| `POST` | `/api/analyze-aggregate` | None | Score caller-computed aggregates. |
| `GET` | `/api/portfolio` | None | Return portfolio metrics from the committed metrics artifact. |
| `GET` | `/api/profiles/{profile_id}` | None | Score a known demo profile by ID. |
| `GET` | `/api/climate/scenarios` | None | List climate scenarios and available demo profile IDs. |
| `GET` | `/api/climate/impact/{profile_id}` | `scenario_id` (required) | Return daily rainfall and estimated impact for one profile in one scenario. |
| `GET` | `/api/climate/portfolio` | `scenario_id` (required) | Summarize estimated impact for demo profiles in one scenario. |

## Climate API contract

Response fields are defined in `backend/climate/schemas.py`. `GridCell` is `{lat, lon}`. `Scenario` has `scenario_id`, `label`, `description`, `grid_cell`, `period_start`, and `period_end`. `DailyRainfall` has `date`, `rain_mm`, and `disrupted`.

- `GET /api/climate/scenarios` returns `scenarios` (an array of `Scenario`) and `profile_ids` (strings).
- `GET /api/climate/impact/{profile_id}?scenario_id={scenario_id}` returns `profile_id`, `scenario_id`, `grid_cell`, `period_start`, `period_end`, `daily` (an array of `DailyRainfall`), `disrupted_days`, `baseline_daily_inflow_inr`, `estimated_cashflow_impact_inr`, `impact_pct_of_monthly_inflow`, `suggested_resilience_buffer_inr`, `assumptions`, and `affects_credit_score`.
- `GET /api/climate/portfolio?scenario_id={scenario_id}` returns `scenario_id`, `grid_cell`, `period_start`, `period_end`, `disrupted_days`, `borrowers` (objects with `profile_id`, `city`, `exposed`, `baseline_daily_inflow_inr`, `estimated_cashflow_impact_inr`, `impact_pct_of_monthly_inflow`, and `suggested_resilience_buffer_inr`), `borrowers_exposed`, `borrowers_affected`, `total_estimated_impact_inr`, `total_suggested_buffer_inr`, `assumptions`, and `affects_credit_score`. A borrower is exposed when their synthetic home grid cell in `data/climate/borrower_locations.json` equals the scenario's grid cell; these synthetic demo locations are used only inside the climate module. Non-exposed borrowers have zero estimated impact, impact percentage, and suggested buffer. The impact and buffer totals and `borrowers_affected` count exposed borrowers only. Borrowers are sorted exposed first, then by estimated impact descending, then by `profile_id` ascending.

## Scam Guard SDK contract

Public exports from `packages/scam_guard/lib/scam_guard.dart` are `ScamGuard`, `ScamRiskLevel`, `ScamSignal`, `ScamCheckResult`, and `ScamContext`.

`const ScamGuard().check({required String payeeVpa, required double amountInr, String? payeeName, String? note, ScamContext? context})` returns `ScamCheckResult`. Its fields are `level` (`ScamRiskLevel`), `score` (integer capped at 100), `signals` (list of `ScamSignal`), and `elapsed` (`Duration`); `shouldWarn` is true unless level is `low`. Each `ScamSignal` has `code`, `message`, and `weight`. `ScamContext` has optional `isFirstTimePayee` (`bool?`) and `typicalAmountInr` (`double?`).

Signal codes and weights from `packages/scam_guard/lib/src/rules.dart`:

| Signal code | Weight |
|---|---:|
| `INVALID_VPA_FORMAT` | 25 |
| `URGENCY_LANGUAGE` | 20 |
| `KYC_OR_ACCOUNT_BLOCK` | 25 |
| `REFUND_OR_PRIZE_BAIT` | 20 |
| `BRAND_IMPERSONATION_VPA` | 30 |
| `HIGH_DIGIT_HANDLE` | 15 |
| `NAME_VPA_MISMATCH` | 10 |
| `KNOWN_SCAM_VPA` | 60 |
| `FIRST_TIME_PAYEE` | 10 |
| `AMOUNT_FAR_ABOVE_USUAL` | 15 |

Risk levels: low below 30; medium from 30 through 59; high from 60. Weights and thresholds are heuristic demo defaults, not guarantees.

## Frontend contracts

- `frontend/lib/features/scam_guard/scam_warning.dart` defines `WarningLevel { none, caution, danger }`; `ScamWarning` with required `level`, `reasons` (`List<String>`), and `elapsedMs` (`double`); and `ScamChecker`, a named-argument function type requiring `payeeVpa` and `amountInr` with optional `payeeName` and `note`.
- `frontend/lib/features/scam_guard/scam_guard_adapter.dart` provides `scamGuardChecker` with the same parameters as `ScamChecker`, maps SDK low/medium/high to none/caution/danger, signal messages to reasons, and elapsed microseconds to milliseconds. This adapter does not expose SDK `context`.
- `frontend/lib/features/climate/climate_api_service.dart` defines `ClimateApiService.fetchOptions() -> Future<ClimateOptions>` and `fetchImpact(String profileId, String scenarioId) -> Future<ClimateImpact>`, plus `ClimateApiException` with optional `statusCode` and required `message`.
- `ClimateStressCard` (`frontend/lib/features/climate/climate_stress_card.dart`) constructor: `ClimateStressCard({Key? key, required ClimateApiService service, required String profileId, String initialScenarioId = 'heavy_rain_week'})`.

## Ports and config

The backend README and Flutter defaults use port `8000` (`http://localhost:8000`). The Flutter source reads these compile-time defines:

| Define | Read by | Default |
|---|---|---|
| `CREDIFY_USE_MOCK` | `frontend/lib/main.dart` (`bool.fromEnvironment`) | `false` |
| `CREDIFY_API_URL` | `frontend/lib/main.dart` (`String.fromEnvironment`) | `http://localhost:8000` |
| `CLIMATE_LIVE` | `frontend/lib/features/climate/preview_main.dart` (`bool.fromEnvironment`) | `false` |
| `CLIMATE_API_URL` | `frontend/lib/features/climate/preview_main.dart` (`String.fromEnvironment`) | `http://localhost:8000` |

## Core design rules

- Scam Guard warnings never block, delay, or intercept payments.
- Climate outputs have `affects_credit_score: false`; router responses set it to false, and climate isolation tests enforce the invariant.
- Credify returns `NOT_ASSESSABLE` when data fails the sufficiency gate; it does not convert thin data into a low score.
- Location, demographic, and other excluded fields never become credit features; backend fairness tests enforce the exclusions.
- Borrower data is synthetic; climate rainfall and scenarios are simulated, not measured weather or forecasts.

## Branch and PR rules

Start each task with `git status`, `git switch main`, `git pull origin main`, then `git switch -c <type>/<short-name>`. Never commit to `main`; never run `git add .`. The lead reviews PRs before merge.
