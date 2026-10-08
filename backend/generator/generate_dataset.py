#!/usr/bin/env python3
"""Synthetic MSME borrower profile generator.

Produces N synthetic Account-Aggregator-shaped transaction histories, one
JSON file per profile, under /data/generated/ (gitignored — regenerate by
running this script; see /data/README.md).

100% synthetic. No real bank statement, GST, Udyam, or credit-bureau data is
used, referenced, or scraped anywhere in this script.

Usage:
    python3 backend/generator/generate_dataset.py
    python3 backend/generator/generate_dataset.py --n-profiles 500 --seed 7

See /docs/DATA_SCHEMA.md for the full documentation of archetypes, health
tiers, noise model, and the Shadow-P2M heuristic implemented here.
"""

from __future__ import annotations

import argparse
import json
import random
from dataclasses import dataclass, field
from datetime import date, timedelta
from pathlib import Path

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

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT_DIR = REPO_ROOT / "data" / "generated"

# A fixed "as of" date keeps the generated dataset reproducible across runs
# and machines regardless of when the script is actually executed.
HISTORY_END_DATE = date(2026, 8, 31)
SEEN_MONTHS = 24
HOLDOUT_MONTHS = 6
TOTAL_MONTHS = SEEN_MONTHS + HOLDOUT_MONTHS  # 30

SHORT_HISTORY_MONTHS_RANGE = (4, 11)  # strictly < 12 months, per acceptance criteria

TIER_WEIGHTS: dict[HealthTier, float] = {
    HealthTier.THRIVING: 0.30,
    HealthTier.STABLE: 0.35,
    HealthTier.STRUGGLING: 0.22,
    HealthTier.FAILING: 0.13,
}

# Tier parameters. These proportions and multipliers are this dataset's own
# design choice for demo/prototype purposes — not sourced from any external
# statistic. See docs/DATA_SCHEMA.md.
TIER_PARAMS: dict[HealthTier, dict] = {
    HealthTier.THRIVING: dict(
        monthly_growth=0.010,
        volatility=0.10,
        missed_day_prob=0.02,
        shock_prob_per_month=0.02,
        shock_severity=(0.6, 0.8),
        bill_on_time_prob=0.95,
        cash_bias=-0.10,
    ),
    HealthTier.STABLE: dict(
        monthly_growth=0.002,
        volatility=0.16,
        missed_day_prob=0.05,
        shock_prob_per_month=0.04,
        shock_severity=(0.5, 0.75),
        bill_on_time_prob=0.85,
        cash_bias=0.0,
    ),
    HealthTier.STRUGGLING: dict(
        monthly_growth=-0.006,
        volatility=0.26,
        missed_day_prob=0.12,
        shock_prob_per_month=0.08,
        shock_severity=(0.35, 0.65),
        bill_on_time_prob=0.60,
        cash_bias=0.12,
    ),
    HealthTier.FAILING: dict(
        monthly_growth=-0.015,
        volatility=0.36,
        missed_day_prob=0.25,
        shock_prob_per_month=0.15,
        shock_severity=(0.25, 0.55),
        bill_on_time_prob=0.35,
        cash_bias=0.22,
    ),
}

ARCHETYPE_PARAMS: dict[Archetype, dict] = {
    Archetype.STREET_FOOD_VENDOR: dict(
        base_daily=1500.0,
        n_txn_range=(4, 10),
        weekend_bump=1.4,
        monsoon_dip=0.65,
        festival_bump=(1.6, 2.2),
        has_rent=True,
        rent_amount=1800.0,
        has_utility=True,
        utility_amount=600.0,
        supplier_freq="daily",
        supplier_share=0.35,
    ),
    Archetype.KIRANA_STORE: dict(
        base_daily=5500.0,
        n_txn_range=(3, 8),
        weekend_bump=1.1,
        monsoon_dip=0.95,
        festival_bump=(1.3, 1.6),
        has_rent=True,
        rent_amount=9000.0,
        has_utility=True,
        utility_amount=2200.0,
        supplier_freq="monthly_lump",
        supplier_share=0.55,
    ),
    Archetype.TAILOR_SALON: dict(
        base_daily=1200.0,
        n_txn_range=(1, 4),
        weekend_bump=1.6,
        monsoon_dip=0.9,
        festival_bump=(2.0, 3.0),
        has_rent=True,
        rent_amount=7000.0,
        has_utility=True,
        utility_amount=1500.0,
        supplier_freq="occasional",
        supplier_share=0.20,
    ),
    Archetype.GIG_WORKER: dict(
        base_daily=900.0,
        n_txn_range=(0, 3),
        weekend_bump=1.0,
        monsoon_dip=0.85,
        festival_bump=(1.1, 1.3),
        has_rent=False,
        rent_amount=0.0,
        has_utility=True,
        utility_amount=350.0,  # phone/data recharge, categorized as utility
        supplier_freq="none",
        supplier_share=0.0,
    ),
}

ARCHETYPE_INCOME_CATEGORY: dict[Archetype, str] = {
    Archetype.STREET_FOOD_VENDOR: "sales",
    Archetype.KIRANA_STORE: "sales",
    Archetype.TAILOR_SALON: "service_income",
    Archetype.GIG_WORKER: "gig_payout",
}

FESTIVAL_WINDOW = (date(2000, 10, 1), date(2000, 11, 15))  # month/day matched per year
WEDDING_SEASON_MONTHS = {11, 12, 1, 2}
MONSOON_MONTHS = {6, 7, 8, 9}


