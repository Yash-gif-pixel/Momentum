"""Leakage-safety tests for the Y3 model layer, held to the same standard as
Y2's: nothing in scoring or training may ever be influenced by held-out
(months 25-30) data.

Y2 already guards feature extraction itself (assert_within_window inside
feature_engine.extract_features). What is NEW and specific to Y3 is that
scorecard.py assembles the affordability block and the monthly-cashflow block
directly from `profile.transactions_seen`, outside of extract_features --
those are a second, independent place a future edit could accidentally wire
up transactions_holdout. The invariance test below exercises the whole
analyze_profile() pipeline end-to-end, the same way Y2's invariance test
exercised extract_features() end-to-end, and for the same reason: a leak that
keeps its dates inside the seen window would slip past feature_engine's own
tripwire, and only an output-invariance check catches it.
"""

from __future__ import annotations

import unittest

from backend.model.artifact import compute_contributions, predict_default_probability
from backend.model.reason_codes import rank_reason_codes
from backend.model.scorecard import analyze_profile
from backend.tests.model_helpers import make_artifact
from backend.tests.test_scorecard import dense_profile, full_profile


class TestScorecardIgnoresHeldOutData(unittest.TestCase):
    """The whole analyze_profile() pipeline must be invariant to the held-out window."""

    def _mutations(self, profile):
        from datetime import timedelta

        from backend.generator.schema import Direction, SplitInfo
        from backend.tests.helpers import income_tx

        # dense_profile() (see test_scorecard.py) has no held-out window by
        # construction. Graft one on: this is what lets the "invariant to
        # holdout content" assertion below mean something -- a fixture with
        # no holdout at all would pass this test vacuously.
        #
        # The injected transaction is dated INSIDE the seen window (not at
        # the real split boundary). That is deliberate: a mutation dated
        # right after the split gets filtered out by window/month-key
        # matching regardless of which list it came from, which would make
        # this test pass even if a future edit genuinely started reading
        # transactions_holdout -- it would prove only that date filtering
        # works, not that the field is unread. Placing it inside the seen
        # window isolates the one thing this test needs to prove: that
        # `transactions_holdout` itself is never consulted, independent of
        # what dates its contents happen to carry.
        leak_date = profile.meta.history_start_date + timedelta(days=10)
        split_date = profile.meta.history_end_date + timedelta(days=1)
        new_end = split_date + timedelta(days=180)
        new_meta = profile.meta.model_copy(
            update={
                "history_end_date": new_end,
                "split": SplitInfo(
                    seen_months=profile.meta.split.seen_months,
                    holdout_months=6,
                    split_date=split_date,
                ),
            }
        )
        baseline_with_holdout = profile.model_copy(update={"meta": new_meta})
        baseline_with_holdout.transactions_holdout = [income_tx(leak_date, 999_999.0)]

        inflated = baseline_with_holdout.model_copy(deep=True)
        for t in inflated.transactions_holdout:
            t.amount *= 1000

        emptied = baseline_with_holdout.model_copy(deep=True)
        emptied.transactions_holdout = []

        flipped = baseline_with_holdout.model_copy(deep=True)
        for t in flipped.transactions_holdout:
            t.direction = Direction.OUT if t.direction == Direction.IN else Direction.IN

        return baseline_with_holdout, [
            ("holdout amounts inflated 1000x", inflated),
            ("holdout window emptied", emptied),
            ("holdout direction flipped", flipped),
        ]

    def test_response_is_identical_regardless_of_holdout_content(self):
        profile = full_profile()
        artifact = make_artifact(
            coefficients={
                "months_would_cover_emi_of_last_24": 1.2,
                "expense_to_income_ratio": -0.8,
                "trend_last_6_months": 0.6,
            },
            intercept=0.1,
        )
        baseline, mutations = self._mutations(profile)
        baseline_response = analyze_profile(baseline, artifact=artifact)

        for description, mutated in mutations:
            with self.subTest(mutation=description):
                response = analyze_profile(mutated, artifact=artifact)
                self.assertEqual(
                    response.model_dump(),
                    baseline_response.model_dump(),
                    f"analyze_profile's output changed when {description} -- "
                    "held-out data is reaching the scoring pipeline",
                )

    def test_not_assessable_response_is_also_invariant_to_holdout(self):
        """The gate branch (affordability/cashflow computed, model never called)
        must be just as leak-proof as the scored branch."""
        profile = dense_profile(3)  # NOT_ASSESSABLE
        baseline, mutations = self._mutations(profile)
        baseline_response = analyze_profile(baseline)

        for description, mutated in mutations:
            with self.subTest(mutation=description):
                response = analyze_profile(mutated)
                self.assertEqual(response.model_dump(), baseline_response.model_dump())


