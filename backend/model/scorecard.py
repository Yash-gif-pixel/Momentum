"""Inference: a profile's features -> an AnalyzeResponse, matching Y1's contract exactly.

    from backend.model.scorecard import analyze_profile
    response = analyze_profile(profile)   # a backend.generator.schema.Profile

This is the ONLY function a future FastAPI /api/analyze handler needs to call.
It reuses `backend.contract.api_schema`'s Pydantic models directly rather than
redefining them, so the response is guaranteed to match the contract Y1 wrote.

Note on the request side: `analyze_profile` takes a full
`backend.generator.schema.Profile`, not Y1's `AnalyzeRequest`. `AnalyzeRequest`
carries `{profile_id, transactions, months_available}` -- it has no
archetype/split/history-date metadata, but `assess_sufficiency` and
`extract_features` both key off `profile.meta.split` and
`profile.meta.history_start_date` to know the seen-window boundary. Building a
full `Profile` (or an equivalent `ProfileMeta`) out of an `AnalyzeRequest` is
the future FastAPI handler's job, not this module's -- reconstructing that
metadata from a flat transaction list plus `months_available` is a real design
question for that task, not a rubber stamp.

Gate-first, same as Y2 always intended
---------------------------------------
`assess_sufficiency` runs before anything else. A profile that is not FULL
NEVER reaches the model -- there is no code path from LOW_CONFIDENCE or
NOT_ASSESSABLE into `predict_default_probability`. This mirrors exactly how
train_scorecard.py built the training population: only FULL, labeled profiles
ever entered training, so the model was never fit on a trail it would now
refuse to score, and it is never asked to score one either.

The affordability and monthly-cashflow blocks are different: they are direct
arithmetic over the profile's own seen-window transactions (the same
functions Y2 already wrote and tested), not a model prediction, so they are
computed and shown regardless of the gate outcome. That is intentional and
documented in docs/DATA_SCHEMA.md: even a NOT_ASSESSABLE profile's own
recorded income and expenses are simple facts, not a scored judgement.

Dependency-light on purpose: only pydantic and Y1/Y2's own modules. No numpy,
no scikit-learn. A FastAPI server built on this later does not need to ship a
scientific Python stack just to serve predictions from an already-trained
artifact.
"""

from __future__ import annotations

from functools import lru_cache

from backend.common.cashflow import (
    indicative_emi,
    monthly_business_income,
    monthly_gross_cashflow,
)
from backend.common.windows import MonthWindow, seen_window
from backend.contract.api_schema import (
    DISCLAIMER,
    Affordability,
    AnalyzeAggregateRequest,
    AnalyzeResponse,
    ScoreBreakdown,
    Band,
    Confidence,
    MonthlyCashflow,
    Outcome,
    ReasonCode,
    ReasonCodes,
)
from backend.model.authenticity import check_authenticity
from backend.features.feature_engine import extract_features
from backend.features.sufficiency import (
    SufficiencyOutcome,
    SufficiencyResult,
    assess_sufficiency,
    assess_sufficiency_from_counts,
)
from backend.generator.schema import Profile
from backend.model.artifact import (
    ARTIFACT_PATH,
    ScorecardArtifact,
    compute_contributions,
    predict_default_probability,
    vitality_score_from_default_probability,
)
from backend.model.reason_codes import rank_reason_codes

# The indicative EMI range widens with the business's own income volatility
# (income_coefficient_of_variation) rather than a single fixed margin for
# everyone: a steadier business gets a tighter, more confident range; a more
# volatile one gets a wider one. Capped at both ends so the range never
# collapses to a single number nor balloons past what is useful to a lender.
# Falls back to the midpoint of the cap range when volatility itself is
# undefined (fewer than 2 months of income data -- only possible for a
# NOT_ASSESSABLE profile, since this never reaches the model gate).
_EMI_MARGIN_MIN = 0.10
_EMI_MARGIN_MAX = 0.40
_EMI_MARGIN_FALLBACK = (_EMI_MARGIN_MIN + _EMI_MARGIN_MAX) / 2

# outcome mapping: SufficiencyOutcome and the contract's Outcome enum share
# the exact same string values for the two non-scored cases by design (Y2's
# sufficiency.py and Y1's api_schema.py both independently chose
# "LOW_CONFIDENCE" / "NOT_ASSESSABLE"), so this asserts that rather than
# silently relying on it.
assert SufficiencyOutcome.LOW_CONFIDENCE.value == Outcome.LOW_CONFIDENCE.value
assert SufficiencyOutcome.NOT_ASSESSABLE.value == Outcome.NOT_ASSESSABLE.value


@lru_cache(maxsize=1)
def _load_artifact() -> ScorecardArtifact:
    return ScorecardArtifact.load(ARTIFACT_PATH)


