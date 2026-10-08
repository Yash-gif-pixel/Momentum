"""A small hand-built ScorecardArtifact for deterministic model-layer tests.

Using a fixed, tiny artifact (rather than the real trained one) means these
tests assert exact arithmetic instead of "some plausible number", and they
never depend on a training run having happened first.
"""

from __future__ import annotations

from backend.model.artifact import BandCutoffs, PREDICTIVE_FEATURES, ScorecardArtifact


# 101 evenly spaced points from 0.0 to 1.0 -- a synthetic reference
# distribution wide enough that any p_default computed by these tests lands
# somewhere sane in the percentile ranking, without depending on a real
# trained model's test-split probabilities.
DEFAULT_REFERENCE_DEFAULT_PROBABILITIES = tuple(round(i / 100, 4) for i in range(101))


def make_artifact(
    coefficients: dict[str, float] | None = None,
    intercept: float = 0.0,
    strong_candidate_max: float = 0.1,
    high_risk_referral_min: float = 0.5,
    reference_default_probabilities: tuple[float, ...] | None = None,
) -> ScorecardArtifact:
    """All means=0, scales=1 by default, so standardized value == raw value
    unless a test overrides scaler_mean/scaler_scale directly on the result.
    """
    coefficients = coefficients or {name: 0.0 for name in PREDICTIVE_FEATURES}
    if reference_default_probabilities is None:
        reference_default_probabilities = DEFAULT_REFERENCE_DEFAULT_PROBABILITIES
    return ScorecardArtifact(
        trained_at="2026-01-01T00:00:00+00:00",
        train_seed=0,
        predictive_features=PREDICTIVE_FEATURES,
        scaler_mean={name: 0.0 for name in PREDICTIVE_FEATURES},
        scaler_scale={name: 1.0 for name in PREDICTIVE_FEATURES},
        coefficients={**{name: 0.0 for name in PREDICTIVE_FEATURES}, **coefficients},
        intercept=intercept,
        band_cutoffs=BandCutoffs(
            strong_candidate_max=strong_candidate_max,
            high_risk_referral_min=high_risk_referral_min,
            method="test fixture",
        ),
        train_profile_ids=("TRAIN0001",),
        test_profile_ids=("TEST0001",),
        reference_default_probabilities=reference_default_probabilities,
    )


def neutral_feature_values() -> dict[str, float]:
    """Every predictive feature at a middling, plausible value."""
    return {
        "pct_weeks_with_income": 0.9,
        "income_coefficient_of_variation": 0.3,
        "longest_dry_streak_days": 5,
        "trend_last_6_months": 0.05,
        "year_over_year_change": 0.05,
        "expense_to_income_ratio": 0.4,
        "ontime_bill_payment_rate": 0.9,
        "cash_buffer_days": 30.0,
        "worst_monthly_dip_pct": 0.3,
        "months_would_cover_emi_of_last_24": 20,
        "digital_share": 0.7,
        "cash_share": 0.3,
    }
