"""Pydantic models for the /api/analyze and /api/portfolio API contract.

This module defines the contract only — it is consumed by a FastAPI app that
will be built in a later task. Nothing here starts a server or implements
scoring logic. Field names and nesting mirror the contract spec exactly so
the future FastAPI app can import these models directly as its
request/response types.
"""

from __future__ import annotations

from enum import Enum
from typing import Literal, Optional

from pydantic import BaseModel, Field, model_validator

from backend.generator.schema import Transaction

DISCLAIMER = (
    "Research prototype on synthetic data. Not a lending decision system. "
    "Decision-support signal only — final lending decision rests with the lender."
)


class Outcome(str, Enum):
    SCORED = "SCORED"
    LOW_CONFIDENCE = "LOW_CONFIDENCE"
    NOT_ASSESSABLE = "NOT_ASSESSABLE"


class Band(str, Enum):
    STRONG_CANDIDATE = "strong_candidate"
    MANUAL_REVIEW = "manual_review"
    HIGH_RISK_REFERRAL = "high_risk_referral"


class Confidence(str, Enum):
    HIGH = "high"
    LOW = "low"


# ---------------------------------------------------------------------------
# POST /api/analyze
# ---------------------------------------------------------------------------


class AnalyzeRequest(BaseModel):
    profile_id: str
    transactions: list[Transaction]
    months_available: int


# ---------------------------------------------------------------------------
# POST /api/analyze-aggregate  (privacy-minimized submission)
# ---------------------------------------------------------------------------
#
# A third submission path, strictly additive: AnalyzeRequest above is
# untouched and remains the contract for callers that do send full
# transaction histories.
#
# The point is what is NOT transmitted. A caller computes the aggregates
# below on their own infrastructure and sends only those, so no transaction
# date, amount, counterparty, channel or note ever reaches this server --
# there is nothing bank-level here to log, cache or breach.


class SubmittedFeatures(BaseModel):
    """The 12 features, self-reported instead of derived here.

    Field names and Optionality mirror
    `backend.features.feature_engine.FeatureSet` exactly, including its
    "None means not computable, never fabricate a zero" convention: a caller
    with under 24 months genuinely cannot compute year_over_year_change, and
    must say None rather than send 0.0, which would read as "flat" and score
    very differently.

    digital_share and cash_share are accepted for parity with FeatureSet but
    structurally cannot affect anything -- they carry no coefficient (see
    PREDICTIVE_FEATURES in backend/model/artifact.py). They are part of the
    contract, not part of the score.
    """

    pct_weeks_with_income: Optional[float] = None
    income_coefficient_of_variation: Optional[float] = None
    longest_dry_streak_days: Optional[int] = None
    trend_last_6_months: Optional[float] = None
    year_over_year_change: Optional[float] = None
    expense_to_income_ratio: Optional[float] = None
    ontime_bill_payment_rate: Optional[float] = None
    cash_buffer_days: Optional[float] = None
    worst_monthly_dip_pct: Optional[float] = None
    months_would_cover_emi_of_last_24: Optional[int] = None
    digital_share: Optional[float] = None
    cash_share: Optional[float] = None


class MonthlyAggregate(BaseModel):
    """One calendar month, carrying every per-month number the server still
    needs once raw transactions are withheld.

    THREE SEPARATE NUMBERS, NOT ONE. `business_income` is not derivable from
    `gross_inflow`, and the two are computed differently on the transaction
    path (see backend/common/cashflow.py):

    * `monthly_business_income` counts CUSTOMER counterparties only and is
      SIGNED -- a reversed customer inflow subtracts, netting to zero. It
      excludes personal transfers entirely. This is a scoring input.
    * `monthly_gross_cashflow` counts EVERY non-noise counterparty by the
      direction it actually landed -- a reversal adds to outflow rather than
      cancelling its original. This is display only, for the lender's chart.

    Collapsing them would either put personal transfers into the score or
    make the chart disagree with the bank statement, so both are submitted.

    `real_transaction_count` replaces the density scan the gate would
    otherwise do over the transaction list, and must already EXCLUDE noise
    (settlement sweeps, rounding adjustments) -- a server that never sees the
    transactions cannot strip those itself.
    """

    month: str = Field(pattern=r"^\d{4}-(0[1-9]|1[0-2])$", description="YYYY-MM")
    real_transaction_count: int = Field(ge=0)
    business_income: float
    gross_inflow: float = Field(ge=0)
    gross_outflow: float = Field(ge=0)


