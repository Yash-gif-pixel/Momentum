"""Builders for small, hand-computable profiles used across the Y2 tests.

Tests assert against profiles whose correct answers can be worked out on
paper, so a failure points at the logic rather than at a statistical drift in
the generated dataset.
"""

from __future__ import annotations

from datetime import date, timedelta

from backend.generator.schema import (
    Archetype,
    Channel,
    CounterpartyType,
    Direction,
    HealthTier,
    Profile,
    ProfileMeta,
    SplitInfo,
    Transaction,
)

SEEN_START = date(2024, 1, 1)
SPLIT_DATE = date(2026, 1, 1)  # 24 months of seen history
HOLDOUT_END = date(2026, 6, 30)  # 6 months of held-out history


def add_months(day: date, months: int) -> date:
    month_index = day.month - 1 + months
    year = day.year + month_index // 12
    month = month_index % 12 + 1
    return date(year, month, min(day.day, 28))


def tx(
    day: date,
    amount: float,
    direction: Direction = Direction.IN,
    counterparty_type: CounterpartyType = CounterpartyType.CUSTOMER,
    category: str = "sales",
    channel: Channel = Channel.UPI,
) -> Transaction:
    return Transaction(
        date=day,
        direction=direction,
        amount=amount,
        channel=channel,
        counterparty_type=counterparty_type,
        category=category,
    )


def income_tx(day: date, amount: float, channel: Channel = Channel.UPI) -> Transaction:
    return tx(day, amount, Direction.IN, CounterpartyType.CUSTOMER, "sales", channel)


def rent_tx(day: date, amount: float) -> Transaction:
    return tx(day, amount, Direction.OUT, CounterpartyType.RENT, "rent", Channel.NEFT)


def utility_tx(day: date, amount: float) -> Transaction:
    return tx(
        day, amount, Direction.OUT, CounterpartyType.UTILITY, "electricity_bill", Channel.NEFT
    )


def supplier_tx(day: date, amount: float) -> Transaction:
    return tx(
        day, amount, Direction.OUT, CounterpartyType.SUPPLIER, "raw_material", Channel.UPI
    )


def noise_tx(day: date, amount: float = 2.0) -> Transaction:
    return tx(
        day, amount, Direction.IN, CounterpartyType.UNKNOWN, "rounding_adjustment", Channel.UPI
    )


def make_profile(
    transactions_seen: list[Transaction],
    transactions_holdout: list[Transaction] | None = None,
    *,
    profile_id: str = "TEST0001",
    start: date = SEEN_START,
    split_date: date | None = SPLIT_DATE,
    end: date = HOLDOUT_END,
    archetype: Archetype = Archetype.KIRANA_STORE,
    tier: HealthTier = HealthTier.STABLE,
) -> Profile:
    """Build a Profile with an explicit 24/6 split (or no split at all)."""
    transactions_holdout = transactions_holdout or []
    if split_date is None:
        seen_months = _months_between(start, end) + 1
        holdout_months = 0
        months_available = seen_months
    else:
        seen_months = _months_between(start, split_date - timedelta(days=1)) + 1
        holdout_months = _months_between(split_date, end) + 1
        months_available = seen_months + holdout_months

    meta = ProfileMeta(
        profile_id=profile_id,
        archetype=archetype,
        latent_health_tier=tier,
        history_start_date=start,
        history_end_date=end,
        months_available=months_available,
        split=SplitInfo(
            seen_months=seen_months,
            holdout_months=holdout_months,
            split_date=split_date,
        ),
    )
    return Profile(
        meta=meta,
        transactions_seen=transactions_seen,
        transactions_holdout=transactions_holdout,
    )


def _months_between(a: date, b: date) -> int:
    return (b.year - a.year) * 12 + (b.month - a.month)


def monthly_profile(
    seen_income_per_month: list[float],
    *,
    essentials_per_month: float = 0.0,
    holdout_income_per_month: list[float] | None = None,
    holdout_essentials_per_month: float = 0.0,
    start: date = SEEN_START,
) -> Profile:
    """A profile with one income transaction (and optional rent) per month.

    Income for month i is placed on the 10th so it never collides with the
    rent payment on the 3rd, which keeps on-time-bill assertions unambiguous.
    """
    seen: list[Transaction] = []
    for i, amount in enumerate(seen_income_per_month):
        month_start = add_months(start, i)
        if amount > 0:
            seen.append(income_tx(month_start.replace(day=10), amount))
        if essentials_per_month > 0:
            seen.append(rent_tx(month_start.replace(day=3), essentials_per_month))

    split_date = add_months(start, len(seen_income_per_month)).replace(day=1)

    holdout: list[Transaction] = []
    if holdout_income_per_month is None:
        return make_profile(seen, [], start=start, split_date=None, end=split_date - timedelta(days=1))

    for i, amount in enumerate(holdout_income_per_month):
        month_start = add_months(split_date, i)
        if amount > 0:
            holdout.append(income_tx(month_start.replace(day=10), amount))
        if holdout_essentials_per_month > 0:
            holdout.append(rent_tx(month_start.replace(day=3), holdout_essentials_per_month))

    end = add_months(split_date, len(holdout_income_per_month)) - timedelta(days=1)
    return make_profile(seen, holdout, start=start, split_date=split_date, end=end)
