"""Tests for backend/model/authenticity.py and its wiring into analyze_profile.

Three things are locked here:

1. The floor is calibrated against REAL data, not guessed. The calibration
   tests re-derive the population's actual CV distribution and fail if the
   margin between the floor and the lowest legitimate profile erodes.
2. A genuinely flat trail is caught.
3. The check is purely additive -- every pre-existing field is byte-for-byte
   identical whether or not it is present.
"""

from __future__ import annotations

import glob
import json
import unittest
from datetime import timedelta
from unittest import mock

from backend.common.cashflow import monthly_business_income
from backend.common.windows import seen_window
from backend.contract.api_schema import AuthenticityCheck
from backend.features.feature_engine import extract_features
from backend.generator.schema import Profile
from backend.model.authenticity import (
    _MIN_INCOME_MONTHS,
    _UNIFORMITY_FLOOR,
    check_authenticity,
)
from backend.model.scorecard import analyze_profile
from backend.tests.helpers import SEEN_START, add_months, income_tx, make_profile, rent_tx
from backend.tests.model_helpers import make_artifact

DATA_DIR = "data"


def _demo_profiles() -> dict[str, Profile]:
    """Every committed demo profile, keyed by its frontend-facing id.

    Imported from the API's own mapping rather than re-listed here, so a demo
    profile added there is automatically covered by these tests instead of
    silently escaping them.
    """
    from backend.api.dependencies import DATA_DIR as API_DATA_DIR, DEMO_PROFILES

    return {
        profile_id: Profile.model_validate(json.loads((API_DATA_DIR / filename).read_text()))
        for profile_id, filename in DEMO_PROFILES.items()
    }


def _cv_and_months(profile: Profile) -> tuple[float | None, int]:
    cv = extract_features(profile).income_coefficient_of_variation
    months = len(monthly_business_income(profile.transactions_seen, seen_window(profile)))
    return cv, months


def flat_income_profile(n_months: int = 24, monthly_income: float = 10_000.0):
    """An income trail with literally zero month-to-month variation.

    Every month earns exactly the same amount, spread over the same number of
    identical transactions. No real business looks like this; it is the
    degenerate case the check exists to catch.
    """
    tx_per_month = 20
    per_tx = monthly_income / tx_per_month
    seen = []
    for i in range(n_months):
        month = add_months(SEEN_START, i)
        for d in range(tx_per_month):
            seen.append(income_tx(month.replace(day=min(1 + d, 28)), per_tx))
        seen.append(rent_tx(month.replace(day=27), 1_000.0))
    end = add_months(SEEN_START, n_months) - timedelta(days=1)
    return make_profile(seen, [], start=SEEN_START, split_date=None, end=end)


class TestFloorIsCalibratedAgainstRealData(unittest.TestCase):
    """The floor must sit clearly below every legitimate profile.

    These recompute the distribution rather than asserting remembered
    numbers, so regenerating the dataset with different parameters fails here
    loudly instead of quietly turning the check into a false-positive
    machine.
    """

    @classmethod
    def setUpClass(cls):
        cls.rows = []
        for path in sorted(glob.glob(f"{DATA_DIR}/generated/*.json")):
            profile = Profile.model_validate(json.loads(open(path).read()))
            cls.rows.append(_cv_and_months(profile))
        if not cls.rows:
            raise unittest.SkipTest(
                "data/generated is empty -- run backend.generator.generate_dataset"
            )

    def test_no_long_history_profile_in_the_population_falls_below_the_floor(self):
        eligible = [cv for cv, months in self.rows if cv is not None and months >= _MIN_INCOME_MONTHS]
        self.assertGreater(len(eligible), 400, "expected most of the population to be eligible")
        self.assertGreater(
            min(eligible),
            _UNIFORMITY_FLOOR,
            "a legitimately generated profile would be flagged as fabricated",
        )

    def test_the_floor_keeps_a_real_margin_below_the_population_minimum(self):
        # Not merely "below" -- a floor a hair under the minimum would flip to
        # false-positive on any regeneration. Require 25% headroom.
        eligible = [cv for cv, months in self.rows if cv is not None and months >= _MIN_INCOME_MONTHS]
        self.assertGreater(min(eligible), _UNIFORMITY_FLOOR * 1.25)

    def test_short_history_profiles_are_why_the_months_guard_exists(self):
        # Documents the confound rather than just asserting the guard works:
        # the lowest CVs in the whole population belong to SHORT trails, not
        # to fabricated ones. Without the guard these would be flagged.
        short = [cv for cv, months in self.rows if cv is not None and months < _MIN_INCOME_MONTHS]
        self.assertTrue(short, "expected the dataset's short-history edge cases")
        self.assertLess(
            min(short),
            _UNIFORMITY_FLOOR,
            "a short-history profile sits under the floor -- the guard is load-bearing",
        )


