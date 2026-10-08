# Credify Frontend — SESSION-LOG.md
# Updated: 2026-09-18

## Agent: Antigravity (Google DeepMind Antigravity IDE)
## Conversation ID: 64555e34-8c0b-4fac-b0ee-2445efc77fcf
## Branch: praneeth/frontend
## Status: Complete (Flutter analyze: 0 issues; flutter test: 15/15 pass; ready for PR)

---

## What was built

A Flutter frontend skeleton for the Credify alternative-credit scoring app
(TechSurge 2k26, PS-F02 "Credit Invisible") under `/frontend/`.

### Architecture

```
frontend/lib/
├── main.dart                        # App shell, theme, nav, disclaimer banner
├── mock_backend.dart                # Mock API (implements CredifyApiService)
├── models/
│   ├── analyze_response.dart        # POST /api/analyze contract model
│   └── portfolio_response.dart      # GET /api/portfolio contract model
├── services/
│   ├── credify_api_service.dart      # Abstract interface (swap-ready)
│   └── credify_http_service.dart     # Real HTTP implementation (not activated)
├── state/
│   └── app_state.dart               # ChangeNotifier state for lender flow + consent
├── screens/
│   ├── lender_screen.dart           # Screen 1: bureau dead-end → Credify score
│   ├── consent_screen.dart          # Screen 2: AA consent flow
│   ├── portfolio_screen.dart        # Screen 3: portfolio metrics + histogram
│   └── borrower_screen.dart         # Screen 4: plain-language borrower view
└── widgets/
    ├── disclaimer_banner.dart        # Persistent banner on all screens
    ├── score_gauge.dart              # Circular vitality gauge (percent_indicator)
    ├── cashflow_chart.dart           # Line chart (fl_chart)
    └── score_histogram_chart.dart   # Bar chart (fl_chart)
```

### Mock API profiles
- `lakshmi_vendor_001` — SCORED, vitality 71.5, strong_candidate (from spec verbatim)
- `thin_file_002` — NOT_ASSESSABLE, thin file (from spec verbatim)
- `dormancy_gap_003` — NOT_ASSESSABLE, constructed per spec requirement
- `ramesh_carpentry_004` — LOW_CONFIDENCE, manual_review

### Mock portfolio numbers are clearly marked as ILLUSTRATIVE PLACEHOLDERS
(will be replaced by live GET /api/portfolio values in a later integration task)

### Decisions made
- Used `provider` (ChangeNotifier) for state — lightweight, no overkill
- `_useMock = true` constant in main.dart is the single toggle to switch to live HTTP
- IndexedStack for tab nav keeps all 4 screens in memory so state persists across tabs
- Disclaimer banner pinned between AppBar and the page body; always visible regardless of scroll position

### Rejected alternatives
- `riverpod` — unnecessary complexity for this phase
- `dio` over `http` — `http` is sufficient and lighter

---

---

## Session 2: Mock alignment with trained model (91.0 score)

### Completed
- In `frontend/lib/mock_backend.dart`: updated `_lakshmi` vitality_score from 71.5 to 91.0 (matching real trained model for `demo_lakshmi`).
- Updated `_lakshmi` reason codes and affordability to be internally consistent with 91.0 score:
  - Strengths: `ontime_bill_payment_rate` (+0.729), `months_would_cover_emi_of_last_24` (+0.549), `trend_last_6_months` (+0.514).
  - Concerns: empty list (strong candidate, 0 concerns).
  - Affordability: `indicative_emi_low: 8989.59`, `indicative_emi_high: 13606.68`, `months_would_cover_emi_of_last_24: 24`.
- In `frontend/lib/services/credify_http_service.dart`: added TODO comment above `getAvailableProfileIds()` noting pending confirmation with backend on exact demo profile IDs in `/data`. Left IDs and `analyzeProfile()` untouched.
- In `frontend/test/credify_test.dart`: updated test assertion from 71.5 to 91.0.
- Verification: `flutter analyze` passed (0 issues), `flutter test` passed (15/15 tests).

### Rejected alternatives
- Did NOT modify `analyzeProfile()` request body or URL in `credify_http_service.dart` — waiting for backend's `GET /api/profiles/{profile_id}` endpoint to be shipped and confirmed.
- Did NOT alter demo profile IDs in `credify_http_service.dart` pending backend confirmation.


---

## Session 3: Live backend wire-up + end-to-end verification

### Branch: integration/e2e-wireup (off main 3695262, merges praneeth/frontend 24dfd27)

### Completed
- `credify_http_service.dart`: `analyzeProfile()` now calls `GET /api/profiles/{id}`
  (`Accept: application/json`) instead of `POST /api/analyze` with only a
  `profile_id` body, which 422'd. Removed the "pending confirmation" TODO; the 4
  ids are final and backed by files in `/data`.
- `main.dart`: live backend is now the default. `_useMock` reads
  `--dart-define=CREDIFY_USE_MOCK=true`; `CREDIFY_API_URL` still overrides the
  `http://localhost:8000` default. (This supersedes Session 1's
  "`_useMock = true`" and "HTTP implementation (not activated)" notes.)
- `portfolio_screen.dart`: the "ILLUSTRATIVE PLACEHOLDER" subtitle is shown only
  with MockBackend; live data is labelled as live.