def add_months(d: date, months: int) -> date:
    month_index = d.month - 1 + months
    year = d.year + month_index // 12
    month = month_index % 12 + 1
    day = min(d.day, [31, 29 if year % 4 == 0 and (year % 100 != 0 or year % 400 == 0) else 28,
                       31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1])
    return date(year, month, day)


def is_in_festival_window(d: date) -> bool:
    return d.month == 10 or (d.month == 11 and d.day <= 15)


def month_key(d: date) -> str:
    return f"{d.year:04d}-{d.month:02d}"


def weighted_choice(rng: random.Random, items: list, weights: list[float]):
    return rng.choices(items, weights=weights, k=1)[0]


@dataclass
class RawTx:
    d: date
    direction: Direction
    amount: float
    channel: Channel
    counterparty_type: CounterpartyType
    category: str
    note: str | None = None
    likely_shadow_supplier: bool | None = None


def pick_channel(
    rng: random.Random,
    cash_heavy: bool,
    cash_bias: float,
    counterparty_type: CounterpartyType,
) -> Channel:
    weights = {
        Channel.UPI: 0.55,
        Channel.CASH: 0.25,
        Channel.NEFT: 0.10,
        Channel.CARD: 0.05,
        Channel.CHEQUE: 0.05,
    }
    if counterparty_type in (CounterpartyType.RENT, CounterpartyType.UTILITY):
        weights[Channel.NEFT] += 0.15
        weights[Channel.CHEQUE] += 0.10
        weights[Channel.CARD] = max(weights[Channel.CARD] - 0.05, 0.0)
    if counterparty_type == CounterpartyType.SUPPLIER:
        weights[Channel.CASH] += 0.10
        weights[Channel.NEFT] += 0.05

    weights[Channel.CASH] = max(0.02, weights[Channel.CASH] + cash_bias)
    weights[Channel.UPI] = max(0.02, weights[Channel.UPI] - cash_bias * 0.6)

    if cash_heavy:
        weights = {c: w * 0.3 for c, w in weights.items()}
        weights[Channel.CASH] += 0.65

    channels = list(weights.keys())
    w = [max(0.01, weights[c]) for c in channels]
    return weighted_choice(rng, channels, w)


def note_for(rng: random.Random, channel: Channel, category: str) -> str | None:
    if channel == Channel.UPI:
        return f"UPI/{rng.randint(100000, 999999)}/{category}"
    if channel == Channel.NEFT:
        return f"NEFT-REF{rng.randint(1000, 9999)}"
    if channel == Channel.CHEQUE:
        return f"CHQ#{rng.randint(1000, 9999)}"
    if channel == Channel.CARD:
        return f"CARD-POS-{rng.randint(1000, 9999)}"
    return None  # cash: typically no digital reference


def split_amount(rng: random.Random, total: float, n: int) -> list[float]:
    if n <= 0 or total <= 0:
        return []
    weights = [rng.random() + 0.2 for _ in range(n)]
    s = sum(weights)
    amounts = [round(total * w / s, 2) for w in weights]
    return [a for a in amounts if a > 0]


def generate_income_days(
    rng: random.Random,
    archetype: Archetype,
    tier: HealthTier,
    start: date,
    end: date,
    cash_heavy: bool,
    tier_params: dict | None = None,
) -> list[RawTx]:
    a = ARCHETYPE_PARAMS[archetype]
    t = tier_params if tier_params is not None else TIER_PARAMS[tier]
    txs: list[RawTx] = []

    month_shock: dict[str, float] = {}
    cur = date(start.year, start.month, 1)
    while cur <= end:
        if rng.random() < t["shock_prob_per_month"]:
            month_shock[month_key(cur)] = rng.uniform(*t["shock_severity"])
        cur = add_months(cur, 1)

    day = start
    day_index = 0
    total_days = (end - start).days + 1
    while day <= end:
        month_idx = (day.year - start.year) * 12 + (day.month - start.month)
        growth = (1 + t["monthly_growth"]) ** month_idx

        seasonal = 1.0
        if day.month in MONSOON_MONTHS:
            seasonal *= a["monsoon_dip"]
        if is_in_festival_window(day):
            seasonal *= rng.uniform(*a["festival_bump"])
        if archetype == Archetype.TAILOR_SALON and day.month in WEDDING_SEASON_MONTHS:
            seasonal *= 1.3
        if day.weekday() >= 5:  # Sat/Sun
            seasonal *= a["weekend_bump"]

        shock = month_shock.get(month_key(day), 1.0)
        volatility_mult = max(0.05, rng.gauss(1.0, t["volatility"]))

        missed = rng.random() < t["missed_day_prob"]
        if archetype == Archetype.GIG_WORKER:
            # irregular by design: independent of tier, extra chance of a zero day
            missed = missed or rng.random() < 0.15

        if not missed:
            daily_total = a["base_daily"] * growth * seasonal * shock * volatility_mult
            n_txn = rng.randint(*a["n_txn_range"])
            if archetype == Archetype.GIG_WORKER and n_txn == 0:
                pass
            else:
                n_txn = max(1, n_txn)
                category = ARCHETYPE_INCOME_CATEGORY[archetype]
                for amt in split_amount(rng, daily_total, n_txn):
                    channel = pick_channel(
                        rng, cash_heavy, t["cash_bias"], CounterpartyType.CUSTOMER
                    )
                    txs.append(
                        RawTx(
                            d=day,
                            direction=Direction.IN,
                            amount=amt,
                            channel=channel,
                            counterparty_type=CounterpartyType.CUSTOMER,
                            category=category,
                            note=note_for(rng, channel, category),
                        )
                    )

        if shock < 1.0 and rng.random() < 0.5 and day.day == 15:
            # one-time shock-related outflow for the affected month
            amt = round(a["base_daily"] * rng.uniform(3, 8), 2)
            channel = pick_channel(rng, cash_heavy, t["cash_bias"], CounterpartyType.UNKNOWN)
            category = rng.choice(["equipment_repair", "medical_expense"])
            txs.append(
                RawTx(
                    d=day,
                    direction=Direction.OUT,
                    amount=amt,
                    channel=channel,
                    counterparty_type=CounterpartyType.UNKNOWN,
                    category=category,
                    note=note_for(rng, channel, category),
                )
            )

        day += timedelta(days=1)
        day_index += 1

    return txs


