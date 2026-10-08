"""Extracts the 12 model features from a profile's SEEN history (months 1-24).

Hard rule enforced by this module: every feature is computed from
`profile.transactions_seen` only, and those transactions are checked against
the seen window by `assert_within_window` before anything is computed. If a
future edit routes held-out (months 25-30) data in here, extraction raises
`LeakageError` rather than silently producing an optimistic feature.

Features are grouped into the six families below, and `FEATURE_FAMILIES` maps
each family to its feature names so downstream scoring can populate the API
contract's `reason_codes.feature` values from the same vocabulary.

Any feature that is genuinely undefined for a profile is returned as None
rather than a fabricated zero -- e.g. year-over-year change needs two full
years of history, which a short-history profile does not have. A None here
means "not computable from this trail", which is information the sufficiency
gate and the eventual scorer should both respect.
"""

from __future__ import annotations

from dataclasses import dataclass, asdict
from datetime import timedelta
from statistics import StatisticsError, linear_regression, median, stdev
from typing import Optional

from backend.common.cashflow import (
    BILL_ON_TIME_DAY_OF_MONTH,
    indicative_emi,
    is_noise,
    monthly_business_income,
    monthly_essential_expenses,
    monthly_total_expenses,
    months_covering_emi,
)
from backend.common.windows import (
    MonthWindow,
    assert_within_window,
    iter_week_keys,
    seen_window,
    week_key,
)
from backend.generator.schema import Channel, CounterpartyType, Direction, Profile, Transaction

# ---------------------------------------------------------------------------
# Fairness by design: fields that must never become features
# ---------------------------------------------------------------------------
#
# Credit models built on alternative data can launder demographic proxies into
# a score without anyone intending it. This list is the explicit, testable
# statement of what is off-limits. `backend/tests/test_fairness.py` parses this
# module's AST and asserts none of these names is ever read as an attribute,
# so adding a banned field to a feature breaks the build rather than quietly
# shipping a proxy.

# Fields that exist in the current schema but must not drive a feature.
EXCLUDED_FIELDS_PRESENT_IN_SCHEMA: tuple[str, ...] = (
    # Generator ground truth / internals -- using these would be self-fulfilling
    # label leakage, not a real signal a lender could observe.
    "latent_health_tier",
    "is_cash_heavy_edge_case",
    "is_short_history_edge_case",
    # Free-text transaction memo. Carries counterparty VPA handles and personal
    # names, which proxy for identity, community and geography.
    "note",
)

# Fields that do NOT exist in the schema today and must never be introduced as
# features. Listed so the prohibition is on record before anyone adds them.
EXCLUDED_FIELDS_RESERVED: tuple[str, ...] = (
    # Geography -- proxies for caste, religion, income class and communal risk.
    "pincode",
    "pin_code",
    "postal_code",
    "district",
    "state",
    "city",
    "village",
    "ward",
    "latitude",
    "longitude",
    "geo",
    "address",
    "region",
    # Demographics -- direct protected attributes.
    "gender",
    "sex",
    "age",
    "date_of_birth",
    "dob",
    "caste",
    "religion",
    "community",
    "language",
    "mother_tongue",
    "marital_status",
    "education",
    "disability",
    # Identity documents -- identify the person, and their issuing patterns
    # correlate with demographics.
    "aadhaar",
    "pan",
    "voter_id",
    "borrower_name",
    "applicant_name",
    # Merchant classification -- MCC-style codes proxy for the demographics of
    # who runs and who patronises a given trade.
    "merchant_category_code",
    "mcc",
    "merchant_category",
    "merchant_name",
    "business_name",
)

EXCLUDED_FIELDS: tuple[str, ...] = (
    EXCLUDED_FIELDS_PRESENT_IN_SCHEMA + EXCLUDED_FIELDS_RESERVED
)

# ---------------------------------------------------------------------------
# Feature vocabulary
# ---------------------------------------------------------------------------

