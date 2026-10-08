"""Plain-language reason codes: one template pair per feature, ranked by contribution.

Per feature, a template pair supplies:
  - `positive(value)`  a specific sentence for when this feature is a strength
  - `negative(value)`  a specific sentence for when this feature is a concern
  - `is_favorable(value)`  a plain domain judgement of whether this raw number
    looks good for the business, independent of any model

That third function exists because of something the trained model actually
does: see "Coefficient sign instability" below. Every template fills in the
profile's real number -- never a placeholder -- so every statement is
specific and checkable.

Contribution and ranking
-------------------------
For each of the 10 predictive features (see backend.model.artifact --
digital_share and cash_share are excluded from the model and therefore never
produce a contribution), contribution = (standardized coefficient) x
(standardized feature value). Positive pushes toward vitality/strong_candidate
(a strength); negative pushes toward default risk (a concern). Candidates are
ranked by |contribution|, largest first; the top 3 coherent strengths and top
3 coherent concerns are returned. Fewer than 3 are returned rather than padded
with filler when fewer qualify -- see below.

Coefficient sign instability -- a real, checked finding
---------------------------------------------------------
Two of the ten predictive features -- `pct_weeks_with_income` and
`longest_dry_streak_days` -- carry almost no independent signal once a
profile has already cleared the FULL sufficiency gate (the gate itself is
what filters for a trail with a readable weekly rhythm; among profiles that
already passed it, the remaining variance in these two numbers correlates
only weakly, near-zero, or even backwards with the held-out default label:
r = +0.07 and r = -0.02 respectively, verified against the labeled dataset).
`worst_monthly_dip_pct` is also affected in the current fit, driven by
collinearity with the growth-trend features rather than a weak signal on its
own (its own univariate correlation with default, r = +0.31, IS in the
intuitive direction). A logistic regression trained on all 10 features
together can assign any of these three a coefficient sign that disagrees with
plain domain intuition -- more weeks with income should never look like a
concern, and it does not fixing this by hand-picking a "corrected" sign,
because the multivariate coefficient is not simply wrong: it is the model's
honestly-fit partial effect controlling for the other 9 correlated features.

What would go wrong un-mitigated: for a profile with 98% of weeks earning
income, if the coefficient's fitted sign happens to make that look like a
downward push on vitality, an ungated pipeline would show "Income arrived in
only 98% of weeks" as a CONCERN -- a sentence that is numerically correct and
reads as nonsense.

The fix here is `is_favorable`: before a candidate is accepted into either
list, its own raw value must agree with the bucket the model's contribution
sign is proposing (a positive contribution must pair with a raw value this
feature's own domain logic calls favorable, and a negative contribution with
a value it calls unfavorable). A candidate that disagrees is skipped, not
relabeled -- in practice this means `worst_monthly_dip_pct` in particular
almost never survives to become a reason code under the current fit, since
its sign is flipped for virtually every profile. That is the CORRECT
behaviour: silently omitting an untrustworthy explanation beats manufacturing
a backwards-reading one. See docs/DATA_SCHEMA.md "Reason codes" for the full
write-up and the actual per-feature frequency this produces across the
dataset.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, Optional

from backend.features.feature_engine import FEATURE_NAMES
from backend.model.artifact import PREDICTIVE_FEATURES, ScorecardArtifact, compute_contributions

Formatter = Callable[[float], str]
FavorabilityCheck = Callable[[float], bool]


@dataclass(frozen=True)
class ReasonTemplate:
    positive: Formatter
    negative: Formatter
    is_favorable: FavorabilityCheck
    higher_is_better: bool  # read by train_scorecard.py's sign-coherence diagnostic


def _pct(value: float) -> float:
    return value * 100.0


TEMPLATES: dict[str, ReasonTemplate] = {
    "pct_weeks_with_income": ReasonTemplate(
        positive=lambda v: f"Income arrived in {_pct(v):.0f}% of weeks — a steady trading rhythm.",
        negative=lambda v: f"Income arrived in only {_pct(v):.0f}% of weeks — a patchy trading rhythm.",
        is_favorable=lambda v: v >= 0.75,
        higher_is_better=True,
    ),
    "income_coefficient_of_variation": ReasonTemplate(
        positive=lambda v: f"Monthly income varies by about {_pct(v):.0f}% of its own average — consistent earnings.",
        negative=lambda v: f"Monthly income swings by about {_pct(v):.0f}% of its own average — volatile earnings.",
        is_favorable=lambda v: v <= 0.5,
        higher_is_better=False,
    ),
    "longest_dry_streak_days": ReasonTemplate(
        positive=lambda v: f"The longest stretch without any income was just {v:.0f} days.",
        negative=lambda v: f"The business went {v:.0f} days at a stretch without any income.",
        is_favorable=lambda v: v <= 14,
        higher_is_better=False,
    ),
    # trend_last_6_months / year_over_year_change: positive()'s v<0 branch and
    # negative()'s v>=0 branch are unreachable via rank_reason_codes (it only
    # calls positive() when is_favorable(v), i.e. v>=0, and negative() only
    # when not is_favorable(v), i.e. v<0). Kept anyway because TEMPLATES is a
    # public dict these tests (and any future caller) can call directly,
    # bypassing that gate -- rendering "Income is up -5%" would be wrong, and
    # the fallback wording is the fix, not a dead branch to delete.
    "trend_last_6_months": ReasonTemplate(
        positive=lambda v: (
            f"Income is up {_pct(v):.0f}% versus the same period a year earlier — growing."
            if v >= 0
            else f"Income's decline has eased to {_pct(abs(v)):.0f}% versus the same period a year earlier."
        ),
        negative=lambda v: (
            f"Income is down {_pct(abs(v)):.0f}% versus the same period a year earlier — shrinking."
            if v < 0
            else f"Income growth has slowed to just {_pct(v):.0f}% versus the same period a year earlier."
        ),
        is_favorable=lambda v: v >= 0,
        higher_is_better=True,
    ),
    "year_over_year_change": ReasonTemplate(
        positive=lambda v: (
            f"Income is up {_pct(v):.0f}% over the last 12 months versus the 12 before that — growing."
            if v >= 0
            else f"Income's year-on-year decline has eased to {_pct(abs(v)):.0f}%."
        ),
        negative=lambda v: (
            f"Income is down {_pct(abs(v)):.0f}% over the last 12 months versus the 12 before that — shrinking."
            if v < 0
            else f"Income growth has slowed to just {_pct(v):.0f}% year-on-year."
        ),
        is_favorable=lambda v: v >= 0,
        higher_is_better=True,
    ),
    "expense_to_income_ratio": ReasonTemplate(
        positive=lambda v: f"The business keeps about {_pct(max(0.0, 1 - v)):.0f}% of every rupee earned after running costs.",
        negative=lambda v: f"Running costs absorb about {_pct(v):.0f}% of every rupee earned, leaving a thin margin.",
        is_favorable=lambda v: v <= 0.6,
        higher_is_better=False,
    ),
    "ontime_bill_payment_rate": ReasonTemplate(
        positive=lambda v: f"Rent and utility bills were paid on time {_pct(v):.0f}% of the time.",
        negative=lambda v: f"Rent and utility bills were paid on time only {_pct(v):.0f}% of the time.",
        is_favorable=lambda v: v >= 0.75,
        higher_is_better=True,
    ),
    "cash_buffer_days": ReasonTemplate(
        positive=lambda v: f"The typical month's surplus could cover about {v:.0f} days of running costs.",
        negative=lambda v: (
            f"The typical month burns cash rather than saving it — a shortfall equivalent to "
            f"{abs(v):.0f} days of running costs."
            if v < 0
            else f"The typical month's surplus covers only about {v:.0f} days of running costs — a thin buffer."
        ),
        is_favorable=lambda v: v >= 15,
        higher_is_better=True,
    ),
    "worst_monthly_dip_pct": ReasonTemplate(
        positive=lambda v: f"Even in its weakest month, income only dipped {_pct(v):.0f}% below the typical month.",
        negative=lambda v: f"In its weakest month, income dipped {_pct(v):.0f}% below the typical month.",
        is_favorable=lambda v: v <= 0.4,
        higher_is_better=False,
    ),
    "months_would_cover_emi_of_last_24": ReasonTemplate(
        positive=lambda v: f"Income would have covered an indicative loan payment in {v:.0f} of the last 24 months.",
        negative=lambda v: f"Income would have covered an indicative loan payment in only {v:.0f} of the last 24 months.",
        is_favorable=lambda v: v >= 18,
        higher_is_better=True,
    ),
    # Informational only -- see artifact.py's PREDICTIVE_FEATURES. These two
    # never receive a coefficient and therefore never produce a contribution,
    # so is_favorable is never consulted for them; the templates exist to
    # satisfy "one template per feature, all 12" and remain independently
    # testable, in case a future task wants to surface them as plain
    # informational context (never as a scored reason code).
    "digital_share": ReasonTemplate(
        positive=lambda v: f"{_pct(v):.0f}% of transaction value moved through digital channels (UPI/NEFT/card/cheque).",
        negative=lambda v: f"Only {_pct(v):.0f}% of transaction value moved through digital channels — most activity is cash.",
        is_favorable=lambda v: v >= 0.5,
        higher_is_better=True,
    ),
    "cash_share": ReasonTemplate(
        positive=lambda v: f"{_pct(v):.0f}% of transaction value is in cash — a normal pattern for this kind of business, not a mark against it.",
        negative=lambda v: f"{_pct(v):.0f}% of transaction value is in cash, which is simply how this business trades — never treated as a mark against it.",
        is_favorable=lambda v: True,
        higher_is_better=False,
    ),
}

assert set(TEMPLATES) == set(FEATURE_NAMES), "every one of the 12 features must have a reason-code template"
assert set(PREDICTIVE_FEATURES) <= set(TEMPLATES), "every predictive feature must have a template"


@dataclass(frozen=True)
class RankedReasonCode:
    feature: str
    statement: str
    contribution: float


def rank_reason_codes(
    artifact: ScorecardArtifact,
    feature_values: dict[str, Optional[float]],
    max_per_side: int = 3,
) -> tuple[list[RankedReasonCode], list[RankedReasonCode]]:
    """Top strengths and concerns for one profile.

    Never pads with filler: if fewer than `max_per_side` candidates survive
    the coherence check on a given side, fewer are returned.
    """
    contributions = compute_contributions(artifact, feature_values)
    ranked = sorted(contributions.items(), key=lambda kv: -abs(kv[1]))

    strengths: list[RankedReasonCode] = []
    concerns: list[RankedReasonCode] = []

    for feature, contribution in ranked:
        if len(strengths) >= max_per_side and len(concerns) >= max_per_side:
            break
        if contribution == 0.0:
            continue

        value = feature_values.get(feature)
        if value is None:
            continue
        template = TEMPLATES[feature]

        if contribution > 0 and len(strengths) < max_per_side:
            if template.is_favorable(value):
                strengths.append(
                    RankedReasonCode(
                        feature=feature,
                        statement=template.positive(value),
                        contribution=contribution,
                    )
                )
            # else: statistically a "strength" but the raw value itself does
            # not look favorable -- a coefficient-sign artifact (see module
            # docstring). Skipped rather than shown backwards.
        elif contribution < 0 and len(concerns) < max_per_side:
            if not template.is_favorable(value):
                concerns.append(
                    RankedReasonCode(
                        feature=feature,
                        statement=template.negative(value),
                        contribution=contribution,
                    )
                )

    return strengths, concerns
