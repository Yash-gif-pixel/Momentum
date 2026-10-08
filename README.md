# Credify — Credit Invisible (TechSurge 2k26, PS-F02)

Credify is a research prototype for MSME credit scoring using alternative
data — specifically simulated Account Aggregator (AA) transaction history —
for small businesses that are "credit invisible" to traditional bureaus.

The repository contains the synthetic data generator, the transaction/profile
schema, the feature-extraction and labeling pipeline, a trained logistic
regression scorecard with plain-language reason codes, a FastAPI backend
serving that scorecard, and a Flutter client. All data is 100% synthetic — no
real bank, GST, Udyam, or bureau data is used anywhere.

**This is decision support, not a lending decision system.** It returns a
score, the reasons behind it, and an honest refusal when the data is too thin.
It is not a regulated entity and is not certified by any account aggregator.

## What makes it different

- **It refuses to answer.** Outcomes are `SCORED` / `LOW_CONFIDENCE` /
  `NOT_ASSESSABLE`, and the gate is on *data sufficiency*, not on how risky
  the business looks. A thin file gets no score rather than a bad one — while
  a risky but well-documented borrower still gets scored (assessable is not
  the same as safe).
- **The explanation is exact, not approximated.** The model is linear, so a
  score decomposes additively into `intercept + each feature's contribution`.
  No SHAP estimation step. This is why logistic regression was chosen over a
  boosted ensemble.
- **Fairness is enforced by a test.** No geographic, demographic or
  merchant-category field can become a feature, and the suite fails if one
  does. `digital_share` / `cash_share` are extracted but structurally
  withheld from the model, so *how* a borrower transacts cannot move a score.

## Quick start

```bash
# 1. environment
python3 -m venv .venv && source .venv/bin/activate    # Windows: .venv\Scripts\activate
pip install -r backend/requirements.txt

# 2. data + model (required on a fresh clone — artifacts are gitignored)
python3 -m backend.generator.generate_dataset
python3 -m backend.scripts.build_feature_table
python3 -m backend.model.train_scorecard
python3 -m backend.model.validate

# 3. backend
uvicorn backend.api.main:app --reload            # http://localhost:8000

# 4. frontend (separate terminal)
cd frontend && flutter pub get && flutter run -d chrome
```

The Flutter app talks to `http://localhost:8000` by default. Override with
`--dart-define=CREDIFY_API_URL=...`, or run against the in-memory fake with
`--dart-define=CREDIFY_USE_MOCK=true` (note: the mock returns no
`score_breakdown`, so the score-decomposition card is hidden in that mode).

Requires Dart SDK ^3.13.3. `google_fonts` fetches Inter at runtime, so the
first load needs network access.

## Pipeline

### 1. Generate the dataset

```bash
python3 -m backend.generator.generate_dataset
```

500+ synthetic MSME borrower profiles (each a simulated AA transaction payload
spanning 30 months) as individual JSON files in `data/generated/` (gitignored
— regenerate anytime). Two reference profiles are committed at
`data/sample_profile.json` and `data/demo_profile_lakshmi.json`.

### 2. Build the feature table

```bash
python3 -m backend.scripts.build_feature_table
```

Extracts 12 features per profile from months 1–24, runs the sufficiency gate,
and derives the held-out label from months 25–30. Of the 12 extracted, **10
are predictive** — `digital_share` and `cash_share` are deliberately excluded
from the model. Writes:

- `data/feature_table.csv` — committed. The only file a model may read.
- `data/labels_holdout.csv` — gitignored. Ground truth, validation only.

### 3. Train and validate

```bash
python3 -m backend.model.train_scorecard
python3 -m backend.model.validate
```

Fits a logistic regression on the `FULL`-gated, labeled population and
calibrates band cutoffs from the validation set's actual probability
distribution. Writes:

- `backend/model/artifacts/scorecard_model.json` — gitignored. Regenerate by
  re-running `train_scorecard.py`.
- `backend/model/artifacts/metrics.json` — committed. AUC, coverage, score
  histogram, band distribution, and a 12-vs-24-month stability check.

```python
from backend.model.scorecard import analyze_profile
response = analyze_profile(profile)  # -> AnalyzeResponse
```

## API

| Method | Path | Purpose |
|---|---|---|
| `GET`  | `/api/health` | Liveness check |
| `POST` | `/api/analyze` | Score a full payload: `{profile_id, transactions, months_available}` |
| `GET`  | `/api/profiles/{profile_id}` | Score a committed demo profile by id |
| `GET`  | `/api/portfolio` | Aggregate metrics, served from the committed `metrics.json` |

A `SCORED` response carries an optional `score_breakdown`: the intercept, every
predictive feature's contribution, the resulting logit, and `p_default`.

**These contributions are additive in log-odds, not in score points.**
`vitality_score` is a percentile rank of `p_default` against a frozen reference
cohort — monotonic but not linear — so "this feature added N points to the
score" would be false. The UI renders the decomposition in log-odds and shows
the `logit → p_default → rank` conversion separately for that reason.

No auth: deliberately out of scope for a prototype on synthetic data, a
production step rather than a hidden feature.

## Frontend

A Flutter app (`frontend/`) with a landing page and four tabs — Consent,
Lender, Borrower, Portfolio — plus light/dark theming.

- **Consent** — pick a demo borrower, authorise a simulated AA consent by
  sliding. Scores are hidden here so the reveal happens on the Lender tab.
- **Lender** — the core demo: run a traditional bureau check (which finds
  nothing), then the Credify check. Shows the score, reason codes, and the
  additive decomposition behind it.
- **Borrower** — the same result in plain language.
- **Portfolio** — aggregate metrics plus a lending-policy cutoff slider:
  drag a score threshold and see how much of the book it would pass. Snapped
  to the histogram's 10-point buckets, and **volume only** — bad rate per
  cutoff needs holdout repayment outcomes this prototype does not expose.

## Tests

```bash
python3 -m unittest discover -s backend/tests -t .   # 212 tests
cd frontend && flutter test                          # 20 tests
```

The backend suite runs on the standard library plus pydantic — no venv
required for the tests themselves (a couple cross-check against scikit-learn
and skip gracefully if it isn't installed). It includes the label-leakage
guard (neither features nor the model may see the held-out window — checked
end to end through `analyze_profile()`, not just at feature extraction) and
the fairness exclusion check.

The Flutter suite covers the API contract, the mock backend, and the
slide-to-authorize gesture — that slide is the only route from Consent into
the rest of the app, so it is tested directly rather than only through the UI.

See `/docs/DATA_SCHEMA.md` for the full schema, business archetypes, health
tiers, noise model, the Shadow-P2M heuristic, the 12 features, the sufficiency
thresholds and their reasoning, the label definition, the fairness exclusion
list, the score formula, band-cutoff calibration, and validation results
(AUC, coverage, and an honestly-reported stability finding).