- `credify_test.dart`: 2 `MockClient` tests pin the call site (GET, URL, Accept
  header, non-2xx throws). Verified the first fails against the old POST code.
- Verified: backend 211 passed; `flutter analyze` 0 issues; `flutter test` 17/17;
  all 4 ids clicked through in Chrome (Consent -> Approve -> Bureau -> Credify)
  against a live uvicorn server.

### Live results (model trained on the committed 521-profile feature table)
- lakshmi_vendor_001 — SCORED 91.0 strong_candidate
- thin_file_002 — NOT_ASSESSABLE (5 months of history)
- dormancy_gap_003 — SCORED 15.0 manual_review
- ramesh_carpentry_004 — SCORED 70.0 manual_review

### Open issues (not fixed here)
- dormancy_gap_003 and ramesh_carpentry_004 are SCORED on the real backend (as
  documented in backend/api/README.md), but MockBackend still has them as
  NOT_ASSESSABLE / LOW_CONFIDENCE. The demo narrative needs to pick one.
- A fresh train from main pulls `data/generated/demo_{thin_file,dormancy_gap,
  ramesh_carpentry}.json` into the training set (521 -> 524 profiles), which moves
  Lakshmi to 93.0, dormancy to 10.0 high_risk_referral, ramesh to 68.0. The committed
  `metrics.json`/`feature_table.csv` predate those demos. Backend fix: exclude
  `demo_*` from `build_feature_table`.
- Reason-code "Weight" renders raw contributions as percentages (e.g. 768%) on
  dormancy_gap_003.
- `pubspec.yaml` requires Dart ^3.13.3, i.e. Flutter >= 3.47.4.

---

## Session 4: Close out Session 3's open issues (same branch, PR #7)

### Completed
- `backend/scripts/build_feature_table.py`: `DEMO_FIXTURE_IDS` (`demo_thin_file`,
  `demo_ramesh_carpentry`, `demo_dormancy_gap`) are skipped in `load_profiles`, so a
  retrain from a fresh `generate_dataset` can no longer pull hand-tuned demo fixtures
  into training. `demo_lakshmi` is deliberately NOT excluded: it is row 522 of the
  committed feature table and the committed model was trained with it, so excluding
  it would change `metrics.json` and Lakshmi's own score.
  Verified: generate -> build_feature_table -> train -> validate gives a byte-identical
  `feature_table.csv` (521 rows) and a `metrics.json` identical to the committed one
  apart from the two run timestamps (not committed). New test
  `TestDemoFixturesExcludedFromTraining`, which fails with the exclusion disabled.
- `lender_screen.dart`: reason-code line showed `contribution * 100` as "Weight: N%".
  `contribution` is an unbounded log-odds term (coefficient x z-score), not a fraction,
  and the API only returns the top 3 per side, so it cannot be normalised to a share
  client-side. Now shows the signed raw value, "Contribution: -7.68", matching the
  backend docs' own wording.
- Verified: backend 212 passed; `flutter analyze` 0 issues; `flutter test` 17/17; all 4
  ids clicked through in Chrome against live uvicorn, no console errors at 1280x1000.
  dormancy_gap_003 now reads +3.99 +0.42 +0.07 / -7.68 -1.75 -1.45 (was 399%...768%).

### Decisions
- dormancy_gap_003 and ramesh_carpentry_004 stay SCORED (demo narrative decision).
  `MockBackend` still has them as NOT_ASSESSABLE / LOW_CONFIDENCE; this only matters
  with `--dart-define=CREDIFY_USE_MOCK=true`.

### Noticed, not fixed
- At a 1280x2000 viewport Flutter logs a transient "RenderFlex overflowed by 51 pixels"
  from the AppBar actions slot (`main.dart` ~line 129). Not seen at 1280x1000.

---

## Session 5: Stop the generator writing demo profiles into the training population

### Branch: fix/generator-demo-out-dir (off main 4e5cee1, after PR #7 merged)

### Completed
- `generate_dataset.py` `main()`: the 4 demo profiles are no longer written to
  `args.out_dir` (`data/generated/`, the population `build_feature_table` globs), only
  to their committed `data/demo_profile_*.json` copies, as `docs/DATA_SCHEMA.md`
  already described. `demo_lakshmi` still enters training via `COMMITTED_SAMPLES`
  (unchanged); it was previously loaded twice and de-duplicated by id.
- Verified from an empty `data/generated/`: 520 files, 0 demo files; feature table
  521 rows, byte-identical; `metrics.json` identical apart from its two run timestamps
  (not committed); committed demo/sample JSON unchanged; live demo scores unchanged
  (91.0 / NOT_ASSESSABLE / 15.0 / 70.0). Backend 212 passed, `flutter analyze` 0
  issues, `flutter test` 17/17.

### Notes
- The generator never clears `out_dir`, so a machine that ran it before this fix still
  has stale `data/generated/demo_*.json`. Delete them (or all of `data/generated/`)
  and regenerate. Session 4's `DEMO_FIXTURE_IDS` guard in `build_feature_table.py`
  (merged in PR #7) already skips the 3 non-Lakshmi ones.
- `build_feature_table.load_profiles`' docstring still says the demo profile also lives
  in the generated dir; left as-is per instruction not to touch that file.
