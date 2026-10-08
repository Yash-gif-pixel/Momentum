"""Feature-table tests: the label must never reach the model's input file.

`test_fairness.py` deliberately does not scan `build_feature_table.py`, because
that script is allowed to read ground truth in order to write the gitignored
validation file. The guarantee that it keeps ground truth *out* of the feature
table is asserted here instead.
"""

from __future__ import annotations

import csv
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from backend.features.feature_engine import FEATURE_NAMES
from backend.scripts.build_feature_table import (
    DEMO_FIXTURE_IDS,
    FEATURE_TABLE_COLUMNS,
    FORBIDDEN_IN_FEATURE_TABLE,
    LABEL_FILE_COLUMNS,
    load_profiles,
)

REPO_ROOT = Path(__file__).resolve().parents[2]
DATA_DIR = REPO_ROOT / "data"
FEATURE_TABLE = DATA_DIR / "feature_table.csv"
GITIGNORE = REPO_ROOT / ".gitignore"


class TestFeatureTableSchema(unittest.TestCase):
    def test_no_ground_truth_column_in_the_feature_table_schema(self):
        leaked = set(FEATURE_TABLE_COLUMNS) & set(FORBIDDEN_IN_FEATURE_TABLE)
        self.assertEqual(leaked, set(), f"ground truth leaked into the table: {leaked}")

    def test_table_carries_profile_id_every_feature_and_the_gate_outcome(self):
        self.assertEqual(FEATURE_TABLE_COLUMNS[0], "profile_id")
        for name in FEATURE_NAMES:
            self.assertIn(name, FEATURE_TABLE_COLUMNS)
        self.assertIn("sufficiency_outcome", FEATURE_TABLE_COLUMNS)

    def test_label_lives_only_in_the_label_file(self):
        self.assertIn("label", LABEL_FILE_COLUMNS)
        self.assertIn("latent_health_tier", LABEL_FILE_COLUMNS)
        self.assertNotIn("label", FEATURE_TABLE_COLUMNS)
        self.assertNotIn("latent_health_tier", FEATURE_TABLE_COLUMNS)

    def test_label_file_is_gitignored(self):
        self.assertIn("labels_holdout.csv", GITIGNORE.read_text())


class TestDemoFixturesExcludedFromTraining(unittest.TestCase):
    def test_demo_fixtures_in_the_generated_dir_are_not_loaded(self):
        with tempfile.TemporaryDirectory() as tmp:
            generated = Path(tmp) / "generated"
            generated.mkdir()
            for name in ("thin_file", "ramesh_carpentry", "dormancy_gap"):
                src = DATA_DIR / f"demo_profile_{name}.json"
                (generated / f"demo_{name}.json").write_text(src.read_text())
            (generated / "MSME0003.json").write_text((DATA_DIR / "sample_profile.json").read_text())

            loaded = {p.meta.profile_id for p in load_profiles(generated)}

        self.assertEqual(loaded, {"MSME0003"})
        self.assertEqual(DEMO_FIXTURE_IDS, {"demo_thin_file", "demo_ramesh_carpentry", "demo_dormancy_gap"})


class TestBuiltFeatureTable(unittest.TestCase):
    @unittest.skipUnless(FEATURE_TABLE.exists(), "feature table not built yet")
    def test_committed_table_has_no_ground_truth_column(self):
        with FEATURE_TABLE.open() as fh:
            header = next(csv.reader(fh))
        for forbidden in FORBIDDEN_IN_FEATURE_TABLE:
            self.assertNotIn(forbidden, header)

    @unittest.skipUnless(FEATURE_TABLE.exists(), "feature table not built yet")
    def test_committed_table_has_one_row_per_unique_profile(self):
        with FEATURE_TABLE.open() as fh:
            rows = list(csv.DictReader(fh))
        ids = [row["profile_id"] for row in rows]
        self.assertEqual(len(ids), len(set(ids)), "duplicate profile_id in the table")
        self.assertGreater(len(rows), 500, "expected 500+ profiles")

    @unittest.skipUnless(FEATURE_TABLE.exists(), "feature table not built yet")
    def test_affordability_is_populated_for_every_row(self):
        """The flagship feature must never be null."""
        with FEATURE_TABLE.open() as fh:
            for row in csv.DictReader(fh):
                self.assertNotEqual(
                    row["months_would_cover_emi_of_last_24"],
                    "",
                    f"{row['profile_id']} has a null affordability feature",
                )


class TestPipelineEndToEnd(unittest.TestCase):
    """Runs the real script over the committed sample profiles."""

    def test_build_produces_separate_feature_and_label_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            generated = tmp_path / "generated"
            generated.mkdir()
            for name in ("sample_profile.json", "demo_profile_lakshmi.json"):
                shutil.copy(DATA_DIR / name, generated / name)

            feature_table = tmp_path / "feature_table.csv"
            label_file = tmp_path / "labels.csv"

            result = subprocess.run(
                [
                    sys.executable,
                    "-m",
                    "backend.scripts.build_feature_table",
                    "--generated-dir", str(generated),
                    "--feature-table", str(feature_table),
                    "--label-file", str(label_file),
                ],
                cwd=REPO_ROOT,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(feature_table.exists())
            self.assertTrue(label_file.exists())

            with feature_table.open() as fh:
                feature_rows = list(csv.DictReader(fh))
            with label_file.open() as fh:
                label_rows = list(csv.DictReader(fh))

            # Both committed samples appear once each, de-duplicated against
            # the copies in the generated directory.
            ids = {row["profile_id"] for row in feature_rows}
            self.assertEqual(ids, {"MSME0003", "demo_lakshmi"})

            for row in feature_rows:
                for forbidden in FORBIDDEN_IN_FEATURE_TABLE:
                    self.assertNotIn(forbidden, row)

            # The short-history sample has no held-out window, so only the
            # demo profile can be labeled.
            self.assertEqual([row["profile_id"] for row in label_rows], ["demo_lakshmi"])

    def test_build_refuses_when_the_dataset_is_missing(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = subprocess.run(
                [
                    sys.executable,
                    "-m",
                    "backend.scripts.build_feature_table",
                    "--generated-dir", str(Path(tmp) / "does-not-exist"),
                ],
                cwd=REPO_ROOT,
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("generate_dataset", result.stderr + result.stdout)


if __name__ == "__main__":
    unittest.main()