def _emi_margin(income_coefficient_of_variation: float | None) -> float:
    if income_coefficient_of_variation is None:
        return _EMI_MARGIN_FALLBACK
    return max(_EMI_MARGIN_MIN, min(_EMI_MARGIN_MAX, income_coefficient_of_variation / 2))


def _affordability_block(
    profile: Profile, window: MonthWindow, feature_values: dict[str, float | None]
) -> Affordability:
    monthly_income = monthly_business_income(profile.transactions_seen, window)
    base_emi = indicative_emi(monthly_income)
    margin = _emi_margin(feature_values.get("income_coefficient_of_variation"))

    months_would_cover = feature_values.get("months_would_cover_emi_of_last_24")
    return Affordability(
        indicative_emi_low=round(base_emi * (1 - margin), 2),
        indicative_emi_high=round(base_emi * (1 + margin), 2),
        # NOTE: pulled directly from Y2's flagship feature, unchanged. For a
        # profile with fewer than 24 seen months (LOW_CONFIDENCE or
        # NOT_ASSESSABLE), this is the count over however many months are
        # actually available, not literally "of the last 24" -- the field
        # name is fixed by the API contract. See docs/DATA_SCHEMA.md.
        months_would_cover_emi_of_last_24=int(months_would_cover)
        if months_would_cover is not None
        else 0,
    )


def _monthly_cashflow_block(profile: Profile, window: MonthWindow) -> list[MonthlyCashflow]:
    totals = monthly_gross_cashflow(profile.transactions_seen, window)
    return [
        MonthlyCashflow(
            month=month,
            inflow=round(values["inflow"], 2),
            outflow=round(values["outflow"], 2),
            net=round(values["inflow"] - values["outflow"], 2),
        )
        for month, values in sorted(totals.items())
    ]


def analyze_profile(
    profile: Profile, artifact: ScorecardArtifact | None = None
) -> AnalyzeResponse:
    """The single entry point a future /api/analyze handler calls.

    `artifact` is normally left unset, which loads and caches the trained
    model from disk. Tests pass a small hand-built artifact instead, so
    scorecard behavior can be asserted deterministically without depending on
    a real training run.
    """
    sufficiency = assess_sufficiency(profile)
    window = seen_window(profile)
    feature_values = extract_features(profile).as_dict()

    affordability = _affordability_block(profile, window, feature_values)
    monthly_cashflow = _monthly_cashflow_block(profile, window)

    # Annotation only -- computed from features that are already extracted,
    # consulted by nothing above, and attached to whichever response is built
    # below. Deliberately independent of the gate outcome: a LOW_CONFIDENCE
    # trail can still be long enough for its smoothness to be worth flagging,
    # and flagging it changes no other field either way.
    authenticity = check_authenticity(
        feature_values.get("income_coefficient_of_variation"),
        n_income_months=len(monthly_business_income(profile.transactions_seen, window)),
    )

    return _assemble_response(
        profile_id=profile.meta.profile_id,
        sufficiency=sufficiency,
        feature_values=feature_values,
        affordability=affordability,
        monthly_cashflow=monthly_cashflow,
        authenticity=authenticity,
        artifact=artifact,
    )


def _assemble_response(
    profile_id: str,
    sufficiency: SufficiencyResult,
    feature_values: dict[str, float | None],
    affordability: Affordability,
    monthly_cashflow: list[MonthlyCashflow],
    authenticity,
    artifact: ScorecardArtifact | None,
) -> AnalyzeResponse:
    """Gate decision + feature values -> a response, for BOTH submission paths.

    Everything from here down is identical whether the features were derived
    from transactions this server received or computed by the caller and
    submitted as aggregates -- the model, the decomposition and the reason
    codes have only ever needed a feature dict. Keeping this shared is what
    makes the two paths provably equivalent rather than coincidentally
    similar (backend/tests/test_analyze_aggregate.py asserts that byte for
    byte on a real demo profile).
    """
    if sufficiency.outcome != SufficiencyOutcome.FULL:
        return AnalyzeResponse(
            profile_id=profile_id,
            outcome=Outcome(sufficiency.outcome.value),
            vitality_score=None,
            band=None,
            confidence=None,
            reason_codes=ReasonCodes(strengths=[], concerns=[]),
            affordability=affordability,
            monthly_cashflow=monthly_cashflow,
            authenticity_check=authenticity,
            coverage_reason=sufficiency.reason,
            disclaimer=DISCLAIMER,
        )

    artifact = artifact or _load_artifact()
    p_default = predict_default_probability(artifact, feature_values)
    vitality_score = vitality_score_from_default_probability(artifact, p_default)
    band = Band(artifact.band_cutoffs.band_for(p_default))

    # Full additive decomposition, not just the ranked reason codes: the UI
    # shows every predictive feature's push so the bars sum to the logit
    # exactly rather than leaving an unexplained remainder.
    contributions = compute_contributions(artifact, feature_values)
    score_breakdown = ScoreBreakdown(
        intercept=float(artifact.intercept),
        contributions={k: float(v) for k, v in contributions.items()},
        logit=float(artifact.intercept + sum(contributions.values())),
        p_default=float(p_default),
    )

    strengths, concerns = rank_reason_codes(artifact, feature_values)
    reason_codes = ReasonCodes(
        strengths=[
            ReasonCode(feature=r.feature, statement=r.statement, contribution=r.contribution)
            for r in strengths
        ],
        concerns=[
            ReasonCode(feature=r.feature, statement=r.statement, contribution=r.contribution)
            for r in concerns
        ],
    )

    return AnalyzeResponse(
        profile_id=profile_id,
        outcome=Outcome.SCORED,
        vitality_score=float(vitality_score),
        band=band,
        # Every profile that reaches this branch passed the FULL gate, so
        # there is only one confidence level a scored result can carry.
        # LOW_CONFIDENCE/NOT_ASSESSABLE profiles never get a confidence value
        # at all (see above) -- the gate outcome already says what it would.
        confidence=Confidence.HIGH,
        reason_codes=reason_codes,
        score_breakdown=score_breakdown,
        affordability=affordability,
        monthly_cashflow=monthly_cashflow,
        authenticity_check=authenticity,
        coverage_reason=None,
        disclaimer=DISCLAIMER,
    )


