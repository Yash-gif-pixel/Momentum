#!/usr/bin/env python3
"""Validates the trained scorecard and writes the committed metrics.json summary.

    python3 -m backend.model.validate

Everything here is read-only with respect to the model: it loads the artifact
train_scorecard.py already saved and evaluates it. Nothing is refit.

Reports, all landing in backend/model/artifacts/metrics.json (the one file in
that directory that IS committed):

  - AUC on the artifact's saved TEST split (never the train split)
  - Coverage: % of all profiles that would receive SCORED / LOW_CONFIDENCE /
    NOT_ASSESSABLE. This is entirely gate-driven (Y2's sufficiency_outcome
    column in data/feature_table.csv) -- the model has no say in it, so this
    is the single source of truth for coverage, not a model-side estimate.
  - Score histogram across every FULL profile (not just the test split -- a
    portfolio view of what the deployed model would actually produce).
  - Band distribution under the trained cutoffs.
  - A 12-vs-24-month stability check on a sample of profiles: are scores
    reasonably close when a business's history is cut down to its first 12
    months? Reported honestly, including where it is NOT stable and why.

AUC here is computed by a small pure-Python rank-sum implementation rather
than scikit-learn's, matching this module's dependency-light inference path
(only train_scorecard.py, which actually fits the model, needs the sklearn/
numpy venv). The result is checked against sklearn in
backend/tests/test_model_validate.py.
"""

from __future__ import annotations

import csv
import json
import random
from dataclasses import dataclass
from datetime import timedelta
from pathlib import Path

from backend.common.windows import seen_window
from backend.features.feature_engine import extract_features
from backend.generator.generate_dataset import add_months
from backend.generator.schema import Profile, SplitInfo
from backend.model.artifact import (
    METRICS_PATH,
    PREDICTIVE_FEATURES,
    ScorecardArtifact,
    now_iso,
    predict_default_probability,
    vitality_score_from_default_probability,
)
from backend.model.reason_codes import rank_reason_codes

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_FEATURE_TABLE = REPO_ROOT / "data" / "feature_table.csv"
DEFAULT_LABEL_FILE = REPO_ROOT / "data" / "labels_holdout.csv"
DEFAULT_GENERATED_DIR = REPO_ROOT / "data" / "generated"
COMMITTED_SAMPLES_DIR = REPO_ROOT / "data"

HISTOGRAM_BUCKET_WIDTH = 10  # 10 buckets across the 0-100 score range
STABILITY_CHECK_N = 25
STABILITY_CHECK_SEED = 7
STABILITY_CHECK_MONTHS = 12
STABILITY_CHECK_SWING_THRESHOLD = 20  # vitality-score points


def roc_auc(y_true: list[int], y_score: list[float]) -> float:
    """AUC via the rank-sum (Mann-Whitney U) formula. No numpy/sklearn needed.

    AUC = (sum of ranks among positive-class scores - n_pos*(n_pos+1)/2)
          / (n_pos * n_neg)
    Tied scores share the average of the ranks they span.
    """
    n = len(y_score)
    order = sorted(range(n), key=lambda i: y_score[i])
    ranks = [0.0] * n
    i = 0
    while i < n:
        j = i
        while j < n and y_score[order[j]] == y_score[order[i]]:
            j += 1
        avg_rank = (i + j + 1) / 2.0  # 1-indexed rank, averaged across the tie
        for k in range(i, j):
            ranks[order[k]] = avg_rank
        i = j

    n_pos = sum(y_true)
    n_neg = n - n_pos
    if n_pos == 0 or n_neg == 0:
        raise ValueError("roc_auc requires both classes to be present")
    sum_ranks_pos = sum(r for r, y in zip(ranks, y_true) if y == 1)
    return (sum_ranks_pos - n_pos * (n_pos + 1) / 2.0) / (n_pos * n_neg)


def load_feature_table(path: Path) -> dict[str, dict]:
    with path.open() as fh:
        return {row["profile_id"]: row for row in csv.DictReader(fh)}


def load_labels(path: Path) -> dict[str, dict]:
    with path.open() as fh:
        return {row["profile_id"]: row for row in csv.DictReader(fh)}


def feature_values_from_row(row: dict) -> dict[str, float | None]:
    return {
        name: (float(row[name]) if row[name] != "" else None) for name in PREDICTIVE_FEATURES
    }


def compute_test_auc(
    artifact: ScorecardArtifact, feature_table: dict[str, dict], labels: dict[str, dict]
) -> tuple[float, int]:
    y_true = []
    p_default = []
    for profile_id in artifact.test_profile_ids:
        row = feature_table[profile_id]
        fv = feature_values_from_row(row)
        p_default.append(predict_default_probability(artifact, fv))
        y_true.append(int(labels[profile_id]["label"]))
    return roc_auc(y_true, p_default), len(y_true)


