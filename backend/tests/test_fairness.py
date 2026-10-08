"""Fairness-by-design tests: banned fields must never reach a feature.

A credit model built on alternative data can launder a demographic proxy into
a score without anyone intending it -- a pincode, a merchant category code, a
free-text memo carrying a counterparty's name. Once that is in the training
data it is nearly impossible to spot by looking at the score.

So this is enforced structurally rather than by review. The static test below
parses the AST of every module that participates in computing a feature and
asserts that no banned field is ever read as an attribute. Adding a banned
field to a feature breaks the build.

Scope note: `build_feature_table.py` is deliberately NOT scanned. It reads
`latent_health_tier` on purpose, to write the gitignored validation file. That
it never lets ground truth into the feature table is asserted separately, in
`test_feature_table.py`.
"""

from __future__ import annotations

import ast
import unittest
from pathlib import Path

from backend.features.feature_engine import (
    EXCLUDED_FIELDS,
    EXCLUDED_FIELDS_PRESENT_IN_SCHEMA,
    EXCLUDED_FIELDS_RESERVED,
    FEATURE_NAMES,
    extract_features,
)
from backend.tests.helpers import monthly_profile

REPO_ROOT = Path(__file__).resolve().parents[2]

# Every module that participates in turning transactions into a feature value.
FEATURE_PATH_MODULES = (
    REPO_ROOT / "backend" / "features" / "feature_engine.py",
    REPO_ROOT / "backend" / "features" / "sufficiency.py",
    REPO_ROOT / "backend" / "common" / "cashflow.py",
    REPO_ROOT / "backend" / "common" / "windows.py",
)


def attribute_names_read(path: Path) -> set[str]:
    """Every attribute name read anywhere in a module (e.g. `tx.note` -> 'note')."""
    tree = ast.parse(path.read_text())
    return {node.attr for node in ast.walk(tree) if isinstance(node, ast.Attribute)}


def string_subscripts(path: Path) -> set[str]:
    """String keys used in subscripts, to catch `row["pincode"]`-style access."""
    tree = ast.parse(path.read_text())
    keys: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Subscript) and isinstance(node.slice, ast.Constant):
            if isinstance(node.slice.value, str):
                keys.add(node.slice.value)
    return keys


class TestExcludedFieldsList(unittest.TestCase):
    def test_list_is_populated_and_deduplicated(self):
        self.assertGreater(len(EXCLUDED_FIELDS), 20)
        self.assertEqual(
            len(EXCLUDED_FIELDS),
            len(set(EXCLUDED_FIELDS)),
            "EXCLUDED_FIELDS contains duplicates",
        )

    def test_covers_the_three_required_categories(self):
        for required in ("pincode", "gender", "merchant_category_code"):
            self.assertIn(
                required,
                EXCLUDED_FIELDS,
                f"{required} must be named in the fairness exclusion list",
            )

    def test_present_in_schema_entries_really_exist_on_the_models(self):
        """The 'present in schema' half must stay in sync with the real schema.

        If a field is renamed or dropped in the generator, this fails so the
        exclusion list cannot silently rot into a list of names that no longer
        mean anything.
        """
        from backend.generator.schema import ProfileMeta, Transaction

        known = set(Transaction.model_fields) | set(ProfileMeta.model_fields)
        for field in EXCLUDED_FIELDS_PRESENT_IN_SCHEMA:
            self.assertIn(
                field,
                known,
                f"'{field}' is listed as present in the schema but no longer exists",
            )

    def test_reserved_entries_do_not_exist_on_the_models(self):
        from backend.generator.schema import ProfileMeta, Transaction

        known = set(Transaction.model_fields) | set(ProfileMeta.model_fields)
        for field in EXCLUDED_FIELDS_RESERVED:
            self.assertNotIn(
                field,
                known,
                f"'{field}' now exists in the schema -- move it to "
                "EXCLUDED_FIELDS_PRESENT_IN_SCHEMA so the static scan covers it",
            )


