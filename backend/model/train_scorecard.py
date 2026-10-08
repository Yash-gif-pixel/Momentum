#!/usr/bin/env python3
"""Trains the logistic regression scorecard and saves it as a JSON artifact.

    python3 -m backend.model.train_scorecard

Reads data/feature_table.csv (Y2, committed) joined with data/labels_holdout.csv
(Y2, gitignored -- rebuild with `python3 -m backend.scripts.build_feature_table`
if it is missing). Only rows with sufficiency_outcome == FULL AND a label are
used. Low-Confidence and Not-Assessable profiles never enter training at all --
the same gate that keeps the model from scoring them at inference time
(scorecard.py) keeps them out of the training population here, so the model
never learns from a trail it would then refuse to score.

LEAKAGE SAFETY: this script never reads a held-out (months 25-30) transaction.
The labels file was already derived by Y2's label_engine.py, entirely from the
held-out window, and everything here works off the CSVs it produced -- the
label as a number, not the transactions behind it. See
backend/tests/test_model_leakage.py for the check that proves it.

Fairness: only backend.model.artifact.PREDICTIVE_FEATURES (10 of the 12
features -- digital_share and cash_share are excluded) ever reach the
regression. See artifact.py's module docstring for why.

Pipeline:
  1. Load and join the two CSVs on profile_id; assert every training row is
     FULL and every FULL+labeled profile has exactly 24 months of seen
     history (so months_would_cover_emi_of_last_24 needs no normalization
     within this training population -- see docs/DATA_SCHEMA.md).
  2. Stratified train/test split BY PROFILE (the table is already one row per
     business), fixed seed, recorded in the artifact and in metrics.json.
  3. Standardize (z-score) the 10 predictive features, fit on train only.
  4. Fit LogisticRegression on the TARGET FLIPPED TO VITALITY (1 = no default),
     so a positive coefficient always means "this feature helps this business"
     -- matching the reason-code contribution direction requested in the brief
     literally, with no sign-flipping needed downstream. AUC is still reported
     in the standard "predicting default" framing; see the note below.
  5. Calibrate band cutoffs from the TEST set's predicted default-probability
     distribution (not guessed round numbers) -- see docs/DATA_SCHEMA.md for
     the exact percentiles and the reasoning.
  6. Save everything needed for inference to backend/model/artifacts/scorecard_model.json
     (gitignored -- regenerate by re-running this script).
"""

from __future__ import annotations

import argparse
import csv
from pathlib import Path

from backend.model.artifact import (
    ARTIFACT_PATH,
    PREDICTIVE_FEATURES,
    BandCutoffs,
    ScorecardArtifact,
    now_iso,
)

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_FEATURE_TABLE = REPO_ROOT / "data" / "feature_table.csv"
DEFAULT_LABEL_FILE = REPO_ROOT / "data" / "labels_holdout.csv"

DEFAULT_SEED = 42
DEFAULT_TEST_SIZE = 0.25

# L2 regularization strength, chosen by 5-fold cross-validation ON THE
# TRAINING SPLIT ONLY (never touching the test split) over
# C in {1.0, 0.5, 0.3, 0.2, 0.1, 0.05, 0.02, 0.01}: mean CV AUC peaked at
# C=0.3 (0.9772 +/- 0.0138), with C=1.0 close behind (0.9763) and AUC
# degrading below C=0.1 as regularization starts erasing real signal.
# Deliberately NOT tuned against the test-set AUC -- a single ~127-row test
# split is noisy enough that chasing its AUC would just be overfitting the
# hyperparameter choice to that noise.
DEFAULT_C = 0.3

# Band cutoff percentiles of the TEST set's predicted default probability.
# See docs/DATA_SCHEMA.md "Band cutoffs" for the full reasoning; briefly:
# the base default rate is ~10%, so the top decile of predicted risk is where
# a lender would expect most actual defaults to concentrate if the model is
# any good, and the bottom quartile is a comfortably-sized "clear pass" tier.
STRONG_CANDIDATE_PERCENTILE = 25
HIGH_RISK_REFERRAL_PERCENTILE = 90