class TestArtifactMathNeverAcceptsHeldOutFeatures(unittest.TestCase):
    """A defense-in-depth check: the model math only ever accepts a flat
    feature-value dict, so it structurally cannot reach into a Profile's
    transactions_holdout even if a caller wanted it to -- there is no
    Profile-shaped argument anywhere in artifact.py's inference functions."""

    def test_predict_default_probability_signature_takes_only_a_value_dict(self):
        import inspect

        params = list(inspect.signature(predict_default_probability).parameters)
        self.assertEqual(params, ["artifact", "feature_values"])

    def test_compute_contributions_signature_takes_only_a_value_dict(self):
        import inspect

        params = list(inspect.signature(compute_contributions).parameters)
        self.assertEqual(params, ["artifact", "feature_values"])

    def test_rank_reason_codes_signature_takes_only_a_value_dict(self):
        import inspect

        params = list(inspect.signature(rank_reason_codes).parameters)
        self.assertEqual(params[:2], ["artifact", "feature_values"])


class TestTrainingPopulationNeverIncludesGatedProfiles(unittest.TestCase):
    """train_scorecard.py must refuse a labeled row that is not FULL -- the
    same gate scorecard.py applies before it will call the model must also
    bound what the model was allowed to learn from."""

    def test_load_training_table_rejects_a_non_full_labeled_row(self):
        import csv
        import tempfile
        from pathlib import Path

        from backend.model.train_scorecard import load_training_table

        from backend.model.artifact import PREDICTIVE_FEATURES

        with tempfile.TemporaryDirectory() as tmp:
            feature_table_path = Path(tmp) / "feature_table.csv"
            label_path = Path(tmp) / "labels.csv"

            feature_columns = [
                "profile_id",
                *PREDICTIVE_FEATURES,
                "sufficiency_outcome",
                "sufficiency_months_available",
                "sufficiency_transactions_per_month",
            ]
            with feature_table_path.open("w", newline="") as fh:
                writer = csv.DictWriter(fh, fieldnames=feature_columns)
                writer.writeheader()
                row = {c: 1.0 for c in feature_columns}
                row["profile_id"] = "SNEAKY0001"
                row["sufficiency_outcome"] = "LOW_CONFIDENCE"  # the point of this test
                row["sufficiency_months_available"] = 9
                writer.writerow(row)

            with label_path.open("w", newline="") as fh:
                writer = csv.DictWriter(
                    fh,
                    fieldnames=[
                        "profile_id", "label", "months_failed", "months_evaluated",
                        "indicative_emi", "latent_health_tier",
                    ],
                )
                writer.writeheader()
                writer.writerow(
                    {
                        "profile_id": "SNEAKY0001", "label": 0, "months_failed": 0,
                        "months_evaluated": 6, "indicative_emi": 1000.0,
                        "latent_health_tier": "stable",
                    }
                )

            # A labeled-but-not-FULL row must be silently excluded, not fed
            # to the model -- the function must return an empty population
            # rather than raising, since a real dataset can validly contain
            # zero such rows most of the time.
            ids, rows, y = load_training_table(feature_table_path, label_path)
            self.assertEqual(ids, [])

    def test_load_training_table_rejects_a_full_row_with_the_wrong_month_count(self):
        import csv
        import tempfile
        from pathlib import Path

        from backend.model.artifact import PREDICTIVE_FEATURES
        from backend.model.train_scorecard import load_training_table

        with tempfile.TemporaryDirectory() as tmp:
            feature_table_path = Path(tmp) / "feature_table.csv"
            label_path = Path(tmp) / "labels.csv"

            feature_columns = [
                "profile_id", *PREDICTIVE_FEATURES, "sufficiency_outcome",
                "sufficiency_months_available", "sufficiency_transactions_per_month",
            ]
            with feature_table_path.open("w", newline="") as fh:
                writer = csv.DictWriter(fh, fieldnames=feature_columns)
                writer.writeheader()
                row = {c: 1.0 for c in feature_columns}
                row["profile_id"] = "ODD0001"
                row["sufficiency_outcome"] = "FULL"
                row["sufficiency_months_available"] = 18  # not 24 -- must be rejected
                writer.writerow(row)

            with label_path.open("w", newline="") as fh:
                writer = csv.DictWriter(
                    fh,
                    fieldnames=[
                        "profile_id", "label", "months_failed", "months_evaluated",
                        "indicative_emi", "latent_health_tier",
                    ],
                )
                writer.writeheader()
                writer.writerow(
                    {
                        "profile_id": "ODD0001", "label": 0, "months_failed": 0,
                        "months_evaluated": 6, "indicative_emi": 1000.0,
                        "latent_health_tier": "stable",
                    }
                )

            with self.assertRaises(SystemExit):
                load_training_table(feature_table_path, label_path)


if __name__ == "__main__":
    unittest.main()
