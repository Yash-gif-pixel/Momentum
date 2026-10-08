"""The trained scorecard artifact: its shape, persistence, and the inference math.

This module is the single place that defines how a standardized feature value
becomes a predicted probability and a reason-code contribution. `train_scorecard.py`
uses it to evaluate the model it just fit; `validate.py` uses it to re-derive
AUC and the score histogram; `scorecard.py` uses it for live inference. Having
one definition means training-time evaluation and production-time inference can
never quietly drift apart -- the classic bug where a model looks good in
notebook and wrong in production.

Deliberately dependency-light: everything below is plain stdlib math (no numpy,
no scikit-learn). `train_scorecard.py` and `validate.py` need scikit-learn to
FIT the model and split the data; nothing that reads this module back for
inference does. A future FastAPI server can import `scorecard.py` without
installing a scientific Python stack.

Fairness note, carried forward from Y2 with the same seriousness: `digital_share`
and `cash_share` are excluded from `PREDICTIVE_FEATURES`. See the module
docstring in `reason_codes.py` for the full reasoning -- in short, they are
computed and templated like every other feature, but structurally cannot
receive a coefficient, so they can never move a score or appear in a reason
code. This is enforced here, not just documented: `PREDICTIVE_FEATURES` is the
only feature set `fit`/`predict_default_probability`/`compute_contributions`
ever touch.
"""

from __future__ import annotations

import json
import math
from bisect import bisect_right
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from backend.features.feature_engine import FEATURE_NAMES

REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACT_DIR = REPO_ROOT / "backend" / "model" / "artifacts"
ARTIFACT_PATH = ARTIFACT_DIR / "scorecard_model.json"
METRICS_PATH = ARTIFACT_DIR / "metrics.json"

# The 12 features Y2 computes, minus the two that must never move a score.
# digital_share and cash_share are also perfectly collinear (they sum to 1),
# which independent of the fairness question would make their individual
# coefficients numerically unstable -- a logistic regression given two
# perfectly anti-correlated columns splits an arbitrary, solver-dependent
# weight between them. Excluding both is the right call on statistical
# grounds alone, and doubly right given Y2's fairness mandate.
_EXCLUDED_FROM_MODEL = frozenset({"digital_share", "cash_share"})
PREDICTIVE_FEATURES: tuple[str, ...] = tuple(
    name for name in FEATURE_NAMES if name not in _EXCLUDED_FROM_MODEL
)

assert len(PREDICTIVE_FEATURES) == 10, "expected 10 predictive features (12 minus 2 trail features)"


def sigmoid(x: float) -> float:
    # Guard against overflow on extreme logits (e.g. a pathological test input).
    if x >= 0:
        z = math.exp(-x)
        return 1.0 / (1.0 + z)
    z = math.exp(x)
    return z / (1.0 + z)


def standardize(value: float, mean: float, scale: float) -> float:
    if scale == 0:
        return 0.0
    return (value - mean) / scale


@dataclass(frozen=True)
class BandCutoffs:
    """Probability-of-default thresholds separating the three bands.

    A profile's predicted default probability p_default determines its band:
      p_default <= strong_candidate_max   -> strong_candidate
      p_default >= high_risk_referral_min -> high_risk_referral
      otherwise                            -> manual_review

    Calibrated from the validation set's actual probability distribution by
    train_scorecard.py -- see docs/DATA_SCHEMA.md for the exact percentiles
    used and why.
    """

    strong_candidate_max: float
    high_risk_referral_min: float
    method: str

    def band_for(self, p_default: float) -> str:
        if p_default <= self.strong_candidate_max:
            return "strong_candidate"
        if p_default >= self.high_risk_referral_min:
            return "high_risk_referral"
        return "manual_review"


@dataclass(frozen=True)
class ScorecardArtifact:
    trained_at: str
    train_seed: int
    predictive_features: tuple[str, ...]
    scaler_mean: dict[str, float]
    scaler_scale: dict[str, float]
    coefficients: dict[str, float]
    intercept: float
    band_cutoffs: BandCutoffs
    train_profile_ids: tuple[str, ...]
    test_profile_ids: tuple[str, ...]
    # Sorted (ascending) predicted default probabilities of the TEST split,
    # frozen at training time. This is the reference distribution
    # vitality_score is ranked against -- see
    # vitality_score_from_default_probability below. Deliberately the same
    # split band_cutoffs is calibrated from (not the training split): a
    # profile's score and its band should read as mutually consistent, since
    # both are "how does this compare to the reference cohort" statements
    # drawn from the same cohort. This does not compromise auc_test's
    # validity -- score/band calibration happens strictly after AUC is
    # computed and never feeds back into how the model was fit, so it carries
    # none of the overfitting risk that reusing test data for model selection
    # would.
    reference_default_probabilities: tuple[float, ...]

    def to_json_dict(self) -> dict:
        return {
            "trained_at": self.trained_at,
            "train_seed": self.train_seed,
            "predictive_features": list(self.predictive_features),
            "scaler_mean": self.scaler_mean,
            "scaler_scale": self.scaler_scale,
            "coefficients": self.coefficients,
            "intercept": self.intercept,
            "band_cutoffs": {
                "strong_candidate_max": self.band_cutoffs.strong_candidate_max,
                "high_risk_referral_min": self.band_cutoffs.high_risk_referral_min,
                "method": self.band_cutoffs.method,
            },
            "train_profile_ids": list(self.train_profile_ids),
            "test_profile_ids": list(self.test_profile_ids),
            "reference_default_probabilities": list(self.reference_default_probabilities),
        }

    @classmethod
    def from_json_dict(cls, d: dict) -> "ScorecardArtifact":
        return cls(
            trained_at=d["trained_at"],
            train_seed=d["train_seed"],
            predictive_features=tuple(d["predictive_features"]),
            scaler_mean={k: float(v) for k, v in d["scaler_mean"].items()},
            scaler_scale={k: float(v) for k, v in d["scaler_scale"].items()},
            coefficients={k: float(v) for k, v in d["coefficients"].items()},
            intercept=float(d["intercept"]),
            band_cutoffs=BandCutoffs(
                strong_candidate_max=float(d["band_cutoffs"]["strong_candidate_max"]),
                high_risk_referral_min=float(d["band_cutoffs"]["high_risk_referral_min"]),
                method=d["band_cutoffs"]["method"],
            ),
            train_profile_ids=tuple(d["train_profile_ids"]),
            test_profile_ids=tuple(d["test_profile_ids"]),
            reference_default_probabilities=tuple(
                sorted(float(v) for v in d["reference_default_probabilities"])
            ),
        )

    def save(self, path: Path = ARTIFACT_PATH) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(self.to_json_dict(), indent=2))

    @classmethod
    def load(cls, path: Path = ARTIFACT_PATH) -> "ScorecardArtifact":
        if not path.exists():
            raise FileNotFoundError(
                f"{path} not found. Train the model first:\n"
                "    python3 -m backend.model.train_scorecard"
            )
        return cls.from_json_dict(json.loads(path.read_text()))


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def standardized_value(
    artifact: ScorecardArtifact, feature: str, raw_value: Optional[float]
) -> Optional[float]:
    if raw_value is None:
        return None
    return standardize(raw_value, artifact.scaler_mean[feature], artifact.scaler_scale[feature])


