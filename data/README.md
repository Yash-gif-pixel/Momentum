# /data

- `sample_profile.json` — one small, committed example profile (a
  short-history edge case, so it's compact) for reference. Shows the full
  profile JSON shape without needing to run the generator.
- `demo_profile_lakshmi.json` — the hand-tuned demo profile used live in the
  pitch: a thriving `street_food_vendor` with a clean growth curve and a
  clear festival-season spike.
- `demo_profile_thin_file.json` — hand-tuned demo profile: a fixed-seed,
  5-month short-history profile (`NOT_ASSESSABLE`). Backs the frontend's
  `thin_file_002` demo id via `GET /api/profiles/{id}` (see
  `backend/api/README.md`). Deliberately its own dedicated builder, not an
  alias to `sample_profile.json` above — that file's exact identity depends
  on bulk-generation loop order, which a hardcoded frontend id shouldn't.
- `demo_profile_ramesh_carpentry.json` — hand-tuned demo profile: a stable,
  ordinary small trade business. No dedicated "carpentry" archetype exists
  in the generator; `tailor_salon` is used as the closest available fit
  (materials-plus-service, weekly rhythm) — a documented substitution, not
  a silent one. Backs the frontend's `ramesh_carpentry_004` demo id via
  `GET /api/profiles/{id}` (see `backend/api/README.md`).
- `demo_profile_dormancy_gap.json` — hand-tuned demo profile: a failing
  `kirana_store` with a deliberate 60-day dormancy gap carved into the
  middle of its history, for demoing regularity/dry-streak concerns live.
  Backs the frontend's `dormancy_gap_003` demo id.
- `generated/` — **not committed.** Bulk generated data (500+ profiles) is
  gitignored (see `/.gitignore`: `/data/generated/`) because it's large and
  fully reproducible. Regenerate it with:

  ```bash
  pip install -r backend/requirements.txt
  python3 -m backend.generator.generate_dataset
  ```

  This writes one JSON file per profile to `data/generated/`, plus refreshes
  `sample_profile.json`, `demo_profile_lakshmi.json`,
  `demo_profile_thin_file.json`, `demo_profile_ramesh_carpentry.json` and
  `demo_profile_dormancy_gap.json` in this directory. See
  `/docs/DATA_SCHEMA.md` for the full schema, archetype, and health-tier
  documentation.
- `feature_table.csv` — **committed** (it's small, ~105 KB). One row per
  profile: `profile_id`, the 12 features, and the sufficiency-gate outcome.
  **This is the only file a model may read.** Rebuild with:

  ```bash
  python3 -m backend.scripts.build_feature_table
  ```

- `labels_holdout.csv` — **not committed**, gitignored. The held-out
  ground-truth label derived from months 25–30, alongside the generator's
  latent health tier. **Validation only — never a model input.** It is written
  by the same command above, deliberately as a separate file so it cannot be
  joined into the feature table by accident.