def generate_expense_days(
    rng: random.Random,
    archetype: Archetype,
    tier: HealthTier,
    start: date,
    end: date,
    cash_heavy: bool,
    tier_params: dict | None = None,
) -> list[RawTx]:
    a = ARCHETYPE_PARAMS[archetype]
    t = tier_params if tier_params is not None else TIER_PARAMS[tier]
    txs: list[RawTx] = []

    # Rent + utility, once a month, with tier-driven on-time/late discipline.
    cur = date(start.year, start.month, 1)
    while cur <= end:
        month_idx = (cur.year - start.year) * 12 + (cur.month - start.month)
        growth = (1 + t["monthly_growth"] * 0.5) ** max(month_idx, 0)
        on_time = rng.random() < t["bill_on_time_prob"]
        due_day = 5
        pay_day = rng.randint(due_day, due_day + 2) if on_time else rng.randint(due_day + 6, due_day + 20)
        pay_day = min(pay_day, 28)

        for enabled, amount, ctype, category in (
            (a["has_rent"], a["rent_amount"], CounterpartyType.RENT, "rent"),
            (a["has_utility"], a["utility_amount"], CounterpartyType.UTILITY, "electricity_bill"
             if archetype != Archetype.GIG_WORKER else "phone_data_recharge"),
        ):
            if not enabled:
                continue
            try:
                pd = date(cur.year, cur.month, pay_day)
            except ValueError:
                pd = date(cur.year, cur.month, 28)
            if pd < start or pd > end:
                continue
            amt = round(amount * growth * rng.uniform(0.95, 1.05), 2)
            channel = pick_channel(rng, cash_heavy, t["cash_bias"], ctype)
            txs.append(
                RawTx(
                    d=pd,
                    direction=Direction.OUT,
                    amount=amt,
                    channel=channel,
                    counterparty_type=ctype,
                    category=category,
                    note=note_for(rng, channel, category)
                    or ("LATE PAYMENT" if not on_time else None),
                )
            )
        cur = add_months(cur, 1)

    # Supplier payments: daily-small, monthly-lump, occasional, or none.
    if a["supplier_freq"] == "daily":
        day = start
        while day <= end:
            if rng.random() < 0.85:
                month_idx = (day.year - start.year) * 12 + (day.month - start.month)
                growth = (1 + t["monthly_growth"]) ** month_idx
                amt = round(a["base_daily"] * a["supplier_share"] * growth * rng.uniform(0.7, 1.3), 2)
                channel = pick_channel(rng, cash_heavy, t["cash_bias"], CounterpartyType.SUPPLIER)
                txs.append(
                    RawTx(
                        d=day,
                        direction=Direction.OUT,
                        amount=amt,
                        channel=channel,
                        counterparty_type=CounterpartyType.SUPPLIER,
                        category="raw_material",
                        note=note_for(rng, channel, "raw_material"),
                    )
                )
            day += timedelta(days=1)
    elif a["supplier_freq"] == "monthly_lump":
        cur = date(start.year, start.month, 1)
        while cur <= end:
            month_idx = (cur.year - start.year) * 12 + (cur.month - start.month)
            growth = (1 + t["monthly_growth"]) ** month_idx
            pay_day = rng.randint(1, 6)
            try:
                pd = date(cur.year, cur.month, pay_day)
            except ValueError:
                pd = date(cur.year, cur.month, 1)
            if start <= pd <= end:
                monthly_revenue_est = a["base_daily"] * 30 * growth
                amt = round(monthly_revenue_est * a["supplier_share"] * rng.uniform(0.85, 1.15), 2)
                channel = pick_channel(rng, cash_heavy, t["cash_bias"], CounterpartyType.SUPPLIER)
                txs.append(
                    RawTx(
                        d=pd,
                        direction=Direction.OUT,
                        amount=amt,
                        channel=channel,
                        counterparty_type=CounterpartyType.SUPPLIER,
                        category="stock_purchase",
                        note=note_for(rng, channel, "stock_purchase"),
                    )
                )
            cur = add_months(cur, 1)
    elif a["supplier_freq"] == "occasional":
        day = start
        while day <= end:
            if rng.random() < 0.04:
                month_idx = (day.year - start.year) * 12 + (day.month - start.month)
                growth = (1 + t["monthly_growth"]) ** month_idx
                amt = round(a["base_daily"] * 6 * a["supplier_share"] * growth * rng.uniform(0.8, 1.2), 2)
                channel = pick_channel(rng, cash_heavy, t["cash_bias"], CounterpartyType.SUPPLIER)
                txs.append(
                    RawTx(
                        d=day,
                        direction=Direction.OUT,
                        amount=amt,
                        channel=channel,
                        counterparty_type=CounterpartyType.SUPPLIER,
                        category="raw_material",
                        note=note_for(rng, channel, "raw_material"),
                    )
                )
            day += timedelta(days=1)

    # Personal transfers: some genuinely personal, some (a subset, recurring)
    # actually informal-supplier-like. See Shadow-P2M tagging in postprocess.
    day = start
    while day <= end:
        if rng.random() < 0.05:
            direction = weighted_choice(rng, [Direction.OUT, Direction.IN], [0.7, 0.3])
            amt = round(rng.uniform(200, 3000), 2)
            channel = Channel.UPI if rng.random() < 0.85 else Channel.CASH
            txs.append(
                RawTx(
                    d=day,
                    direction=direction,
                    amount=amt,
                    channel=channel,
                    counterparty_type=CounterpartyType.PERSONAL,
                    category="personal_transfer",
                    note=note_for(rng, channel, "personal_transfer"),
                )
            )
        day += timedelta(days=1)

    # A recurring "shadow supplier" pattern: a fixed personal VPA paid on a
    # regular weekday, in a stable amount band, across many months.
    if rng.random() < 0.35:
        shadow_weekday = rng.randint(0, 6)
        shadow_amount = round(rng.uniform(500, 4000), 2)
        cur = start + timedelta(days=(shadow_weekday - start.weekday()) % 7)
        while cur <= end:
            if rng.random() < 0.8:
                amt = round(shadow_amount * rng.uniform(0.9, 1.1), 2)
                channel = Channel.UPI
                txs.append(
                    RawTx(
                        d=cur,
                        direction=Direction.OUT,
                        amount=amt,
                        channel=channel,
                        counterparty_type=CounterpartyType.PERSONAL,
                        category="personal_transfer",
                        note=note_for(rng, channel, "personal_transfer"),
                    )
                )
            cur += timedelta(days=7)

    return txs


