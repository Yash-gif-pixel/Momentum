"""Shared cashflow primitives used by both the feature engine and the label engine.

Both engines must agree on what "income", "essential expenses" and the
"indicative EMI" mean, otherwise the flagship affordability feature and the
held-out label would be measuring different things and the model would be
learning against a moving target.

Those shared definitions live here rather than in either engine, so that
`feature_engine` and `label_engine` never import from each other. Everything
in this module is a pure function over a list of transactions -- it has no
opinion about *which* months those transactions came from. Enforcing the
seen / held-out boundary is `backend.common.windows`' job, and each engine
calls that guard before handing its transactions here.
"""

from __future__ import annotations

from statistics import median
from typing import Iterable

from backend.common.windows import MonthWindow, iter_month_keys, month_key
from backend.generator.schema import CounterpartyType, Direction, Transaction

# Generator-injected artifacts that represent settlement/rounding noise rather
# than real business activity. Excluded from every money calculation so a
# handful of rupee-scale artifacts cannot move a ratio or inflate a count.
# NOTE: "upi_reversal" is deliberately NOT here -- a reversal is a real
# correction and must be netted off the transaction it reverses.
NOISE_CATEGORIES: frozenset[str] = frozenset({"batch_settlement", "rounding_adjustment"})

# Counterparties whose outflows are treated as non-discretionary running costs.
# This is the "essential expenses" set referenced by the label definition.
ESSENTIAL_COUNTERPARTIES: frozenset[CounterpartyType] = frozenset(
    {CounterpartyType.UTILITY, CounterpartyType.RENT, CounterpartyType.SUPPLIER}
)

# Counterparties treated as business operating costs for the broader
# expense-to-income ratio (essentials plus personal drawings and one-off
# shocks such as equipment repair / medical expense, which land on UNKNOWN).
EXPENSE_COUNTERPARTIES: frozenset[CounterpartyType] = frozenset(
    {
        CounterpartyType.SUPPLIER,
        CounterpartyType.UTILITY,
        CounterpartyType.RENT,
        CounterpartyType.PERSONAL,
        CounterpartyType.UNKNOWN,
    }
)

# Bills dated on or before this day of the month count as paid on time.
# The synthetic billing cycle models a due date on the 5th; a 2-day grace
# window makes the 7th the cutoff. In production this would come from the
# biller's actual due date rather than a fixed convention.
BILL_ON_TIME_DAY_OF_MONTH = 7

# The indicative EMI a lender might extend, as a share of median monthly
# income. Used identically by the flagship affordability feature (over the
# seen window) and by the label engine (over the held-out window).
EMI_SHARE_OF_MEDIAN_INCOME = 0.20


def is_noise(tx: Transaction) -> bool:
    return tx.category in NOISE_CATEGORIES


def _signed(tx: Transaction, inflow_positive: bool) -> float:
    """Amount signed so that the 'expected' direction is positive.

    Reversals are the reason this exists: a reversed customer inflow appears
    as an OUT transaction still tagged `customer`, so summing signed amounts
    over customer transactions nets the reversal off automatically.
    """
    is_in = tx.direction == Direction.IN
    positive = is_in if inflow_positive else not is_in
    return tx.amount if positive else -tx.amount


def monthly_business_income(
    transactions: Iterable[Transaction], window: MonthWindow
) -> dict[str, float]:
    """Net business income per calendar month.

    Business income == money from `customer` counterparties, net of reversals.
    Personal transfers, settlement sweeps and rounding artifacts are excluded,
    so a rupee-scale artifact can never register as a month (or week) of
    trading activity.

    Every month in `window` is present in the result, including months with no
    trading at all, which appear as 0.0.
    """
    totals = {key: 0.0 for key in iter_month_keys(window)}
    for tx in transactions:
        if is_noise(tx) or tx.counterparty_type != CounterpartyType.CUSTOMER:
            continue
        key = month_key(tx.date)
        if key in totals:
            totals[key] += _signed(tx, inflow_positive=True)
    return totals


def monthly_essential_expenses(
    transactions: Iterable[Transaction], window: MonthWindow
) -> dict[str, float]:
    """Non-discretionary running costs per calendar month.

    These are the profile's *actual* recurring outflows as they appear in the
    data -- utility, rent and supplier payments -- not a modelled assumption.
    """
    totals = {key: 0.0 for key in iter_month_keys(window)}
    for tx in transactions:
        if is_noise(tx) or tx.counterparty_type not in ESSENTIAL_COUNTERPARTIES:
            continue
        key = month_key(tx.date)
        if key in totals:
            totals[key] += _signed(tx, inflow_positive=False)
    return totals


def monthly_total_expenses(
    transactions: Iterable[Transaction], window: MonthWindow
) -> dict[str, float]:
    """All operating outflows per month (essentials + personal + shocks)."""
    totals = {key: 0.0 for key in iter_month_keys(window)}
    for tx in transactions:
        if is_noise(tx) or tx.counterparty_type not in EXPENSE_COUNTERPARTIES:
            continue
        key = month_key(tx.date)
        if key in totals:
            totals[key] += _signed(tx, inflow_positive=False)
    return totals


def monthly_gross_cashflow(
    transactions: Iterable[Transaction], window: MonthWindow
) -> dict[str, dict[str, float]]:
    """Gross inflow and outflow per calendar month, across every counterparty type.

    Unlike `monthly_business_income` (customer-only, reversals netted to zero),
    this is a full-picture DISPLAY total: every non-noise transaction counts by
    its own direction, so a reversal shows up as its own entry on the side it
    actually landed rather than cancelling out. This is what a cashflow chart
    shown to a lender should look like -- not a scoring input, and not used by
    feature_engine or label_engine.
    """
    totals = {key: {"inflow": 0.0, "outflow": 0.0} for key in iter_month_keys(window)}
    for tx in transactions:
        if is_noise(tx):
            continue
        key = month_key(tx.date)
        if key not in totals:
            continue
        side = "inflow" if tx.direction == Direction.IN else "outflow"
        totals[key][side] += tx.amount
    return totals


def indicative_emi(monthly_income: dict[str, float]) -> float:
    """Indicative monthly EMI: 20% of median monthly income.

    THE SINGLE DEFINITION. The flagship affordability feature evaluates this
    over months 1-24 and the label engine evaluates the same figure over
    months 25-30; both must call this function so the feature and the label
    can never drift apart.

    Callers must pass income from the SEEN window only -- the EMI is part of
    what a lender would compute up front, so deriving it from held-out months
    would leak the future into both the feature and the label.
    """
    if not monthly_income:
        return 0.0
    return max(0.0, EMI_SHARE_OF_MEDIAN_INCOME * median(monthly_income.values()))


def months_covering_emi(
    monthly_income: dict[str, float],
    monthly_essentials: dict[str, float],
    emi: float,
) -> int:
    """Count months where income covered the EMI on top of essential expenses.

    A month "covers" when: income >= emi + essential expenses for that month.
    """
    covered = 0
    for key, income in monthly_income.items():
        if income >= emi + monthly_essentials.get(key, 0.0):
            covered += 1
    return covered