FEATURE_FAMILIES: dict[str, tuple[str, ...]] = {
    "regularity": (
        "pct_weeks_with_income",
        "income_coefficient_of_variation",
        "longest_dry_streak_days",
    ),
    "growth": (
        "trend_last_6_months",
        "year_over_year_change",
    ),
    "discipline": (
        "expense_to_income_ratio",
        "ontime_bill_payment_rate",
    ),
    "resilience": (
        "cash_buffer_days",
        "worst_monthly_dip_pct",
    ),
    "affordability": ("months_would_cover_emi_of_last_24",),
    "trail": (
        "digital_share",
        "cash_share",
    ),
}

FEATURE_NAMES: tuple[str, ...] = tuple(
    name for family in FEATURE_FAMILIES.values() for name in family
)

DIGITAL_CHANNELS: frozenset[Channel] = frozenset(
    {Channel.UPI, Channel.NEFT, Channel.CARD, Channel.CHEQUE}
)

# Growth features need a minimum amount of history to mean anything.
MIN_MONTHS_FOR_TREND = 6
MIN_MONTHS_FOR_YOY = 24


@dataclass(frozen=True)
class FeatureSet:
    """The 12 features, grouped by family in declaration order."""

    # -- Regularity --------------------------------------------------------
    pct_weeks_with_income: Optional[float]
    income_coefficient_of_variation: Optional[float]
    longest_dry_streak_days: Optional[int]
    # -- Growth ------------------------------------------------------------
    trend_last_6_months: Optional[float]
    year_over_year_change: Optional[float]
    # -- Discipline --------------------------------------------------------
    expense_to_income_ratio: Optional[float]
    ontime_bill_payment_rate: Optional[float]
    # -- Resilience --------------------------------------------------------
    cash_buffer_days: Optional[float]
    worst_monthly_dip_pct: Optional[float]
    # -- Affordability (flagship) -----------------------------------------
    months_would_cover_emi_of_last_24: Optional[int]
    # -- Trail -------------------------------------------------------------
    # Informational only, never used to penalize cash-heavy businesses.
    digital_share: Optional[float]
    cash_share: Optional[float]

    def as_dict(self) -> dict[str, Optional[float]]:
        return asdict(self)


# ---------------------------------------------------------------------------
# Family 5: Affordability (flagship -- implemented and tested first)
# ---------------------------------------------------------------------------


def _months_would_cover_emi(
    monthly_income: dict[str, float], monthly_essentials: dict[str, float]
) -> int:
    """How many of the seen months could have carried an indicative EMI.

    The flagship feature. Uses the same EMI definition as the label engine
    (20% of median monthly income, `cashflow.indicative_emi`) but evaluates it
    over months 1-24 instead of the held-out window, so the feature and the
    label measure the same thing at two different points in time.

    WARNING -- this is an ABSOLUTE COUNT, not a rate, because the API contract
    fixes it as `months_would_cover_emi_of_last_24: int`. It is therefore
    bounded by how much history a profile has: a business that covered the EMI
    in all 11 of its 11 months scores 11, below a 24-month business that missed
    four. Ranking profiles on the raw count would penalize a thin file for
    being thin, which is the exact exclusion this project exists to undo.

    Downstream scoring must either restrict comparisons to profiles the
    sufficiency gate passed as FULL (all of which have the same 24-month
    window), or normalize by the window length. The denominator is carried
    alongside the feature in the feature table as
    `sufficiency_months_available`, so the rate is always recoverable without
    adding a thirteenth feature.
    """
    emi = indicative_emi(monthly_income)
    return months_covering_emi(monthly_income, monthly_essentials, emi)


# ---------------------------------------------------------------------------
# Family 1: Regularity
# ---------------------------------------------------------------------------


def _pct_weeks_with_income(
    transactions: list[Transaction], window: MonthWindow
) -> Optional[float]:
    """Share of calendar weeks in the window containing real trading income."""
    all_weeks = set(iter_week_keys(window))
    if not all_weeks:
        return None
    earning_weeks = {
        week_key(tx.date)
        for tx in transactions
        if not is_noise(tx)
        and tx.direction == Direction.IN
        and tx.counterparty_type == CounterpartyType.CUSTOMER
    }
    return len(earning_weeks & all_weeks) / len(all_weeks)