def load_training_table(
    feature_table_path: Path, label_file_path: Path
) -> tuple[list[str], list[dict[str, float]], list[int]]:
    """Join the feature table and the label file on profile_id.

    Returns (profile_ids, feature_rows, labels) for every profile that is both
    sufficiency_outcome == FULL in the feature table AND present in the label
    file. Every row is asserted to have exactly 24 months of seen history,
    which is what makes months_would_cover_emi_of_last_24 comparable across
    the training population without normalization (see artifact.py / Y2 docs).
    """
    if not feature_table_path.exists():
        raise SystemExit(
            f"{feature_table_path} not found. Build it first:\n"
            "    python3 -m backend.scripts.build_feature_table"
        )
    if not label_file_path.exists():
        raise SystemExit(
            f"{label_file_path} not found (it is gitignored -- validation-only "
            "ground truth). Build it first:\n"
            "    python3 -m backend.scripts.build_feature_table"
        )

    with feature_table_path.open() as fh:
        feature_table = {row["profile_id"]: row for row in csv.DictReader(fh)}
    with label_file_path.open() as fh:
        labels = {row["profile_id"]: row for row in csv.DictReader(fh)}

    profile_ids: list[str] = []
    feature_rows: list[dict[str, float]] = []
    y: list[int] = []

    skipped_not_full = 0
    for profile_id, label_row in sorted(labels.items()):
        feature_row = feature_table.get(profile_id)
        if feature_row is None:
            raise SystemExit(
                f"{profile_id} has a label but no row in the feature table -- "
                "the two files are out of sync. Rebuild both with "
                "backend.scripts.build_feature_table."
            )
        if feature_row["sufficiency_outcome"] != "FULL":
            # Defensive: in the current dataset every labeled profile is FULL
            # (verified by build_feature_table's own coupling of the two), but
            # this must never silently change. A LOW_CONFIDENCE or
            # NOT_ASSESSABLE profile must never enter training, matching the
            # same gate scorecard.py applies before it will call the model.
            skipped_not_full += 1
            continue

        months_available = int(feature_row["sufficiency_months_available"])
        if months_available != 24:
            raise SystemExit(
                f"{profile_id} is FULL with {months_available} months of seen "
                "history, not 24. The affordability feature's raw count is only "
                "comparable across profiles with the same denominator -- "
                "training must not proceed until this is normalized. See "
                "feature_engine.py's warning on months_would_cover_emi_of_last_24."
            )

        row_values: dict[str, float] = {}
        missing = []
        for name in PREDICTIVE_FEATURES:
            raw = feature_row[name]
            if raw == "":
                missing.append(name)
                continue
            row_values[name] = float(raw)
        if missing:
            raise SystemExit(
                f"{profile_id} is FULL but has null feature(s) {missing}. "
                "FULL profiles are expected to have every predictive feature "
                "populated (verified for the current dataset); refusing to "
                "silently impute."
            )

        profile_ids.append(profile_id)
        feature_rows.append(row_values)
        y.append(int(label_row["label"]))

    if skipped_not_full:
        print(
            f"NOTE: {skipped_not_full} labeled profile(s) were not FULL and "
            "were excluded from training (see the defensive check above)."
        )

    return profile_ids, feature_rows, y


def summarize_percentiles(values: list[float], percentiles: list[int]) -> dict[int, float]:
    ordered = sorted(values)
    n = len(ordered)
    result = {}
    for p in percentiles:
        # Nearest-rank method; fine for a few hundred points and easy to audit.
        rank = max(0, min(n - 1, round(p / 100 * (n - 1))))
        result[p] = ordered[rank]
    return result