def compute_coverage(feature_table: dict[str, dict]) -> dict:
    counts = {"SCORED": 0, "LOW_CONFIDENCE": 0, "NOT_ASSESSABLE": 0}
    for row in feature_table.values():
        outcome = row["sufficiency_outcome"]
        key = "SCORED" if outcome == "FULL" else outcome
        counts[key] += 1
    total = sum(counts.values())
    return {
        "n_profiles": total,
        "counts": counts,
        "pct": {k: round(100 * v / total, 2) for k, v in counts.items()},
    }


@dataclass
class PortfolioMetrics:
    """Everything computable in a single pass over the FULL cohort.

    score_histogram, band_distribution and reason_code_frequency were
    previously three independent O(n) passes over the same rows, each
    re-deriving feature_values_from_row and re-scoring the profile. One pass
    computes all three, since they need exactly the same per-row work.
    """

    scores: list[float]
    histogram: list[dict]
    band_distribution: dict[str, int]
    reason_code_frequency: dict[str, int]


def compute_portfolio_metrics(
    artifact: ScorecardArtifact, feature_table: dict[str, dict]
) -> PortfolioMetrics:
    scores: list[float] = []
    band_distribution = {"strong_candidate": 0, "manual_review": 0, "high_risk_referral": 0}
    reason_code_frequency = {name: 0 for name in PREDICTIVE_FEATURES}

    for row in feature_table.values():
        if row["sufficiency_outcome"] != "FULL":
            continue
        fv = feature_values_from_row(row)
        p_default = predict_default_probability(artifact, fv)

        scores.append(vitality_score_from_default_probability(artifact, p_default))
        band_distribution[artifact.band_cutoffs.band_for(p_default)] += 1

        strengths, concerns = rank_reason_codes(artifact, fv)
        for r in strengths + concerns:
            reason_code_frequency[r.feature] += 1

    histogram = []
    for low in range(0, 100, HISTOGRAM_BUCKET_WIDTH):
        high = low + HISTOGRAM_BUCKET_WIDTH
        label = f"{low}-{high}"
        count = sum(1 for s in scores if low <= s < high or (high == 100 and s == 100))
        histogram.append({"bucket": label, "count": count})

    return PortfolioMetrics(
        scores=scores,
        histogram=histogram,
        band_distribution=band_distribution,
        reason_code_frequency=reason_code_frequency,
    )


def _find_profile_json(profile_id: str) -> Path | None:
    """Locate a profile's JSON file by id.

    data/generated/ names every file after its own profile_id (including the
    two profiles that also have a committed copy under a different filename
    -- e.g. MSME0003.json there is the same profile as data/sample_profile.json),
    so that directory alone covers every id. The two committed files are
    checked as a fallback only for the unusual case where data/generated/ has
    been deleted without regenerating it.
    """
    direct = DEFAULT_GENERATED_DIR / f"{profile_id}.json"
    if direct.exists():
        return direct

    for name in ("sample_profile.json", "demo_profile_lakshmi.json"):
        path = COMMITTED_SAMPLES_DIR / name
        if not path.exists():
            continue
        data = json.loads(path.read_text())
        if data.get("meta", {}).get("profile_id") == profile_id:
            return path
    return None


def truncate_seen_window(profile: Profile, months: int) -> Profile:
    """A copy of `profile` with only its first `months` months of seen history.

    Used ONLY by the stability check below. This deliberately bypasses the
    sufficiency gate -- assess_sufficiency would classify a 12-month profile
    as LOW_CONFIDENCE and a real inference call would never reach the model
    at all. The point here is to measure the underlying model's sensitivity
    to less history, not to claim a 12-month profile would be scored in
    production. See the printed report for that caveat restated plainly.
    """
    start = profile.meta.history_start_date
    new_end = add_months(start, months) - timedelta(days=1)
    truncated_tx = [t for t in profile.transactions_seen if t.date <= new_end]
    new_meta = profile.meta.model_copy(
        update={
            "history_end_date": new_end,
            "months_available": months,
            "split": SplitInfo(seen_months=months, holdout_months=0, split_date=None),
        }
    )
    return profile.model_copy(
        update={"meta": new_meta, "transactions_seen": truncated_tx, "transactions_holdout": []}
    )


