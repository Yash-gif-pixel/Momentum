"""The sufficiency gate: decide whether a trail can carry a score at all.

This runs BEFORE any scoring is attempted. The point is to refuse to produce a
confident number from a trail that cannot support one -- a thin file should
come back as "we cannot assess this" rather than as a low score, because a low
score reads as "this business is bad" when the truth is "we do not have enough
of their history yet". Conflating those two is precisely how thin-file
businesses get locked out of credit.

Thresholds are this prototype's own design choice. They are argued below and
in docs/DATA_SCHEMA.md, and are NOT drawn from any regulatory standard or
published methodology.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

from backend.common.cashflow import is_noise
from backend.common.windows import seen_window
from backend.generator.schema import Profile

# --- Thresholds -------------------------------------------------------------
#
# Why 6 months and not 3?
#   These businesses are strongly seasonal: a monsoon dip and a festival spike
#   are both normal and both last roughly a quarter. A 3-month window can land
#   entirely inside one of them, so it measures the season rather than the
#   business -- a vendor assessed across a single festival looks exceptional,
#   and the same vendor assessed across a single monsoon looks failing. Six
#   months is the shortest window that necessarily spans more than one seasonal
#   regime, so it is the shortest window from which a trend means anything.
#
# Why 12 months for full confidence?
#   A full seasonal cycle takes twelve months, so full confidence needs more
#   than twelve months of history: at exactly twelve the window closes the
#   cycle but leaves nothing to compare it against, so no month can yet be
#   read against its own counterpart a year earlier. Twelve months and under
#   is therefore LOW_CONFIDENCE, and FULL begins above it. Below the cycle,
#   growth and volatility features are still measurable but are partly
#   reporting where in the year the window happened to fall -- hence "low
#   confidence" rather than "not assessable".
MIN_MONTHS_ASSESSABLE = 6
MIN_MONTHS_FULL_CONFIDENCE = 12

# Why ~8 transactions/month?
#   Below roughly two transactions a week there is no rhythm left to measure:
#   regularity, dry streaks and volatility all collapse into noise, and a
#   single missed week swings them wildly. Eight per month is the floor at
#   which a weekly pattern is even observable.
#
# Why 15 for full confidence?
#   Between 8 and 15 a month the trail is real but thin -- roughly two to three
#   transactions a week. Features compute, but each one rests on few enough
#   observations that a couple of missing entries materially move them, so the
#   result is reported with low confidence rather than refused.
MIN_TX_PER_MONTH_ASSESSABLE = 8.0
MIN_TX_PER_MONTH_FULL_CONFIDENCE = 15.0


class SufficiencyOutcome(str, Enum):
    NOT_ASSESSABLE = "NOT_ASSESSABLE"
    LOW_CONFIDENCE = "LOW_CONFIDENCE"
    FULL = "FULL"


@dataclass(frozen=True)
class SufficiencyResult:
    outcome: SufficiencyOutcome
    months_available: int
    transactions_per_month: float
    reason: str

    @property
    def is_full_assessment_eligible(self) -> bool:
        return self.outcome == SufficiencyOutcome.FULL


def assess_sufficiency(profile: Profile) -> SufficiencyResult:
    """Classify a profile's trail before any scoring is attempted.

    Density counts only real business transactions: settlement sweeps and
    rounding artifacts are excluded, so a trail cannot clear the density bar
    on noise alone. Assessment covers the seen window only -- the held-out
    months are not part of what a lender would have.
    """
    window = seen_window(profile)
    months = window.n_months
    real_transactions = [tx for tx in profile.transactions_seen if not is_noise(tx)]
    per_month = (len(real_transactions) / months) if months > 0 else 0.0
    return classify_sufficiency(months, per_month)


def assess_sufficiency_from_counts(
    real_transactions_per_month: dict[str, int],
) -> SufficiencyResult:
    """The same gate, for a caller who submits per-month counts instead of
    transactions (see POST /api/analyze-aggregate).

    Deliberately NOT implemented by reconstructing a Profile out of synthetic
    transactions: that would invent dates, amounts and counterparties this
    path exists precisely to avoid receiving, and any of those inventions
    could drift from what the real gate measures without a test noticing.

    Both entry points funnel into `classify_sufficiency`, so the thresholds
    and the wording of `reason` have exactly one implementation. The caller's
    counts must already exclude noise -- the server cannot tell settlement
    sweeps from real transactions when it never sees them, which is one of
    the trust limits documented in backend/api/README.md.

    Every month of the window must be present, including months with no
    activity at all (as a 0), matching how `iter_month_keys` yields empty
    months. A caller that omits its silent months would otherwise report a
    denser trail than it has.
    """
    months = len(real_transactions_per_month)
    total = sum(real_transactions_per_month.values())
    per_month = (total / months) if months > 0 else 0.0
    return classify_sufficiency(months, per_month)


def classify_sufficiency(months: int, per_month: float) -> SufficiencyResult:
    """The gate's actual decision, over the two numbers it really depends on.

    Split out from `assess_sufficiency` so the aggregate submission path can
    reach the identical thresholds and the identical `reason` strings without
    duplicating either as literals in a second place.
    """
    thin_history = months < MIN_MONTHS_ASSESSABLE
    thin_density = per_month < MIN_TX_PER_MONTH_ASSESSABLE
    if thin_history or thin_density:
        reasons = []
        if thin_history:
            reasons.append(
                f"only {months} months of history "
                f"(minimum {MIN_MONTHS_ASSESSABLE} to span more than one season)"
            )
        if thin_density:
            reasons.append(
                f"only {per_month:.1f} transactions/month "
                f"(minimum {MIN_TX_PER_MONTH_ASSESSABLE:.0f} for a readable rhythm)"
            )
        return SufficiencyResult(
            outcome=SufficiencyOutcome.NOT_ASSESSABLE,
            months_available=months,
            transactions_per_month=per_month,
            reason="Not assessable: " + "; ".join(reasons) + ".",
        )

    short_history = months <= MIN_MONTHS_FULL_CONFIDENCE
    sparse_trail = per_month <= MIN_TX_PER_MONTH_FULL_CONFIDENCE
    if short_history or sparse_trail:
        reasons = []
        if short_history:
            reasons.append(
                f"{months} months of history does not clear a full "
                f"{MIN_MONTHS_FULL_CONFIDENCE}-month seasonal cycle with a prior "
                "year to compare against"
            )
        if sparse_trail:
            reasons.append(
                f"{per_month:.1f} transactions/month is a sparse trail "
                f"(under {MIN_TX_PER_MONTH_FULL_CONFIDENCE:.0f})"
            )
        return SufficiencyResult(
            outcome=SufficiencyOutcome.LOW_CONFIDENCE,
            months_available=months,
            transactions_per_month=per_month,
            reason="Low confidence: " + "; ".join(reasons) + ".",
        )

    return SufficiencyResult(
        outcome=SufficiencyOutcome.FULL,
        months_available=months,
        transactions_per_month=per_month,
        reason=(
            f"Full assessment: {months} months of history at "
            f"{per_month:.1f} transactions/month."
        ),
    )