def analyze_from_aggregates(
    request: AnalyzeAggregateRequest, artifact: ScorecardArtifact | None = None
) -> AnalyzeResponse:
    """Score a caller-computed aggregate submission (POST /api/analyze-aggregate).

    The privacy-minimized path: no transaction dates, amounts, counterparties
    or channels reach this server, so there is no bank-level detail here to
    log, cache or leak. Everything below the gate is the SAME code
    `analyze_profile` runs -- `_assemble_response` is shared, so the model,
    the additive decomposition and the reason codes cannot drift between the
    two paths.

    What changes is only where the three transaction-derived inputs come
    from:

    * the gate reads submitted per-month counts (`assess_sufficiency_from_counts`)
      instead of scanning a transaction list;
    * affordability's EMI is the median of submitted `business_income`
      instead of `monthly_business_income(...)`;
    * the cashflow chart uses submitted `gross_inflow`/`gross_outflow`
      instead of `monthly_gross_cashflow(...)`.

    THE TRUST BOUNDARY MOVES, AND NOT IN THE CALLER'S FAVOUR. On the
    transaction path the server derives every feature itself, so a feature
    cannot disagree with the data behind it. Here the caller asserts both,
    and the server cannot recompute either from what it was given. See the
    "Privacy architecture" section of backend/api/README.md -- this endpoint
    minimizes what is disclosed, it does not verify what is claimed.
    """
    by_month = {m.month: m for m in request.months}

    sufficiency = assess_sufficiency_from_counts(
        {month: m.real_transaction_count for month, m in by_month.items()}
    )

    # model_dump() rather than a hand-written dict: the field names are
    # FeatureSet's own, so this stays aligned with `extract_features(...)
    # .as_dict()` without a second list of names to keep in sync.
    feature_values: dict[str, float | None] = dict(request.features.model_dump())

    business_income = {month: m.business_income for month, m in by_month.items()}
    base_emi = indicative_emi(business_income)
    margin = _emi_margin(feature_values.get("income_coefficient_of_variation"))
    months_would_cover = feature_values.get("months_would_cover_emi_of_last_24")
    affordability = Affordability(
        indicative_emi_low=round(base_emi * (1 - margin), 2),
        indicative_emi_high=round(base_emi * (1 + margin), 2),
        months_would_cover_emi_of_last_24=int(months_would_cover)
        if months_would_cover is not None
        else 0,
    )

    monthly_cashflow = [
        MonthlyCashflow(
            month=month,
            inflow=round(m.gross_inflow, 2),
            outflow=round(m.gross_outflow, 2),
            net=round(m.gross_inflow - m.gross_outflow, 2),
        )
        for month, m in sorted(by_month.items())
    ]

    # Run on EVERY aggregate request, regardless of gate outcome -- a
    # self-reported feature is easier to fabricate than a transaction trail
    # the server derived itself, so this is the one cross-check that still
    # applies when the raw data is withheld.
    #
    # The minimum-months guard inside check_authenticity still applies, and
    # deliberately so: it is a statistical-power limit, not a trust one. A CV
    # computed over four months is a low-power estimate no matter who
    # computed it, and flagging it would be a false positive rather than a
    # fraud catch. Overriding it here would also break equivalence with
    # /api/analyze for short windows, which is the property the tests pin.
    authenticity = check_authenticity(
        feature_values.get("income_coefficient_of_variation"),
        n_income_months=len(by_month),
    )

    return _assemble_response(
        profile_id=request.profile_id,
        sufficiency=sufficiency,
        feature_values=feature_values,
        affordability=affordability,
        monthly_cashflow=monthly_cashflow,
        authenticity=authenticity,
        artifact=artifact,
    )
