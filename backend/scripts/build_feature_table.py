#!/usr/bin/env python3
"""Runs the full Y2 pipeline over every generated profile and writes the feature table.

    python3 -m backend.scripts.build_feature_table

Outputs two files, and the separation between them is the point:

  data/feature_table.csv     Committed. One row per profile: profile_id, the 12
                             features, and the sufficiency-gate outcome. This is
                             the ONLY file a model may read.

  data/labels_holdout.csv    Gitignored. The held-out ground-truth label plus the
                             generator's latent health tier, for validation only.
                             Never a model input.

The script asserts that no label column leaks into the feature table before it
writes anything, so the two can never quietly merge.

CSV is used rather than Parquet deliberately: the table is ~520 rows, and CSV
keeps the pipeline dependency-free (stdlib only, beyond the pydantic the
generator already required) so any teammate can run it without setting up an
environment.
"""

from __future__ import annotations

import argparse
import csv
import json
from collections import Counter
from pathlib import Path

from backend.common.cashflow import indicative_emi, monthly_business_income
from backend.common.windows import seen_window
from backend.features.feature_engine import FEATURE_NAMES, extract_features
from backend.features.sufficiency import assess_sufficiency
from backend.generator.schema import Profile
from backend.labels.label_engine import derive_label

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_GENERATED_DIR = REPO_ROOT / "data" / "generated"
DEFAULT_FEATURE_TABLE = REPO_ROOT / "data" / "feature_table.csv"
DEFAULT_LABEL_FILE = REPO_ROOT / "data" / "labels_holdout.csv"

# Committed reference profiles, included alongside the bulk generated set.
COMMITTED_SAMPLES = ("sample_profile.json", "demo_profile_lakshmi.json")

# Hand-tuned demo fixtures, not population samples: never train on them.
# demo_lakshmi is not listed -- the committed model was trained with it in.
DEMO_FIXTURE_IDS = frozenset({"demo_thin_file", "demo_ramesh_carpentry", "demo_dormancy_gap"})

FEATURE_TABLE_COLUMNS = (
    "profile_id",
    *FEATURE_NAMES,
    "sufficiency_outcome",
    "sufficiency_months_available",
    "sufficiency_transactions_per_month",
)

LABEL_FILE_COLUMNS = (
    "profile_id",
    "label",
    "months_failed",
    "months_evaluated",
    "indicative_emi",
    "latent_health_tier",
)

# Anything resembling ground truth must never appear in the feature table.
FORBIDDEN_IN_FEATURE_TABLE = (
    "label",
    "months_failed",
    "latent_health_tier",
    "default",
    "is_default",
    "target",
    "y",
)


def load_profiles(generated_dir: Path) -> list[Profile]:
    """Load every profile, de-duplicating by profile_id.

    The committed samples are copies of profiles that also live in the
    generated directory (the demo profile, and one short-history sample), so
    loading both sources without de-duplication would double-count them.

    The samples are resolved relative to the generated directory's parent
    rather than hardcoded to the repo, so pointing --generated-dir at another
    dataset does not silently mix in two profiles from this repo.
    """
    paths: list[Path] = sorted(generated_dir.glob("*.json"))
    paths += [generated_dir.parent / name for name in COMMITTED_SAMPLES]

    by_id: dict[str, Profile] = {}
    duplicates = 0
    for path in paths:
        if not path.exists():
            continue
        profile = Profile.model_validate(json.loads(path.read_text()))
        if profile.meta.profile_id in DEMO_FIXTURE_IDS:
            continue
        if profile.meta.profile_id in by_id:
            duplicates += 1
            continue
        by_id[profile.meta.profile_id] = profile

    print(f"Loaded {len(by_id)} unique profiles ({duplicates} duplicate ids skipped)")
    return list(by_id.values())