def run_stability_check(artifact: ScorecardArtifact) -> dict:
    rng = random.Random(STABILITY_CHECK_SEED)
    candidates = list(artifact.test_profile_ids)
    rng.shuffle(candidates)

    results = []
    for profile_id in candidates:
        if len(results) >= STABILITY_CHECK_N:
            break
        path = _find_profile_json(profile_id)
        if path is None:
            continue  # bulk data not regenerated locally; skip rather than fail
        profile = Profile.model_validate(json.loads(path.read_text()))

        fv_24 = extract_features(profile).as_dict()
        p_default_24 = predict_default_probability(artifact, fv_24)
        score_24 = vitality_score_from_default_probability(artifact, p_default_24)

        truncated = truncate_seen_window(profile, STABILITY_CHECK_MONTHS)
        fv_12 = extract_features(truncated).as_dict()
        p_default_12 = predict_default_probability(artifact, fv_12)
        score_12 = vitality_score_from_default_probability(artifact, p_default_12)

        results.append(
            {
                "profile_id": profile_id,
                "score_24_months": score_24,
                "score_12_months": score_12,
                "diff": score_24 - score_12,
            }
        )

    if not results:
        return {
            "n_checked": 0,
            "note": "No profile JSON files were available locally (data/generated/ is "
            "gitignored bulk data) -- run backend.generator.generate_dataset first "
            "to exercise this check.",
        }

    diffs = [abs(r["diff"]) for r in results]
    swung = [r for r in results if abs(r["diff"]) > STABILITY_CHECK_SWING_THRESHOLD]
    return {
        "n_checked": len(results),
        "months_compared": [STABILITY_CHECK_MONTHS, 24],
        "mean_abs_diff": round(sum(diffs) / len(diffs), 2),
        "max_abs_diff": max(diffs),
        "n_swung_more_than_threshold": len(swung),
        "swing_threshold": STABILITY_CHECK_SWING_THRESHOLD,
        "caveat": (
            "This bypasses the sufficiency gate on purpose: a real 12-month profile "
            "is classified LOW_CONFIDENCE by assess_sufficiency and would never reach "
            "the model in production (analyze_profile would return vitality_score=null). "
            "This check measures the underlying model's raw sensitivity to reduced "
            "history, not production behaviour."
        ),
        "details": results,
    }


def main() -> None:
    artifact = ScorecardArtifact.load()
    feature_table = load_feature_table(DEFAULT_FEATURE_TABLE)
    labels = load_labels(DEFAULT_LABEL_FILE)

    auc_test, n_test = compute_test_auc(artifact, feature_table, labels)
    print(f"AUC (test split, n={n_test}): {auc_test:.4f}")

    coverage = compute_coverage(feature_table)
    print(f"\nCoverage across {coverage['n_profiles']} profiles: {coverage['pct']}")

    portfolio = compute_portfolio_metrics(artifact, feature_table)
    histogram = portfolio.histogram
    band_distribution = portfolio.band_distribution
    reason_code_frequency = portfolio.reason_code_frequency

    print("\nScore histogram (all FULL profiles):")
    max_count = max(b["count"] for b in histogram) if histogram else 0
    total_scored = sum(b["count"] for b in histogram)
    degenerate = max_count > 0.5 * total_scored if total_scored else False
    for b in histogram:
        print(f"  {b['bucket']:>7s}: {b['count']:4d} {'#' * b['count']}")
    if degenerate:
        print(f"  WARNING: bucket with {max_count} profiles is >50% of all scored "
              f"profiles ({total_scored}) -- histogram looks degenerate, not spread.")
    else:
        print(f"  Shape looks spread, not a single dominant spike "
              f"(largest bucket is {100 * max_count / total_scored:.0f}% of {total_scored}).")

    print(f"\nBand distribution (all FULL profiles): {band_distribution}")

    print("\nReason-code appearance frequency across all FULL profiles "
          "(coherence-filtered -- see reason_codes.py):")
    for name, count in sorted(reason_code_frequency.items(), key=lambda kv: -kv[1]):
        print(f"  {name:36s} {count:4d} ({100 * count / coverage['counts']['SCORED']:.1f}%)")

    print(f"\n12-vs-{STABILITY_CHECK_MONTHS}-month stability check "
          f"(sample of up to {STABILITY_CHECK_N} test profiles):")
    stability = run_stability_check(artifact)
    if stability["n_checked"] == 0:
        print(f"  {stability['note']}")
    else:
        print(f"  checked {stability['n_checked']} profiles")
        print(f"  mean |score_24 - score_12| = {stability['mean_abs_diff']}")
        print(f"  max  |score_24 - score_12| = {stability['max_abs_diff']}")
        print(f"  {stability['n_swung_more_than_threshold']} of {stability['n_checked']} swung "
              f"more than {STABILITY_CHECK_SWING_THRESHOLD} points")
        print(f"  caveat: {stability['caveat']}")

    metrics = {
        "validated_at": now_iso(),
        "artifact_trained_at": artifact.trained_at,
        "train_seed": artifact.train_seed,
        "n_train": len(artifact.train_profile_ids),
        "n_test": len(artifact.test_profile_ids),
        "auc_test": round(auc_test, 4),
        "coverage": coverage,
        "score_histogram": histogram,
        "score_histogram_degenerate": degenerate,
        "band_cutoffs": {
            "strong_candidate_max_default_prob": artifact.band_cutoffs.strong_candidate_max,
            "high_risk_referral_min_default_prob": artifact.band_cutoffs.high_risk_referral_min,
            "method": artifact.band_cutoffs.method,
        },
        "band_distribution": band_distribution,
        "reason_code_feature_frequency": reason_code_frequency,
        "feature_coefficients": artifact.coefficients,
        "stability_check_12_vs_24_months": stability,
    }
    METRICS_PATH.parent.mkdir(parents=True, exist_ok=True)
    METRICS_PATH.write_text(json.dumps(metrics, indent=2))
    print(f"\nWrote {METRICS_PATH}")


if __name__ == "__main__":
    main()