# The only demo profile that is SUPPOSED to trip the check. It does not
# represent a real MSME -- it is a hand-built fabricated trail
# (build_demo_profile_uniform_trail) that exists so the flag can be shown
# firing. Listed explicitly rather than skipped by a status check, so that a
# genuine profile drifting under the floor still fails loudly instead of
# being quietly tolerated as "one of the expected ones".
EXPECTED_TO_FLAG = frozenset({"uniform_trail_007"})


class TestDemoProfilesAreNeverFlagged(unittest.TestCase):
    """No committed demo profile may trip the check, bar the one built to.

    A false positive in the live demo is the worst possible failure for this
    feature, so every demo profile is asserted individually and the failure
    message names the offender and its margin.
    """

    def test_no_real_demo_profile_is_flagged_as_unusually_uniform(self):
        for profile_id, profile in _demo_profiles().items():
            if profile_id in EXPECTED_TO_FLAG:
                continue
            with self.subTest(profile_id=profile_id):
                result = analyze_profile(profile, artifact=make_artifact())
                if result.authenticity_check is None:
                    continue
                self.assertEqual(
                    result.authenticity_check.status,
                    "natural",
                    f"{profile_id} flagged at CV {result.authenticity_check.observed:.4f} "
                    f"against floor {_UNIFORMITY_FLOOR}",
                )

    def test_the_fabricated_profile_really_does_flag(self):
        # The other half of the guarantee: the allowlist above must not be a
        # place where a profile goes to stop being checked. If this profile
        # ever stops flagging, the demo silently loses its only worked
        # example and this fails.
        for profile_id in EXPECTED_TO_FLAG:
            with self.subTest(profile_id=profile_id):
                result = analyze_profile(
                    _demo_profiles()[profile_id], artifact=make_artifact()
                )
                self.assertIsNotNone(result.authenticity_check)
                self.assertEqual(
                    result.authenticity_check.status, "unusually_uniform"
                )
                # And it must still be SCORED -- the point of the demo is that
                # a fabricated trail satisfies the model and is caught anyway.
                self.assertEqual(result.outcome.value, "SCORED")
                self.assertIsNotNone(result.vitality_score)

    def test_lakshmi_is_not_near_the_floor_despite_her_tight_generator_volatility(self):
        # build_demo_profile_lakshmi uses volatility=0.06, the tightest in the
        # generator, which makes her look like the obvious false-positive risk.
        # She is not: that knob is DAILY noise, and monthly CV is dominated by
        # seasonality. This pins the reasoning so nobody "fixes" the floor
        # upward on the strength of the tier_params alone.
        cv, _ = _cv_and_months(_demo_profiles()["lakshmi_vendor_001"])
        self.assertIsNotNone(cv)
        self.assertGreater(cv, _UNIFORMITY_FLOOR * 4)

    def test_the_thin_file_demo_profile_is_not_flagged_only_because_of_the_guard(self):
        # thin_file_002 has 4 months and a CV of ~0.037 -- under the floor. It
        # is not fabricated, it is just short. If the months guard is ever
        # removed, this is the profile that breaks first.
        profile = _demo_profiles()["thin_file_002"]
        cv, months = _cv_and_months(profile)
        self.assertLess(months, _MIN_INCOME_MONTHS)
        self.assertLess(cv, _UNIFORMITY_FLOOR)
        self.assertIsNone(analyze_profile(profile, artifact=make_artifact()).authenticity_check)


class TestFlatIncomeIsCaught(unittest.TestCase):
    def test_a_perfectly_flat_trail_is_flagged(self):
        result = analyze_profile(flat_income_profile(), artifact=make_artifact())
        self.assertIsNotNone(result.authenticity_check)
        self.assertEqual(result.authenticity_check.status, "unusually_uniform")
        self.assertAlmostEqual(result.authenticity_check.observed, 0.0, places=6)
        self.assertEqual(result.authenticity_check.floor, _UNIFORMITY_FLOOR)
        self.assertEqual(result.authenticity_check.signal, "income_coefficient_of_variation")
        self.assertIn("manual look", result.authenticity_check.note)

    def test_a_flagged_profile_still_gets_a_normal_score(self):
        # The flag must not behave like a gate: a flagged profile is scored
        # exactly as it would be otherwise.
        result = analyze_profile(flat_income_profile(), artifact=make_artifact())
        self.assertEqual(result.authenticity_check.status, "unusually_uniform")
        self.assertEqual(result.outcome.value, "SCORED")
        self.assertIsNotNone(result.vitality_score)
        self.assertIsNotNone(result.band)