def _income_coefficient_of_variation(
    monthly_income: dict[str, float],
) -> Optional[float]:
    """Volatility of monthly income, normalised by its own mean (sample CV)."""
    values = list(monthly_income.values())
    if len(values) < 2:
        return None
    mean = sum(values) / len(values)
    if mean <= 0:
        return None
    try:
        return stdev(values) / mean
    except StatisticsError:
        return None


def _longest_dry_streak_days(
    transactions: list[Transaction], window: MonthWindow
) -> int:
    """Longest unbroken run of calendar days with no trading income.

    Counts leading and trailing dry periods too, so a trail that simply stops
    earning halfway through is penalised rather than looking merely 'sparse'.
    """
    earning_days = {
        tx.date
        for tx in transactions
        if not is_noise(tx)
        and tx.direction == Direction.IN
        and tx.counterparty_type == CounterpartyType.CUSTOMER
    }
    longest = 0
    current = 0
    day = window.start
    while day <= window.end:
        if day in earning_days:
            current = 0
        else:
            current += 1
            longest = max(longest, current)
        day += timedelta(days=1)
    return longest


# ---------------------------------------------------------------------------
# Family 2: Growth
# ---------------------------------------------------------------------------


def _trend_last_6_months(monthly_income: dict[str, float]) -> Optional[float]:
    """Recent momentum: how the last 6 months compare, as a fraction.

    These businesses are strongly seasonal -- a street food vendor's monsoon
    is always weaker than its festival season. Measuring a raw 6-month slope
    therefore reports whichever season the window happens to end in: on this
    dataset's demo profile, a visibly growing business scored -3% simply
    because months 19-24 end in the monsoon.

    So when there is enough history (18+ months) this compares the last 6
    months against *the same 6 calendar months a year earlier* -- this monsoon
    against last monsoon -- which cancels seasonality and leaves real growth.

    Below 18 months that comparison is impossible, so it falls back to a
    least-squares slope over the last 6 months, normalised by their mean
    (fractional change per month). The fallback is seasonality-exposed and is
    flagged as such in docs/DATA_SCHEMA.md.
    """
    values = list(monthly_income.values())
    if len(values) < MIN_MONTHS_FOR_TREND:
        return None

    recent = values[-MIN_MONTHS_FOR_TREND:]
    if len(values) >= MIN_MONTHS_FOR_TREND + 12:
        # Season-matched: same 6 calendar months, one year earlier.
        prior = values[-(MIN_MONTHS_FOR_TREND + 12) : -12]
        prior_total = sum(prior)
        if prior_total > 0:
            return (sum(recent) - prior_total) / prior_total

    mean = sum(recent) / len(recent)
    if mean <= 0:
        return None
    slope, _intercept = linear_regression(range(len(recent)), recent)
    return slope / mean


def _year_over_year_change(monthly_income: dict[str, float]) -> Optional[float]:
    """Second-12-months income versus first-12-months income, as a fraction."""
    values = list(monthly_income.values())
    if len(values) < MIN_MONTHS_FOR_YOY:
        return None
    recent = values[-12:]
    prior = values[-24:-12]
    prior_total = sum(prior)
    if prior_total <= 0:
        return None
    return (sum(recent) - prior_total) / prior_total


# ---------------------------------------------------------------------------
# Family 3: Discipline
# ---------------------------------------------------------------------------


def _expense_to_income_ratio(
    monthly_income: dict[str, float], monthly_expenses: dict[str, float]
) -> Optional[float]:
    total_income = sum(monthly_income.values())
    if total_income <= 0:
        return None
    return sum(monthly_expenses.values()) / total_income


def _ontime_bill_payment_rate(transactions: list[Transaction]) -> Optional[float]:
    """Share of rent/utility bills paid by the on-time cutoff day.

    Reversals are skipped -- a reversal is a correction to a payment, not a
    separate bill.
    """
    bills = [
        tx
        for tx in transactions
        if not is_noise(tx)
        and tx.direction == Direction.OUT
        and tx.category != "upi_reversal"
        and tx.counterparty_type
        in (CounterpartyType.UTILITY, CounterpartyType.RENT)
    ]
    if not bills:
        return None
    on_time = sum(1 for tx in bills if tx.date.day <= BILL_ON_TIME_DAY_OF_MONTH)
    return on_time / len(bills)


# ---------------------------------------------------------------------------
# Family 4: Resilience
# ---------------------------------------------------------------------------