def _csv_value(value: object) -> object:
    """Render None as an empty CSV cell rather than the string 'None'."""
    return "" if value is None else value


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--generated-dir", type=Path, default=DEFAULT_GENERATED_DIR)
    parser.add_argument("--feature-table", type=Path, default=DEFAULT_FEATURE_TABLE)
    parser.add_argument("--label-file", type=Path, default=DEFAULT_LABEL_FILE)
    args = parser.parse_args()

    leaked = [c for c in FEATURE_TABLE_COLUMNS if c in FORBIDDEN_IN_FEATURE_TABLE]
    if leaked:
        raise SystemExit(
            f"Refusing to build: ground-truth column(s) {leaked} present in the "
            "feature table schema. Labels belong only in the gitignored label file."
        )

    if not args.generated_dir.exists():
        raise SystemExit(
            f"{args.generated_dir} not found. Generate the dataset first:\n"
            "    python3 -m backend.generator.generate_dataset"
        )

    profiles = load_profiles(args.generated_dir)
    if not profiles:
        raise SystemExit("No profiles found.")

    feature_rows: list[dict] = []
    label_rows: list[dict] = []
    null_counts: Counter[str] = Counter()
    outcome_counts: Counter[str] = Counter()
    label_counts: Counter[int] = Counter()
    unlabelable = 0

    for profile in profiles:
        features = extract_features(profile)
        sufficiency = assess_sufficiency(profile)
        feature_values = features.as_dict()

        for name, value in feature_values.items():
            if value is None:
                null_counts[name] += 1

        row = {"profile_id": profile.meta.profile_id}
        row.update({name: _csv_value(feature_values[name]) for name in FEATURE_NAMES})
        row["sufficiency_outcome"] = sufficiency.outcome.value
        row["sufficiency_months_available"] = sufficiency.months_available
        row["sufficiency_transactions_per_month"] = round(
            sufficiency.transactions_per_month, 3
        )
        feature_rows.append(row)
        outcome_counts[sufficiency.outcome.value] += 1

        # The EMI is derived from the SEEN window and handed to the label
        # engine as a scalar, so the label engine never reads months 1-24.
        emi = indicative_emi(
            monthly_business_income(profile.transactions_seen, seen_window(profile))
        )
        label = derive_label(profile, emi)
        if label is None:
            unlabelable += 1
            continue
        label_counts[label.label] += 1
        label_rows.append(
            {
                "profile_id": label.profile_id,
                "label": label.label,
                "months_failed": label.months_failed,
                "months_evaluated": label.months_evaluated,
                "indicative_emi": round(label.indicative_emi, 2),
                "latent_health_tier": profile.meta.latent_health_tier.value,
            }
        )

    args.feature_table.parent.mkdir(parents=True, exist_ok=True)
    with args.feature_table.open("w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(FEATURE_TABLE_COLUMNS))
        writer.writeheader()
        writer.writerows(feature_rows)

    with args.label_file.open("w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(LABEL_FILE_COLUMNS))
        writer.writeheader()
        writer.writerows(label_rows)

    total = len(feature_rows)
    print(f"\nFeature table -> {args.feature_table}  ({total} rows)")
    print(f"Hidden labels -> {args.label_file}  ({len(label_rows)} rows, gitignored)")

    print(f"\nSufficiency outcomes: {dict(outcome_counts)}")

    labeled = sum(label_counts.values())
    if labeled:
        pct_default = 100 * label_counts[1] / labeled
        print(
            f"Label distribution:   default={label_counts[1]} ({pct_default:.1f}%), "
            f"no-default={label_counts[0]} ({100 - pct_default:.1f}%), "
            f"unlabelable={unlabelable} (no held-out window)"
        )

    print("\nNull audit (features that are undefined for some profiles):")
    if not null_counts:
        print("  none - every feature computed for every profile")
    for name in FEATURE_NAMES:
        count = null_counts.get(name, 0)
        if count:
            print(f"  {name:36s} {count:4d} null ({100 * count / total:.1f}%)")


if __name__ == "__main__":
    main()