class TestHelperBoundaries(unittest.TestCase):
    """check_authenticity in isolation, at its two boundaries."""

    def test_none_cv_returns_none_rather_than_fabricating_a_zero(self):
        self.assertIsNone(check_authenticity(None, n_income_months=24))

    def test_too_few_months_returns_none_even_for_a_zero_cv(self):
        self.assertIsNone(check_authenticity(0.0, n_income_months=_MIN_INCOME_MONTHS - 1))

    def test_at_the_months_boundary_a_zero_cv_is_flagged(self):
        result = check_authenticity(0.0, n_income_months=_MIN_INCOME_MONTHS)
        self.assertIsNotNone(result)
        self.assertEqual(result.status, "unusually_uniform")

    def test_a_value_exactly_at_the_floor_is_natural_not_flagged(self):
        # Strictly-below, so the floor itself is a legitimate value.
        result = check_authenticity(_UNIFORMITY_FLOOR, n_income_months=24)
        self.assertEqual(result.status, "natural")

    def test_a_value_just_under_the_floor_is_flagged(self):
        result = check_authenticity(_UNIFORMITY_FLOOR - 1e-9, n_income_months=24)
        self.assertEqual(result.status, "unusually_uniform")

    def test_returns_the_contract_model(self):
        self.assertIsInstance(check_authenticity(0.3, n_income_months=24), AuthenticityCheck)


class TestTheCheckIsPurelyAdditive(unittest.TestCase):
    """Every field that existed before this feature must be unchanged.

    This is a real A/B rather than a reading of the diff: the check is
    disabled at its call site (patched to return None, exactly as if the
    feature had never been wired in), the same profile is scored again, and
    every key except `authenticity_check` must match. Run against a FLAGGED
    profile as well as an unflagged one -- a flagged profile is where an
    accidental coupling would actually surface.
    """

    def _with_and_without(self, profile) -> tuple[dict, dict]:
        enabled = analyze_profile(profile, artifact=make_artifact()).model_dump(mode="json")
        with mock.patch("backend.model.scorecard.check_authenticity", return_value=None):
            disabled = analyze_profile(profile, artifact=make_artifact()).model_dump(mode="json")
        return enabled, disabled

    def _assert_only_the_new_field_differs(self, profile):
        enabled, disabled = self._with_and_without(profile)
        self.assertIsNone(disabled["authenticity_check"])
        self.assertEqual(enabled.keys(), disabled.keys())
        for key in enabled:
            if key == "authenticity_check":
                continue
            self.assertEqual(
                enabled[key], disabled[key], f"{key} changed when the check was enabled"
            )

    def test_an_unflagged_scored_profile_is_unchanged(self):
        self._assert_only_the_new_field_differs(_demo_profiles()["lakshmi_vendor_001"])

    def test_a_flagged_profile_is_unchanged_apart_from_the_annotation(self):
        profile = flat_income_profile()
        self.assertEqual(
            analyze_profile(profile, artifact=make_artifact()).authenticity_check.status,
            "unusually_uniform",
        )
        self._assert_only_the_new_field_differs(profile)

    def test_a_gated_profile_is_unchanged(self):
        # The NOT_ASSESSABLE branch builds its own response object, so it is a
        # separate code path and gets its own assertion.
        profile = _demo_profiles()["thin_file_002"]
        self.assertEqual(
            analyze_profile(profile, artifact=make_artifact()).outcome.value,
            "NOT_ASSESSABLE",
        )
        self._assert_only_the_new_field_differs(profile)

    def test_every_demo_profile_is_unchanged(self):
        for profile_id, profile in _demo_profiles().items():
            with self.subTest(profile_id=profile_id):
                self._assert_only_the_new_field_differs(profile)

    def test_the_field_defaults_to_none_so_old_constructions_still_validate(self):
        # An AnalyzeResponse built without the new field at all -- i.e. any
        # caller written before this feature -- must still be valid.
        from backend.contract.api_schema import (
            Affordability,
            AnalyzeResponse,
            Outcome,
            ReasonCodes,
        )

        response = AnalyzeResponse(
            profile_id="X",
            outcome=Outcome.NOT_ASSESSABLE,
            reason_codes=ReasonCodes(),
            affordability=Affordability(
                indicative_emi_low=0.0,
                indicative_emi_high=0.0,
                months_would_cover_emi_of_last_24=0,
            ),
            monthly_cashflow=[],
        )
        self.assertIsNone(response.authenticity_check)


if __name__ == "__main__":
    unittest.main()
