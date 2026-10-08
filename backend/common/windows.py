"""Time-window definitions and the label-leakage guard.

This module is the single place that decides which calendar range counts as
"seen" history (months 1-24, usable for features) and which counts as the
"held-out" window (months 25-30, usable only for deriving labels).

The leakage guard here is deliberately an *enforced* check, not a convention:
`assert_within_window` raises `LeakageError` the moment a transaction outside
the expected range is handed to an engine. `feature_engine` calls it with the
seen window and `label_engine` calls it with the held-out window, so a future
edit that accidentally routes held-out transactions into feature extraction
fails loudly instead of silently producing an optimistic model.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, timedelta
from typing import Iterable, Iterator

from backend.generator.schema import Profile, Transaction


class LeakageError(AssertionError):
    """Raised when transactions cross the seen / held-out boundary.

    Subclasses AssertionError so it reads naturally in tests, but it is raised
    unconditionally — it is NOT stripped by `python -O`, unlike a bare
    `assert` statement.
    """


@dataclass(frozen=True)
class MonthWindow:
    """An inclusive [start, end] calendar range with a human-readable name."""

    start: date
    end: date
    name: str

    def contains(self, day: date) -> bool:
        return self.start <= day <= self.end

    @property
    def n_months(self) -> int:
        return months_between(self.start, self.end) + 1


def months_between(a: date, b: date) -> int:
    """Whole calendar months from a to b (same month -> 0)."""
    return (b.year - a.year) * 12 + (b.month - a.month)


def month_key(day: date) -> str:
    return f"{day.year:04d}-{day.month:02d}"


def iter_month_keys(window: MonthWindow) -> Iterator[str]:
    """Yield every calendar month key in the window, including empty ones.

    Enumerating months from the window (rather than from the transactions
    present) is what makes a zero-income month count as a real zero instead of
    silently vanishing from medians, averages and coverage counts.
    """
    year, month = window.start.year, window.start.month
    end_year, end_month = window.end.year, window.end.month
    while (year, month) <= (end_year, end_month):
        yield f"{year:04d}-{month:02d}"
        month += 1
        if month > 12:
            year, month = year + 1, 1


def iter_week_keys(window: MonthWindow) -> Iterator[str]:
    """Yield every ISO week key (e.g. '2025-W07') covered by the window."""
    seen: set[str] = set()
    day = window.start
    while day <= window.end:
        iso = day.isocalendar()
        key = f"{iso.year:04d}-W{iso.week:02d}"
        if key not in seen:
            seen.add(key)
            yield key
        day += timedelta(days=1)


def week_key(day: date) -> str:
    iso = day.isocalendar()
    return f"{iso.year:04d}-W{iso.week:02d}"


def seen_window(profile: Profile) -> MonthWindow:
    """The months-1-24 range a model is allowed to learn from.

    For short-history edge-case profiles (no held-out window at all) this is
    simply the profile's entire history.
    """
    meta = profile.meta
    split = meta.split.split_date
    end = split - timedelta(days=1) if split is not None else meta.history_end_date
    return MonthWindow(start=meta.history_start_date, end=end, name="seen")


def holdout_window(profile: Profile) -> MonthWindow | None:
    """The months-25-30 range used only to derive labels.

    Returns None for short-history profiles, which have no held-out window --
    there is not enough history to hold anything back, so they cannot be
    labeled at all.
    """
    meta = profile.meta
    split = meta.split.split_date
    if split is None or meta.split.holdout_months == 0:
        return None
    return MonthWindow(start=split, end=meta.history_end_date, name="holdout")


def assert_within_window(
    transactions: Iterable[Transaction],
    window: MonthWindow,
    caller: str,
) -> None:
    """Fail loudly if any transaction falls outside `window`.

    This is the leakage tripwire. `caller` names the engine so the error
    message points straight at the module that reached across the boundary.
    """
    for tx in transactions:
        if not window.contains(tx.date):
            raise LeakageError(
                f"{caller} received a transaction dated {tx.date.isoformat()} "
                f"outside its permitted '{window.name}' window "
                f"[{window.start.isoformat()} .. {window.end.isoformat()}]. "
                "This is a label-leakage boundary violation: feature code must "
                "read only months 1-24 and label code only months 25-30."
            )
