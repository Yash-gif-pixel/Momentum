"""Derives the ground-truth label from the HELD-OUT window (months 25-30).

Leakage boundary
----------------
This module reads `profile.transactions_holdout` and nothing else, and checks
every transaction against the held-out window before using it. It never
imports `feature_engine` and never touches `transactions_seen`.

The one quantity it needs from the seen window -- the indicative EMI -- is
passed in as a plain number by the caller rather than recomputed here. That is
deliberate: the EMI is what a lender would have sized up front from months
1-24, so recomputing it from held-out income would leak the future into both
the feature and the label, and would also let the label drift away from the
`months_would_cover_emi_of_last_24` feature it is supposed to mirror.

Label definition
----------------
Behaviourally grounded, not an arbitrary cutoff. For each of the 6 held-out
months, ask the question a borrower actually faces: after paying the month's
essential running costs, was there enough income left to service the EMI?

    covered(month)  <=>  income(month) >= indicative_emi + essentials(month)

A profile is labeled "default" (1) when that fails in 2 or more of the 6
months. One bad month is a normal shock for a seasonal micro-business and
should not brand it a defaulter; two or more is a pattern of being unable to
carry the obligation.

Where this label may NOT go
---------------------------
The label is ground truth for validation only. It must never be written into
the feature table or reach a model as an input -- `build_feature_table.py`
writes it to a separate, gitignored file and asserts it is absent from the
feature table.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

from backend.common.cashflow import (
    monthly_business_income,
    monthly_essential_expenses,
)
from backend.common.windows import assert_within_window, holdout_window
from backend.generator.schema import Profile

# A profile is labeled "default" when it fails to cover the EMI in at least
# this many of the held-out months. One shortfall is a seasonal shock; two is
# a pattern.
DEFAULT_THRESHOLD_MONTHS = 2


@dataclass(frozen=True)
class LabelResult:
    """Ground truth for validation only -- never a model input."""

    profile_id: str
    label: int  # 1 == default, 0 == no default
    months_failed: int
    months_evaluated: int
    indicative_emi: float
    monthly_shortfalls: dict[str, float]

    @property
    def is_default(self) -> bool:
        return self.label == 1


def derive_label(profile: Profile, indicative_emi: float) -> Optional[LabelResult]:
    """Label a profile from its held-out months.

    `indicative_emi` must have been computed from the SEEN window (months
    1-24) by `backend.common.cashflow.indicative_emi`.

    Returns None when the profile has no held-out window at all -- the
    short-history edge cases have nothing held back, so they cannot be labeled
    and are excluded from validation rather than being guessed at.
    """
    window = holdout_window(profile)
    if window is None:
        return None

    # A business with no measurable income across months 1-24 cannot be sized
    # for an obligation at all, so there is nothing to test repayment capacity
    # against. Labeling it 0 would be badly wrong: with an EMI of zero the
    # coverage test degenerates to `income >= essentials`, and a dead business
    # with neither would score as certain to repay.
    if indicative_emi <= 0:
        return None

    # NOTE: an empty holdout list is NOT unlabelable. A profile whose held-out
    # window exists but contains no transactions is a business that stopped
    # trading completely -- the most severe default there is. It must fall
    # through and be scored as six failed months, not silently dropped.
    transactions = profile.transactions_holdout

    # Leakage tripwire: every transaction must sit inside months 25-30.
    assert_within_window(transactions, window, caller="label_engine.derive_label")

    monthly_income = monthly_business_income(transactions, window)
    monthly_essentials = monthly_essential_expenses(transactions, window)

    shortfalls: dict[str, float] = {}
    months_failed = 0
    for key, income in monthly_income.items():
        required = indicative_emi + monthly_essentials.get(key, 0.0)
        gap = required - income
        shortfalls[key] = gap
        if gap > 0:
            months_failed += 1

    return LabelResult(
        profile_id=profile.meta.profile_id,
        label=1 if months_failed >= DEFAULT_THRESHOLD_MONTHS else 0,
        months_failed=months_failed,
        months_evaluated=len(monthly_income),
        indicative_emi=indicative_emi,
        monthly_shortfalls=shortfalls,
    )