def main() -> None:
    # Imported lazily so `python3 -m backend.model.artifact` etc. (used by the
    # dependency-light inference path) never requires numpy/scikit-learn to be
    # importable -- only this offline training script does.
    from sklearn.linear_model import LogisticRegression
    from sklearn.metrics import roc_auc_score
    from sklearn.model_selection import train_test_split
    from sklearn.preprocessing import StandardScaler

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--feature-table", type=Path, default=DEFAULT_FEATURE_TABLE)
    parser.add_argument("--label-file", type=Path, default=DEFAULT_LABEL_FILE)
    parser.add_argument("--artifact-path", type=Path, default=ARTIFACT_PATH)
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
    parser.add_argument("--test-size", type=float, default=DEFAULT_TEST_SIZE)
    parser.add_argument("--C", type=float, default=DEFAULT_C, dest="C")
    args = parser.parse_args()

    profile_ids, feature_rows, y = load_training_table(args.feature_table, args.label_file)
    n = len(profile_ids)
    n_default = sum(y)
    print(f"Loaded {n} FULL, labeled profiles ({n_default} default, {n - n_default} no-default, "
          f"{100 * n_default / n:.1f}% positive)")

    X = [[row[name] for name in PREDICTIVE_FEATURES] for row in feature_rows]

    # Stratified split BY PROFILE. The table is already one row per business,
    # so splitting the row list is splitting by profile_id directly -- there
    # is no risk of the same business's transactions appearing on both sides.
    (
        X_train, X_test,
        y_train, y_test,
        ids_train, ids_test,
    ) = train_test_split(
        X, y, profile_ids,
        test_size=args.test_size,
        random_state=args.seed,
        stratify=y,
    )
    print(f"Split: {len(ids_train)} train / {len(ids_test)} test "
          f"(seed={args.seed}, stratified on label)")
    print(f"  train positive rate: {100 * sum(y_train) / len(y_train):.1f}%")
    print(f"  test  positive rate: {100 * sum(y_test) / len(y_test):.1f}%")

    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)
    X_test_scaled = scaler.transform(X_test)

    # Target flipped to "vitality" (1 = no default) so a positive coefficient
    # always means "this feature helps this business" -- see module docstring.
    y_vitality_train = [1 - label for label in y_train]
    y_vitality_test = [1 - label for label in y_test]

    model = LogisticRegression(max_iter=2000, random_state=args.seed, C=args.C)
    model.fit(X_train_scaled, y_vitality_train)

    p_vitality_test = model.predict_proba(X_test_scaled)[:, 1]
    p_default_test = [1.0 - p for p in p_vitality_test]

    # AUC reported in the standard "predicting default" framing. This is
    # numerically identical to the AUC for predicting vitality -- AUC is
    # invariant under flipping both the label and the score direction -- so
    # reporting it this way is just the more familiar framing, not a
    # different number.
    auc_test = roc_auc_score(y_test, p_default_test)
    p_vitality_train = model.predict_proba(X_train_scaled)[:, 1]
    auc_train = roc_auc_score(y_train, [1.0 - p for p in p_vitality_train])
    print(f"\nAUC (test, predicting default):  {auc_test:.4f}")
    print(f"AUC (train, predicting default): {auc_train:.4f}  (reference only, not the reported metric)")

    # --- Band cutoff calibration -------------------------------------------
    percentiles = summarize_percentiles(
        p_default_test, [10, 25, 50, 75, 90, 95]
    )
    print("\nTest-set predicted default probability, by percentile:")
    for p, v in percentiles.items():
        print(f"  P{p:<3d} {v:.4f}")

    strong_candidate_max = percentiles[STRONG_CANDIDATE_PERCENTILE]
    high_risk_referral_min = percentiles[HIGH_RISK_REFERRAL_PERCENTILE]

    # Empirical check: how well do these cutoffs actually separate the two
    # test-set classes? Printed for the record, not enforced -- the dataset is
    # small enough (127-ish test profiles, ~13 defaults) that this is a sanity
    # read, not a statistically powerful test.
    high_risk_ids = [pid for pid, p in zip(ids_test, p_default_test) if p >= high_risk_referral_min]
    high_risk_defaults = sum(
        1 for pid, label in zip(ids_test, y_test)
        if pid in set(high_risk_ids) and label == 1
    )
    strong_ids = [pid for pid, p in zip(ids_test, p_default_test) if p <= strong_candidate_max]
    strong_defaults = sum(
        1 for pid, label in zip(ids_test, y_test)
        if pid in set(strong_ids) and label == 1
    )
    print(f"\nAt the P{HIGH_RISK_REFERRAL_PERCENTILE} high_risk_referral cutoff "
          f"({high_risk_referral_min:.4f}): {len(high_risk_ids)} of {len(ids_test)} test "
          f"profiles referred, {high_risk_defaults} of them actual defaults "
          f"({100 * high_risk_defaults / max(1, len(high_risk_ids)):.0f}% precision).")
    print(f"At the P{STRONG_CANDIDATE_PERCENTILE} strong_candidate cutoff "
          f"({strong_candidate_max:.4f}): {len(strong_ids)} of {len(ids_test)} test "
          f"profiles passed, {strong_defaults} of them actual defaults "
          f"({100 * strong_defaults / max(1, len(strong_ids)):.0f}% of the 'clear pass' "
          "tier still defaulted).")

    band_cutoffs = BandCutoffs(
        strong_candidate_max=strong_candidate_max,
        high_risk_referral_min=high_risk_referral_min,
        method=(
            f"strong_candidate: predicted default probability at or below the "
            f"P{STRONG_CANDIDATE_PERCENTILE} of the validation set's distribution "
            f"({strong_candidate_max:.4f}). high_risk_referral: at or above the "
            f"P{HIGH_RISK_REFERRAL_PERCENTILE} ({high_risk_referral_min:.4f}), "
            f"chosen because the base default rate is ~10%, so the top decile of "
            f"predicted risk is where a reasonably discriminating model should "
            f"concentrate most actual defaults. manual_review is everything between."
        ),
    )

    coefficients = dict(zip(PREDICTIVE_FEATURES, model.coef_[0].tolist()))
    scaler_mean = dict(zip(PREDICTIVE_FEATURES, scaler.mean_.tolist()))
    scaler_scale = dict(zip(PREDICTIVE_FEATURES, scaler.scale_.tolist()))

    from backend.model.reason_codes import TEMPLATES

    print("\nCoefficients (vitality-target model; positive = helps the business):")
    flipped_signs = []
    for name, coef in sorted(coefficients.items(), key=lambda kv: -abs(kv[1])):
        expected_positive = TEMPLATES[name].higher_is_better
        flipped = (coef >= 0) != expected_positive
        flag = "  <- counter-intuitive sign, see docs/DATA_SCHEMA.md" if flipped else ""
        print(f"  {name:36s} {coef:+.4f}{flag}")
        if flipped:
            flipped_signs.append(name)
    if flipped_signs:
        print(f"\n{len(flipped_signs)} feature(s) fit with a sign that disagrees with "
              f"reason_codes.py's domain expectation ({', '.join(flipped_signs)}) -- "
              "this is diagnosed, not treated as a bug, in docs/DATA_SCHEMA.md "
              "('A real finding: counter-intuitive signs'). reason_codes.py's "
              "coherence filter (is_favorable) prevents these from ever producing "
              "a backwards-reading reason code regardless.")

    artifact = ScorecardArtifact(
        trained_at=now_iso(),
        train_seed=args.seed,
        predictive_features=PREDICTIVE_FEATURES,
        scaler_mean=scaler_mean,
        scaler_scale=scaler_scale,
        coefficients=coefficients,
        intercept=float(model.intercept_[0]),
        band_cutoffs=band_cutoffs,
        train_profile_ids=tuple(ids_train),
        test_profile_ids=tuple(ids_test),
        # Same split band_cutoffs was calibrated from -- see the field's
        # docstring in artifact.py for why score and band deliberately share
        # one reference cohort.
        reference_default_probabilities=tuple(sorted(p_default_test)),
    )
    artifact.save(args.artifact_path)
    print(f"\nSaved artifact -> {args.artifact_path}")
    print("Run `python3 -m backend.model.validate` to score it and write metrics.json.")


if __name__ == "__main__":
    main()