def predict_vitality_probability(
    artifact: ScorecardArtifact, feature_values: dict[str, Optional[float]]
) -> float:
    """P(no default) for one profile's raw feature values.

    Any predictive feature that is None (should not happen for a FULL profile,
    but inference stays defensive) is treated as its training-set mean --
    i.e. it contributes zero to the logit, neither a strength nor a concern.
    Missing features are also excluded from `compute_contributions` for the
    same profile, so this never silently manufactures a reason code out of
    absent data.
    """
    logit = artifact.intercept
    for feature in artifact.predictive_features:
        raw = feature_values.get(feature)
        z = standardized_value(artifact, feature, raw) if raw is not None else 0.0
        logit += artifact.coefficients[feature] * z
    return sigmoid(logit)


def predict_default_probability(
    artifact: ScorecardArtifact, feature_values: dict[str, Optional[float]]
) -> float:
    return 1.0 - predict_vitality_probability(artifact, feature_values)


def vitality_score_from_default_probability(
    artifact: ScorecardArtifact, p_default: float
) -> int:
    """vitality_score: this profile's percentile rank against the TRAINING
    population's predicted default probabilities, inverted so 100 is safest.

    The one place this formula is written. scorecard.py and validate.py both
    call this rather than each re-deriving it, so a future edit to the
    ranking rule cannot update one call site and silently miss another.

    WHY PERCENTILE RANK, NOT A LINEAR 100*(1-p_default) TRANSFORM:
    predicted default probabilities on this dataset are heavily skewed --
    most profiles are genuinely low-risk, so a linear transform crushes the
    vast majority of the population into the 90-100 range (this was measured:
    83.8% of FULL profiles landed in that one bucket) and leaves almost no
    resolution to tell a merely-good business from an excellent one. A rank
    transform fixes this by construction: mapping through the empirical CDF
    of a reference population always produces an exactly uniform score
    distribution ON that reference population, and an approximately uniform
    one on any new population drawn from a similar distribution.

    The trade-off, stated plainly: vitality_score stops being a direct read
    of "probability this business does not default" and becomes "how this
    business's risk compares to the training cohort's risk distribution."
    That is a real change in what the number means, not a free lunch --
    documented in docs/DATA_SCHEMA.md. It is also exactly how many real
    credit scores work (e.g. a 3-digit score is a rescaled rank against a
    reference population, not PD read off directly), so it is a defensible,
    precedented choice rather than an ad hoc one.

    The reference distribution is frozen at training time (the TEST split's
    own predicted default probabilities, sorted -- the same split
    band_cutoffs is calibrated from, so a profile's score and band are
    consistent statements about the same reference cohort) and travels
    inside the artifact, so a score computed today and one computed next
    month against the same trained model mean the same thing -- it does not
    silently drift depending on who else happens to be in today's batch of
    API calls.
    """
    reference = artifact.reference_default_probabilities
    if not reference:
        # Only reachable with a hand-built artifact that omitted the
        # reference distribution (e.g. an old test fixture); a real trained
        # artifact always has one. Falls back to the plain linear transform
        # rather than dividing by zero.
        return max(0, min(100, round(100 * (1 - p_default))))

    rank = bisect_right(reference, p_default)
    percentile_of_default_risk = rank / len(reference)  # 0 = safest, 1 = riskiest
    return max(0, min(100, round(100 * (1 - percentile_of_default_risk))))


def compute_contributions(
    artifact: ScorecardArtifact, feature_values: dict[str, Optional[float]]
) -> dict[str, float]:
    """(standardized coefficient) x (standardized feature value) per predictive feature.

    Positive == pushes toward vitality / strong_candidate (a strength).
    Negative == pushes toward default risk (a concern).

    Only features in `artifact.predictive_features` ever appear here --
    digital_share and cash_share have no coefficient and are never included,
    by construction (see PREDICTIVE_FEATURES above).
    """
    contributions: dict[str, float] = {}
    for feature in artifact.predictive_features:
        raw = feature_values.get(feature)
        if raw is None:
            continue
        z = standardized_value(artifact, feature, raw)
        contributions[feature] = artifact.coefficients[feature] * z
    return contributions