def _in_gap(day: date, gap_windows: list[tuple[date, date]]) -> bool:
    return any(gs <= day <= ge for gs, ge in gap_windows)


def _reversal_day_for(
    original: date,
    candidate: date,
    end: date,
    gap_windows: list[tuple[date, date]],
    split_date: date | None,
) -> date:
    """Place a reversal so it stays paired with the transaction it reverses.

    A reversal must never end up separated from its original, because each one
    alone is a phantom: an orphaned reversal reads as an unexplained negative
    entry, and an original whose reversal was dropped reads as income that was
    never actually received.

    So a next-day reversal falls back to same-day (always valid, and an instant
    UPI failure reversal is realistic) whenever the later date would:
      * run past the end of the history,
      * land inside a data gap, where its original cannot be, or
      * cross the seen/held-out split, which would strand a correction to
        seen-window activity on the held-out side of the boundary.
    """
    if candidate > end:
        return original
    if split_date is not None and original < split_date <= candidate:
        return original
    if _in_gap(candidate, gap_windows):
        return original
    return candidate


def inject_noise(
    rng: random.Random,
    txs: list[RawTx],
    start: date,
    end: date,
    gap_windows: list[tuple[date, date]] | None = None,
    split_date: date | None = None,
) -> list[RawTx]:
    gap_windows = gap_windows or []
    out = list(txs)

    # Failed/reversed UPI transactions.
    upi_txs = [t for t in txs if t.channel == Channel.UPI]
    for t in rng.sample(upi_txs, k=min(len(upi_txs), max(1, len(upi_txs) // 150))):
        reversal_day = _reversal_day_for(
            t.d, t.d + timedelta(days=rng.choice([0, 1])), end, gap_windows, split_date
        )
        rev_direction = Direction.OUT if t.direction == Direction.IN else Direction.IN
        out.append(
            RawTx(
                d=reversal_day,
                direction=rev_direction,
                amount=t.amount,
                channel=Channel.UPI,
                counterparty_type=t.counterparty_type,
                category="upi_reversal",
                note="REVERSED",
            )
        )

    # Midnight batch-settlement sweeps: small aggregator adjustment entries.
    day = start
    while day <= end:
        if rng.random() < 0.03 and not _in_gap(day, gap_windows):
            direction = weighted_choice(rng, [Direction.IN, Direction.OUT], [0.5, 0.5])
            out.append(
                RawTx(
                    d=day,
                    direction=direction,
                    amount=round(rng.uniform(5, 60), 2),
                    channel=Channel.UPI,
                    counterparty_type=CounterpartyType.UNKNOWN,
                    category="batch_settlement",
                    note="UPI SETTLEMENT BATCH",
                )
            )
        day += timedelta(days=1)

    # Rounding artifacts.
    day = start
    while day <= end:
        if rng.random() < 0.01 and not _in_gap(day, gap_windows):
            out.append(
                RawTx(
                    d=day,
                    direction=Direction.IN,
                    amount=round(rng.uniform(0.5, 5.0), 2),
                    channel=Channel.UPI,
                    counterparty_type=CounterpartyType.UNKNOWN,
                    category="rounding_adjustment",
                    note="rounding",
                )
            )
        day += timedelta(days=1)

    return out


def compute_gap_windows(
    rng: random.Random, start: date, end: date, n_gaps: int
) -> list[tuple[date, date]]:
    """Pick the date ranges where the AA data pull is simulated to have failed."""
    total_days = (end - start).days + 1
    if total_days < 20 or n_gaps <= 0:
        return []
    windows = []
    for _ in range(n_gaps):
        gap_len = rng.randint(2, 7)
        gap_start_offset = rng.randint(0, max(1, total_days - gap_len - 1))
        gap_start = start + timedelta(days=gap_start_offset)
        windows.append((gap_start, gap_start + timedelta(days=gap_len)))
    return windows


def apply_gaps(txs: list[RawTx], gap_windows: list[tuple[date, date]]) -> list[RawTx]:
    if not gap_windows:
        return txs
    return [t for t in txs if not _in_gap(t.d, gap_windows)]


def tag_shadow_p2m(txs: list[RawTx]) -> None:
    """Heuristic: a personal-counterparty transaction is flagged
    likely_shadow_supplier=True if it recurs on the same weekday, in the same
    ~amount band, across 3+ distinct calendar months.

    (The AA-style schema here has no time-of-day field, so weekday +
    amount-band recurrence is used as the observable proxy. See
    docs/DATA_SCHEMA.md.)
    """
    personal = [t for t in txs if t.counterparty_type == CounterpartyType.PERSONAL]
    groups: dict[tuple[int, int], set[str]] = {}
    for t in personal:
        band = round(t.amount / 100) * 100
        key = (t.d.weekday(), band)
        groups.setdefault(key, set()).add(month_key(t.d))

    for t in personal:
        band = round(t.amount / 100) * 100
        key = (t.d.weekday(), band)
        t.likely_shadow_supplier = len(groups.get(key, ())) >= 3


def build_profile(
    rng: random.Random,
    profile_index: int,
    archetype: Archetype,
    tier: HealthTier,
    cash_heavy: bool,
    short_history: bool,
    tier_params: dict | None = None,
) -> Profile:
    profile_id = f"MSME{profile_index:04d}"

    if short_history:
        months = rng.randint(*SHORT_HISTORY_MONTHS_RANGE)
        end = HISTORY_END_DATE
        start = add_months(end, -months) + timedelta(days=1)
        seen_months, holdout_months, split_date = months, 0, None
    else:
        months = TOTAL_MONTHS
        end = HISTORY_END_DATE
        start = add_months(end, -months) + timedelta(days=1)
        split_date = add_months(start, SEEN_MONTHS)
        seen_months, holdout_months = SEEN_MONTHS, HOLDOUT_MONTHS

    income = generate_income_days(rng, archetype, tier, start, end, cash_heavy, tier_params)
    expenses = generate_expense_days(rng, archetype, tier, start, end, cash_heavy, tier_params)
    raw = income + expenses

    n_gaps = 0 if short_history else rng.choice([0, 0, 1, 1, 2])
    # Gap windows are decided first and then honoured by both steps: the base
    # transactions inside them are dropped, and noise injection skips those
    # days entirely. Emptying the gaps only after injecting noise would let
    # settlement sweeps and rounding artifacts resurrect a day the AA pull is
    # meant to have missed, and could separate a reversal from its original.
    gap_windows = compute_gap_windows(rng, start, end, n_gaps)
    raw = apply_gaps(raw, gap_windows)
    raw = inject_noise(rng, raw, start, end, gap_windows, split_date)
    tag_shadow_p2m(raw)
    raw.sort(key=lambda t: t.d)

    def to_model(t: RawTx) -> Transaction:
        return Transaction(
            date=t.d,
            direction=t.direction,
            amount=round(max(t.amount, 0.01), 2),
            channel=t.channel,
            counterparty_type=t.counterparty_type,
            category=t.category,
            note=t.note,
            likely_shadow_supplier=t.likely_shadow_supplier
            if t.counterparty_type == CounterpartyType.PERSONAL
            else None,
        )

    if split_date is not None:
        seen = [to_model(t) for t in raw if t.d < split_date]
        holdout = [to_model(t) for t in raw if t.d >= split_date]
    else:
        seen = [to_model(t) for t in raw]
        holdout = []

    meta = ProfileMeta(
        profile_id=profile_id,
        archetype=archetype,
        latent_health_tier=tier,
        is_cash_heavy_edge_case=cash_heavy,
        is_short_history_edge_case=short_history,
        history_start_date=start,
        history_end_date=end,
        months_available=months,
        split=SplitInfo(seen_months=seen_months, holdout_months=holdout_months, split_date=split_date),
    )
    return Profile(meta=meta, transactions_seen=seen, transactions_holdout=holdout)


def build_demo_profile_lakshmi() -> Profile:
    """Hand-tuned demo profile: street_food_vendor, thriving, clean growth
    curve with a clear festival spike and minimal noise. Used live in the
    pitch, so it is tuned to look good plotted, not just to statistically
    pass the generator's own checks.
    """
    rng = random.Random(42)
    tier = HealthTier.THRIVING
    archetype = Archetype.STREET_FOOD_VENDOR

    # Override tier params for a visibly clean demo curve, passed explicitly
    # rather than mutating the shared TIER_PARAMS global.
    demo_tier_params = dict(
        TIER_PARAMS[tier],
        monthly_growth=0.014,
        volatility=0.06,
        missed_day_prob=0.01,
        shock_prob_per_month=0.0,
        bill_on_time_prob=0.98,
        cash_bias=-0.12,
    )
    profile = build_profile(
        rng,
        profile_index=0,
        archetype=archetype,
        tier=tier,
        cash_heavy=False,
        short_history=False,
        tier_params=demo_tier_params,
    )

    profile.meta.profile_id = "demo_lakshmi"
    return profile


def build_demo_profile_thin_file() -> Profile:
    """Hand-tuned demo profile: a short-history (4-11 month) profile with a
    fixed seed, dedicated to the frontend's thin_file_002 demo id.

    Deliberately NOT the same file as data/sample_profile.json. That file is
    picked as "whichever short-history, non-cash-heavy profile happens to
    come first" in main()'s bulk-generation loop -- deterministic under a
    fixed --seed, but its exact identity is an accident of loop order, not a
    pinned choice, and would silently change if the bulk generation logic or
    edge-case counts ever changed. A demo id a frontend hardcodes and a demo
    tests against needs a stable identity independent of that, the same way
    build_demo_profile_lakshmi/ramesh_carpentry/dormancy_gap all use their
    own fixed rng seed rather than being sampled from the bulk population.
    """
    rng = random.Random(121)  # lands on 5 months of history -> NOT_ASSESSABLE
    tier = HealthTier.STABLE
    archetype = Archetype.KIRANA_STORE

    profile = build_profile(
        rng,
        profile_index=0,
        archetype=archetype,
        tier=tier,
        cash_heavy=False,
        short_history=True,
    )
    profile.meta.profile_id = "demo_thin_file"
    return profile


def build_demo_profile_ramesh_carpentry() -> Profile:
    """Hand-tuned demo profile: a stable, ordinary 30-month history.

    NOTE ON ARCHETYPE SUBSTITUTION: the generator has no dedicated
    "carpentry" archetype -- only street_food_vendor, kirana_store,
    tailor_salon, gig_worker exist (see Archetype). tailor_salon is used
    here as the closest available fit: a materials-plus-service small trade
    with a weekly rhythm, which is a reasonable stand-in for a carpentry
    business's cashflow shape. This substitution is deliberate and
    documented here (and in docs/DATA_SCHEMA.md), not a silent guess --
    adding a real carpentry archetype would need its own generator
    parameters and is out of scope for a single demo profile.
    """
    rng = random.Random(104)
    tier = HealthTier.STABLE
    archetype = Archetype.TAILOR_SALON

    profile = build_profile(
        rng,
        profile_index=0,
        archetype=archetype,
        tier=tier,
        cash_heavy=False,
        short_history=False,
    )
    profile.meta.profile_id = "demo_ramesh_carpentry"
    return profile


def build_demo_profile_meera_tailor() -> Profile:
    """Hand-tuned demo profile: a thriving tailor_salon with a clean,
    ordinary 30-month history.

    Exists for the one demo case where a traditional bureau record also
    exists (see the frontend's simulated bureau lookup): a borrower whose
    bureau file is thin and years out of date, but whose present-day
    cashflow is healthy. Nothing about that bureau record lives here --
    this is an ordinary generated profile, scored by the same model and the
    same gate as every other. The bureau side is entirely a frontend
    simulation, deliberately kept out of the scoring path so it cannot
    influence a Credify score.
    """
    rng = random.Random(105)
    tier = HealthTier.THRIVING
    archetype = Archetype.TAILOR_SALON

    profile = build_profile(
        rng,
        profile_index=0,
        archetype=archetype,
        tier=tier,
        cash_heavy=False,
        short_history=False,
    )
    profile.meta.profile_id = "demo_meera_tailor"
    return profile


def build_demo_profile_arjun_kirana() -> Profile:
    """Hand-tuned demo profile: a kirana_store whose turnover decays steadily
    across the whole seen window.

    The mirror image of build_demo_profile_meera_tailor. Meera is the
    credit-invisible borrower a bureau would decline; this profile is the
    borrower a bureau would happily approve -- the frontend pairs it with a
    healthy simulated bureau file -- while the cashflow shows the business
    shrinking month after month. It exists to make the point that a bureau
    score is a record of past BORROWING, reported with a lag, and says
    nothing about whether the business can service a loan today.

    The base tier is STABLE rather than STRUGGLING on purpose. A STRUGGLING
    business is volatile, misses trading days and pays bills late, and the
    model marks it down for all of those before the trend is even considered
    -- which muddles the point, because a bureau would likely have noticed a
    borrower in that state. What makes this profile interesting is that every
    OTHER signal looks fine: income arrives in 98% of weeks, monthly income
    varies by only ~19%, bills are mostly paid on time. The one thing wrong is
    that turnover is shrinking, which is precisely the thing a bureau file
    cannot show.

    The -2.0%/month override supplies that decline (STABLE's own +0.2% would
    not); across the 24-month seen window it takes monthly inflow from roughly
    Rs 1.62L to Rs 0.77L. As with every demo builder these params are passed
    explicitly instead of mutating the TIER_PARAMS global.

    SEED CHOICE IS NOT ARBITRARY: 111 was picked by sweeping seeds and keeping
    one that scores in the low-to-mid 20s, i.e. clearly below the book but
    still `manual_review` rather than `high_risk_referral`. Steeper declines
    and lower seeds score near zero, which makes the demo contrast louder but
    reads as a strawman. The score itself is not set here and is not tunable
    from here -- it is whatever the scorecard returns for this cashflow. What
    is chosen is the profile, the same way every other build_demo_profile_*
    pins a fixed seed to keep a demo fixture's identity stable.
    """
    rng = random.Random(111)
    tier = HealthTier.STABLE
    archetype = Archetype.KIRANA_STORE

    demo_tier_params = dict(
        TIER_PARAMS[tier],
        monthly_growth=-0.020,
        volatility=0.16,
        missed_day_prob=0.05,
    )
    profile = build_profile(
        rng,
        profile_index=0,
        archetype=archetype,
        tier=tier,
        cash_heavy=False,
        short_history=False,
        tier_params=demo_tier_params,
    )

    profile.meta.profile_id = "demo_arjun_kirana"
    return profile


def build_demo_profile_uniform_trail() -> Profile:
    """A FABRICATED trail: what a templated or machine-generated bank
    statement looks like, not a real business.

    Every other demo profile here represents a genuine MSME. This one does
    not, and nothing in the product should present it as one. It exists so
    the data-pattern check (backend/model/authenticity.py) can be shown
    firing -- no real profile in this dataset trips it, by design, since the
    floor was calibrated to sit below all of them.

    WHY IT IS BUILT BY HAND INSTEAD OF THROUGH build_profile
    --------------------------------------------------------
    build_profile cannot produce this shape at any parameter setting. Its
    `volatility` knob is DAILY multiplicative noise, while monthly income CV
    is dominated by seasonality -- the monsoon dip, festival bumps and
    wedding season are applied per-day inside generate_income_days and
    survive any amount of daily smoothing. demo_lakshmi proves it: the
    tightest volatility in the generator (0.06) still lands at CV 0.409.

    That is precisely the tell this profile embodies. A real Indian MSME's
    monthly income cannot be flat, because the calendar will not let it. A
    forged statement generated from a monthly template has no reason to know
    that, so it comes out unnaturally even -- which is what the check reads.

    Deliberately kept plausible in every OTHER respect: it clears the
    sufficiency gate, pays its bills on time, carries a healthy margin and
    scores well. A fabrication that also looked weak would prove nothing --
    the point of the demo is that a forged trail can satisfy the model and
    still be caught by the one signal that is not about creditworthiness.

    The +/-1.5% jitter is intentional. A perfectly identical monthly total
    (CV exactly 0.0) would be a strawman; a little noise is what a competent
    forgery looks like, and it still lands an order of magnitude under the
    0.08 floor.
    """
    rng = random.Random(777)

    end = HISTORY_END_DATE
    start = add_months(end, -TOTAL_MONTHS) + timedelta(days=1)
    split_date = add_months(start, SEEN_MONTHS)

    # One month's template, repeated. Amounts are in the same range as the
    # kirana_store archetype so it does not stand out on the cashflow chart.
    income_per_month = 150_000.0
    income_txns_per_month = 20
    rent, utility = 9_000.0, 2_200.0
    supplier_payment, supplier_payments_per_month = 18_000.0, 4

    def jitter() -> float:
        return rng.uniform(0.985, 1.015)

    # A whisper of growth (+0.3%/month). Without it, year-over-year change is
    # pure jitter noise around zero and the reason-code template renders the
    # faintly absurd "Income is down 0% ... shrinking". A forged statement
    # would plausibly template in mild growth anyway, and 7% of drift across
    # 24 months is nowhere near enough to lift the CV off the floor.
    monthly_growth = 0.003

    txns: list[Transaction] = []
    month_index = 0
    cur = date(start.year, start.month, 1)
    while cur <= end:
        month_total = income_per_month * ((1 + monthly_growth) ** month_index) * jitter()
        month_index += 1
        per_txn = month_total / income_txns_per_month
        for i in range(income_txns_per_month):
            # Spread across the whole month rather than the first 20 days, so
            # every week carries income. Bunching it early left a dead week
            # each month, which read as a patchy rhythm -- a real weakness,
            # and not the one this profile is meant to demonstrate.
            day = min(1 + (i * 28) // income_txns_per_month, 28)
            d = date(cur.year, cur.month, day)
            if not (start <= d <= end):
                continue
            txns.append(
                Transaction(
                    date=d,
                    direction=Direction.IN,
                    amount=round(per_txn, 2),
                    channel=Channel.UPI,
                    counterparty_type=CounterpartyType.CUSTOMER,
                    category="sales",
                )
            )

        for amount, ctype, category in (
            (rent, CounterpartyType.RENT, "rent"),
            (utility, CounterpartyType.UTILITY, "electricity_bill"),
        ):
            d = date(cur.year, cur.month, 5)
            if start <= d <= end:
                txns.append(
                    Transaction(
                        date=d,
                        direction=Direction.OUT,
                        amount=round(amount * jitter(), 2),
                        channel=Channel.NEFT,
                        counterparty_type=ctype,
                        category=category,
                    )
                )

        for i in range(supplier_payments_per_month):
            d = date(cur.year, cur.month, min(7 + i * 7, 28))
            if start <= d <= end:
                txns.append(
                    Transaction(
                        date=d,
                        direction=Direction.OUT,
                        amount=round(supplier_payment * jitter(), 2),
                        channel=Channel.NEFT,
                        counterparty_type=CounterpartyType.SUPPLIER,
                        category="raw_material",
                    )
                )

        cur = add_months(cur, 1)

    txns.sort(key=lambda t: t.date)

    meta = ProfileMeta(
        profile_id="demo_uniform_trail",
        archetype=Archetype.KIRANA_STORE,
        latent_health_tier=HealthTier.STABLE,
        is_cash_heavy_edge_case=False,
        is_short_history_edge_case=False,
        history_start_date=start,
        history_end_date=end,
        months_available=TOTAL_MONTHS,
        split=SplitInfo(
            seen_months=SEEN_MONTHS, holdout_months=HOLDOUT_MONTHS, split_date=split_date
        ),
    )
    return Profile(
        meta=meta,
        transactions_seen=[t for t in txns if t.date < split_date],
        transactions_holdout=[t for t in txns if t.date >= split_date],
    )


def build_demo_profile_dormancy_gap() -> Profile:
    """Hand-tuned demo profile: kirana_store, failing, with one long
    (60-day) dormancy gap carved into the middle of the seen window.

    The generator's own noise model (apply_gaps) only produces short 2-7 day
    gaps -- realistic for an occasional missed AA data pull, but too brief to
    read as "this business went dormant" in a live demo. This profile
    instead has a deliberate, much longer gap removed directly, specifically
    to demonstrate longest_dry_streak_days / regularity concerns clearly.
    """
    rng = random.Random(203)
    tier = HealthTier.FAILING
    archetype = Archetype.KIRANA_STORE

    profile = build_profile(
        rng,
        profile_index=0,
        archetype=archetype,
        tier=tier,
        cash_heavy=False,
        short_history=False,
    )

    gap_start = add_months(profile.meta.history_start_date, 10)
    gap_end = gap_start + timedelta(days=60)
    profile.transactions_seen = [
        t for t in profile.transactions_seen if not (gap_start <= t.date <= gap_end)
    ]

    profile.meta.profile_id = "demo_dormancy_gap"
    return profile


def monthly_totals(profile: Profile) -> dict[str, dict[str, float]]:
    totals: dict[str, dict[str, float]] = {}
    for t in profile.transactions_seen + profile.transactions_holdout:
        mk = f"{t.date.year:04d}-{t.date.month:02d}"
        bucket = totals.setdefault(mk, {"inflow": 0.0, "outflow": 0.0})
        if t.direction == Direction.IN:
            bucket["inflow"] += t.amount
        else:
            bucket["outflow"] += t.amount
    return dict(sorted(totals.items()))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--n-profiles", type=int, default=520)
    parser.add_argument("--n-short-history", type=int, default=15)
    parser.add_argument("--n-cash-heavy", type=int, default=15)
    parser.add_argument("--seed", type=int, default=2026)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    args = parser.parse_args()

    args.out_dir.mkdir(parents=True, exist_ok=True)
    master_rng = random.Random(args.seed)

    short_history_indices = set(master_rng.sample(range(1, args.n_profiles + 1), args.n_short_history))
    remaining = [i for i in range(1, args.n_profiles + 1) if i not in short_history_indices]
    cash_heavy_indices = set(master_rng.sample(remaining, args.n_cash_heavy))

    archetypes = list(Archetype)
    tiers = list(TIER_WEIGHTS.keys())
    tier_weights = [TIER_WEIGHTS[t] for t in tiers]

    tier_counts = {t: 0 for t in tiers}
    archetype_counts = {a: 0 for a in archetypes}

    sample_profile_json: str | None = None

    for i in range(1, args.n_profiles + 1):
        profile_rng = random.Random(master_rng.randint(0, 2**31 - 1))
        archetype = archetypes[(i - 1) % len(archetypes)]
        tier = weighted_choice(profile_rng, tiers, tier_weights)
        cash_heavy = i in cash_heavy_indices
        short_history = i in short_history_indices

        profile = build_profile(profile_rng, i, archetype, tier, cash_heavy, short_history)
        tier_counts[tier] += 1
        archetype_counts[archetype] += 1

        profile_json = profile.model_dump_json(indent=2, exclude_none=False)
        out_path = args.out_dir / f"{profile.meta.profile_id}.json"
        out_path.write_text(profile_json)

        if sample_profile_json is None and short_history and not cash_heavy:
            sample_profile_json = profile_json

    demo = build_demo_profile_lakshmi()
    demo_json = demo.model_dump_json(indent=2, exclude_none=False)
    thin_file_json = build_demo_profile_thin_file().model_dump_json(indent=2, exclude_none=False)
    ramesh_json = build_demo_profile_ramesh_carpentry().model_dump_json(indent=2, exclude_none=False)
    dormancy_json = build_demo_profile_dormancy_gap().model_dump_json(indent=2, exclude_none=False)
    meera_json = build_demo_profile_meera_tailor().model_dump_json(indent=2, exclude_none=False)
    arjun_json = build_demo_profile_arjun_kirana().model_dump_json(indent=2, exclude_none=False)
    uniform_json = build_demo_profile_uniform_trail().model_dump_json(indent=2, exclude_none=False)

    # Demo profiles go only to data/, never out_dir: out_dir is the training
    # population build_feature_table globs, and these are hand-tuned fixtures.
    # (demo_lakshmi still reaches training via COMMITTED_SAMPLES.)
    committed_dir = REPO_ROOT / "data"
    (committed_dir / "demo_profile_lakshmi.json").write_text(demo_json)
    (committed_dir / "demo_profile_thin_file.json").write_text(thin_file_json)
    (committed_dir / "demo_profile_ramesh_carpentry.json").write_text(ramesh_json)
    (committed_dir / "demo_profile_dormancy_gap.json").write_text(dormancy_json)
    (committed_dir / "demo_profile_meera_tailor.json").write_text(meera_json)
    (committed_dir / "demo_profile_arjun_kirana.json").write_text(arjun_json)
    (committed_dir / "demo_profile_uniform_trail.json").write_text(uniform_json)
    if sample_profile_json is not None:
        (committed_dir / "sample_profile.json").write_text(sample_profile_json)

    print(f"Generated {args.n_profiles} profiles -> {args.out_dir}")
    print(f"Tier distribution: { {t.value: c for t, c in tier_counts.items()} }")
    print(f"Archetype distribution: { {a.value: c for a, c in archetype_counts.items()} }")
    print(f"Short-history edge cases: {len(short_history_indices)}")
    print(f"Cash-heavy edge cases: {len(cash_heavy_indices)}")

    demo_monthly = monthly_totals(demo)
    print("\nDemo profile (lakshmi) monthly net cashflow:")
    for mk, v in demo_monthly.items():
        print(f"  {mk}: inflow={v['inflow']:.0f} outflow={v['outflow']:.0f} net={v['inflow'] - v['outflow']:.0f}")


if __name__ == "__main__":
    main()