def _cash_buffer_days(
    monthly_income: dict[str, float],
    monthly_expenses: dict[str, float],
    window: MonthWindow,
) -> Optional[float]:
    """Days of running costs the typical monthly surplus could cover.

    The AA payload modelled here carries no account balance, so this is a
    flow-derived liquidity proxy rather than an observed balance: the median
    monthly surplus divided by average daily expense. A negative value means
    the typical month burns cash rather than building a buffer.
    """
    total_expenses = sum(monthly_expenses.values())
    n_days = (window.end - window.start).days + 1
    if total_expenses <= 0 or n_days <= 0:
        return None
    avg_daily_expense = total_expenses / n_days
    surpluses = [
        income - monthly_expenses.get(key, 0.0)
        for key, income in monthly_income.items()
    ]
    if not surpluses:
        return None
    return median(surpluses) / avg_daily_expense


def _worst_monthly_dip_pct(monthly_income: dict[str, float]) -> Optional[float]:
    """How far the worst month fell below the typical month, as a fraction.

    0.0 means the weakest month matched the median and 1.0 means a month with
    no income at all. Values above 1.0 are possible and meaningful: a month can
    net negative when reversals exceed that month's inflows. Measured against
    the median rather than the mean so a single festival spike does not make
    every other month look like a dip.
    """
    values = list(monthly_income.values())
    if not values:
        return None
    typical = median(values)
    if typical <= 0:
        return None
    return max(0.0, (typical - min(values)) / typical)


# ---------------------------------------------------------------------------
# Family 6: Trail
# ---------------------------------------------------------------------------
#
# digital_share / cash_share are INFORMATIONAL ONLY and must never be used to
# penalize cash-heavy businesses. A cash-heavy street vendor is not a worse
# credit risk for being cash-heavy -- penalizing that would rebuild the exact
# exclusion this project exists to undo. These features are here so the
# product can describe the quality of the trail (and explain a LOW_CONFIDENCE
# outcome), not to move a score downward.


def _channel_shares(
    transactions: list[Transaction],
) -> tuple[Optional[float], Optional[float]]:
    digital_value = 0.0
    cash_value = 0.0
    for tx in transactions:
        if is_noise(tx):
            continue
        if tx.channel in DIGITAL_CHANNELS:
            digital_value += tx.amount
        elif tx.channel == Channel.CASH:
            cash_value += tx.amount
    total = digital_value + cash_value
    if total <= 0:
        return None, None
    return digital_value / total, cash_value / total


# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------


def extract_features(profile: Profile) -> FeatureSet:
    """Compute all 12 features from the profile's seen window (months 1-24).

    Reads `profile.transactions_seen` and nothing else. The held-out window is
    not touched, and the leakage guard below proves it.
    """
    window = seen_window(profile)
    transactions = profile.transactions_seen

    # Leakage tripwire: every transaction must sit inside months 1-24.
    assert_within_window(transactions, window, caller="feature_engine.extract_features")

    monthly_income = monthly_business_income(transactions, window)
    monthly_essentials = monthly_essential_expenses(transactions, window)
    monthly_expenses = monthly_total_expenses(transactions, window)
    digital_share, cash_share = _channel_shares(transactions)

    return FeatureSet(
        pct_weeks_with_income=_pct_weeks_with_income(transactions, window),
        income_coefficient_of_variation=_income_coefficient_of_variation(monthly_income),
        longest_dry_streak_days=_longest_dry_streak_days(transactions, window),
        trend_last_6_months=_trend_last_6_months(monthly_income),
        year_over_year_change=_year_over_year_change(monthly_income),
        expense_to_income_ratio=_expense_to_income_ratio(monthly_income, monthly_expenses),
        ontime_bill_payment_rate=_ontime_bill_payment_rate(transactions),
        cash_buffer_days=_cash_buffer_days(monthly_income, monthly_expenses, window),
        worst_monthly_dip_pct=_worst_monthly_dip_pct(monthly_income),
        months_would_cover_emi_of_last_24=_months_would_cover_emi(
            monthly_income, monthly_essentials
        ),
        digital_share=digital_share,
        cash_share=cash_share,
    )