class AnalyzeAggregateRequest(BaseModel):
    """A scoring request carrying only aggregates -- no transaction-level data.

    `months` must cover EVERY month of the submitted window in an unbroken
    run, including months with no trading at all (submitted as zeros), which
    is how `iter_month_keys` treats them on the transaction path. Omitting
    silent months would report a shorter, denser trail than the business
    actually has and could move it across the sufficiency gate.
    """

    profile_id: str
    months_available: int = Field(ge=0)
    features: SubmittedFeatures
    months: list[MonthlyAggregate]

    @model_validator(mode="after")
    def _validate_window(self) -> "AnalyzeAggregateRequest":
        keys = [m.month for m in self.months]
        if len(set(keys)) != len(keys):
            raise ValueError("months contains duplicate month keys")
        if self.months_available != len(keys):
            raise ValueError(
                f"months_available ({self.months_available}) does not match the "
                f"number of submitted months ({len(keys)})"
            )
        # A gap would silently shorten the window the gate measures, so it is
        # rejected rather than tolerated or filled in.
        ordered = sorted(keys)
        for earlier, later in zip(ordered, ordered[1:]):
            y, m = (int(part) for part in earlier.split("-"))
            expected = f"{y + 1:04d}-01" if m == 12 else f"{y:04d}-{m + 1:02d}"
            if later != expected:
                raise ValueError(
                    f"months must be a continuous run; {earlier} is followed by "
                    f"{later}, expected {expected}"
                )
        return self


class ReasonCode(BaseModel):
    feature: str
    statement: str
    contribution: float


class ReasonCodes(BaseModel):
    strengths: list[ReasonCode] = Field(default_factory=list)
    concerns: list[ReasonCode] = Field(default_factory=list)


class ScoreBreakdown(BaseModel):
    """The exact additive decomposition behind a SCORED result.

    The model is linear, so `intercept + sum(contributions.values())` equals
    `logit` exactly -- no approximation step (unlike SHAP over a tree model).
    That additivity holds in LOG-ODDS SPACE ONLY. vitality_score is a
    percentile rank of p_default against a frozen reference cohort, which is
    monotonic but not linear, so these contributions must never be presented
    as "points added to the score".

    Optional and additive: older clients that ignore this field are unaffected.
    """

    intercept: float
    contributions: dict[str, float]
    logit: float
    p_default: float


class AuthenticityCheck(BaseModel):
    """Whether an income trail looks *too* smooth to be a real business's.

    The mirror image of the sufficiency gate: that one catches too LITTLE
    data, this one catches data that is too CLEAN. Real income carries
    seasonality and bad months; a fabricated or templated trail usually does
    not.

    Purely an annotation. It is computed after scoring is already finished
    and never feeds the gate or the model, so it cannot move vitality_score,
    band, outcome or confidence. `status` is a prompt to look, not a verdict:
    a genuinely well-run business on a fixed monthly contract could sit below
    the floor without anything being wrong.

    Optional and additive: older clients that ignore this field are
    unaffected.
    """

    status: Literal["natural", "unusually_uniform"]
    signal: str
    observed: float
    floor: float
    note: str


class Affordability(BaseModel):
    indicative_emi_low: float
    indicative_emi_high: float
    months_would_cover_emi_of_last_24: int


class MonthlyCashflow(BaseModel):
    month: str
    inflow: float
    outflow: float
    net: float


class AnalyzeResponse(BaseModel):
    profile_id: str
    outcome: Outcome
    vitality_score: Optional[float] = Field(default=None, ge=0, le=100)
    band: Optional[Band] = None
    confidence: Optional[Confidence] = None
    reason_codes: ReasonCodes
    score_breakdown: Optional[ScoreBreakdown] = Field(
        default=None,
        description="Populated only for SCORED outcomes; absent when there is no score to decompose.",
    )
    affordability: Affordability
    monthly_cashflow: list[MonthlyCashflow]
    authenticity_check: Optional[AuthenticityCheck] = Field(
        default=None,
        description=(
            "Populated only when income_coefficient_of_variation is computable "
            "AND there are enough monthly income observations for it to mean "
            "anything; absent otherwise, since a short trail's CV cannot "
            "distinguish a fabricated business from a young one. Independent "
            "of `outcome` -- an annotation, not a gate."
        ),
    )
    coverage_reason: Optional[str] = Field(
        default=None,
        description="Populated only for LOW_CONFIDENCE / NOT_ASSESSABLE outcomes.",
    )
    disclaimer: str = DISCLAIMER


# ---------------------------------------------------------------------------
# GET /api/portfolio
# ---------------------------------------------------------------------------


class BandDistribution(BaseModel):
    strong_candidate: int
    manual_review: int
    high_risk_referral: int


class ScoreHistogramBucket(BaseModel):
    bucket: str
    count: int


class PortfolioResponse(BaseModel):
    n_profiles: int
    coverage_pct: float
    auc: Optional[float] = None
    band_distribution: BandDistribution
    score_histogram: list[ScoreHistogramBucket]