class TestNoExcludedFieldIsReadOnTheFeaturePath(unittest.TestCase):
    def test_no_banned_attribute_is_read(self):
        for module_path in FEATURE_PATH_MODULES:
            with self.subTest(module=module_path.name):
                read = attribute_names_read(module_path)
                banned = read & set(EXCLUDED_FIELDS)
                self.assertEqual(
                    banned,
                    set(),
                    f"{module_path.name} reads banned field(s) {sorted(banned)}. "
                    "These are demographic proxies or generator ground truth and "
                    "must never influence a feature.",
                )

    def test_no_banned_string_subscript(self):
        for module_path in FEATURE_PATH_MODULES:
            with self.subTest(module=module_path.name):
                banned = string_subscripts(module_path) & set(EXCLUDED_FIELDS)
                self.assertEqual(
                    banned, set(), f"{module_path.name} subscripts banned field(s) {sorted(banned)}"
                )

    def test_feature_names_do_not_reference_banned_concepts(self):
        for feature_name in FEATURE_NAMES:
            for banned in EXCLUDED_FIELDS:
                self.assertNotIn(
                    banned,
                    feature_name,
                    f"feature '{feature_name}' references banned field '{banned}'",
                )


class TestFairnessTripwireAtRuntime(unittest.TestCase):
    """Behavioural backstop: touching a banned field during extraction explodes."""

    def test_extraction_does_not_touch_banned_meta_fields(self):
        profile = monthly_profile([10_000.0] * 24, essentials_per_month=1_000.0)

        tripped: list[str] = []
        banned_on_meta = [
            field
            for field in EXCLUDED_FIELDS_PRESENT_IN_SCHEMA
            if field in type(profile.meta).model_fields
        ]
        self.assertTrue(banned_on_meta, "expected some banned fields to live on meta")

        class TripwireMeta:
            def __init__(self, wrapped):
                object.__setattr__(self, "_wrapped", wrapped)

            def __getattr__(self, name):
                if name in banned_on_meta:
                    tripped.append(name)
                    raise AssertionError(
                        f"feature extraction read banned field 'meta.{name}'"
                    )
                return getattr(object.__getattribute__(self, "_wrapped"), name)

        class TripwireProfile:
            def __init__(self, wrapped):
                object.__setattr__(self, "_wrapped", wrapped)
                object.__setattr__(self, "meta", TripwireMeta(wrapped.meta))

            def __getattr__(self, name):
                return getattr(object.__getattribute__(self, "_wrapped"), name)

        features = extract_features(TripwireProfile(profile))
        self.assertEqual(tripped, [], f"banned fields were read: {tripped}")
        self.assertEqual(features.months_would_cover_emi_of_last_24, 24)

    def test_cash_heavy_profile_is_not_penalised_by_the_gate(self):
        """A cash-heavy trail must not, by itself, cost a business its assessment.

        digital_share / cash_share are informational. Two profiles with
        identical cashflow and different channel mixes must reach the same
        sufficiency outcome and the same affordability result.
        """
        from datetime import timedelta

        from backend.features.sufficiency import SufficiencyOutcome, assess_sufficiency
        from backend.generator.schema import Channel
        from backend.tests.helpers import income_tx, make_profile, rent_tx, add_months, SEEN_START

        def build(channel: Channel):
            seen = []
            for i in range(24):
                month = add_months(SEEN_START, i)
                # 20 trading days a month clears the density bar comfortably,
                # so both profiles reach FULL and the comparison below is a
                # real test rather than two identical refusals.
                for day in range(1, 21):
                    seen.append(income_tx(month.replace(day=day), 1_000.0, channel=channel))
                seen.append(rent_tx(month.replace(day=25), 2_000.0))
            # End on the last day of the 24th month, not the 1st of the 25th.
            end = add_months(SEEN_START, 24) - timedelta(days=1)
            return make_profile(seen, [], split_date=None, end=end)

        digital = build(Channel.UPI)
        cash = build(Channel.CASH)

        digital_gate = assess_sufficiency(digital)
        cash_gate = assess_sufficiency(cash)

        # Both must actually be assessable -- otherwise this test would pass
        # even if the gate did penalise cash.
        self.assertEqual(digital_gate.outcome, SufficiencyOutcome.FULL)
        self.assertEqual(cash_gate.outcome, SufficiencyOutcome.FULL)
        digital_features = extract_features(digital)
        cash_features = extract_features(cash)
        self.assertEqual(
            digital_features.months_would_cover_emi_of_last_24,
            cash_features.months_would_cover_emi_of_last_24,
        )
        # The only thing that may differ is the informational trail split.
        self.assertAlmostEqual(digital_features.digital_share, 1.0)
        self.assertGreater(cash_features.cash_share, 0.0)


if __name__ == "__main__":
    unittest.main()
