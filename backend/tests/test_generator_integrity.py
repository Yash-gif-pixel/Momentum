"""Generator data-integrity tests around gaps and reversal pairing.

A `upi_reversal` only makes sense next to the transaction it reverses. Alone,
each half is a phantom: an orphaned reversal is an unexplained negative entry
that depresses a month's income, and an original whose reversal was dropped is
income that was never actually received. Both distort the features and the
label computed from that month.
"""

from __future__ import annotations

import random
import unittest
from datetime import date, timedelta

from backend.generator.generate_dataset import (
    RawTx,
    _in_gap,
    _reversal_day_for,
    apply_gaps,
    build_profile,
    compute_gap_windows,
    inject_noise,
)
from backend.generator.schema import (
    Archetype,
    Channel,
    CounterpartyType,
    Direction,
    HealthTier,
)

START = date(2024, 1, 1)
END = date(2024, 12, 31)


class TestReversalPlacement(unittest.TestCase):
    def test_reversal_does_not_cross_the_seen_holdout_split(self):
        split = date(2024, 7, 1)
        last_seen_day = split - timedelta(days=1)
        placed = _reversal_day_for(
            original=last_seen_day,
            candidate=split,  # would land in the held-out window
            end=END,
            gap_windows=[],
            split_date=split,
        )
        self.assertEqual(placed, last_seen_day)
        self.assertLess(placed, split)

    def test_reversal_of_a_holdout_transaction_may_stay_in_the_holdout(self):
        split = date(2024, 7, 1)
        placed = _reversal_day_for(
            original=split,
            candidate=split + timedelta(days=1),
            end=END,
            gap_windows=[],
            split_date=split,
        )
        self.assertEqual(placed, split + timedelta(days=1))

    def test_reversal_does_not_land_inside_a_data_gap(self):
        gap = (date(2024, 3, 10), date(2024, 3, 15))
        placed = _reversal_day_for(
            original=date(2024, 3, 9),
            candidate=date(2024, 3, 10),  # first day of the gap
            end=END,
            gap_windows=[gap],
            split_date=None,
        )
        self.assertEqual(placed, date(2024, 3, 9))
        self.assertFalse(_in_gap(placed, [gap]))

    def test_reversal_does_not_run_past_the_end_of_history(self):
        placed = _reversal_day_for(
            original=END, candidate=END + timedelta(days=1), end=END,
            gap_windows=[], split_date=None,
        )
        self.assertEqual(placed, END)

    def test_an_ordinary_next_day_reversal_is_left_alone(self):
        placed = _reversal_day_for(
            original=date(2024, 5, 1), candidate=date(2024, 5, 2), end=END,
            gap_windows=[], split_date=None,
        )
        self.assertEqual(placed, date(2024, 5, 2))


class TestNoiseRespectsGaps(unittest.TestCase):
    def test_no_noise_is_injected_into_a_gap(self):
        rng = random.Random(7)
        gap_windows = [(date(2024, 4, 1), date(2024, 4, 20))]
        base = [
            RawTx(
                d=date(2024, 1, 5),
                direction=Direction.IN,
                amount=100.0,
                channel=Channel.UPI,
                counterparty_type=CounterpartyType.CUSTOMER,
                category="sales",
            )
        ]
        result = inject_noise(rng, base, START, END, gap_windows, None)
        in_gap = [t for t in result if _in_gap(t.d, gap_windows)]
        self.assertEqual(in_gap, [], "noise refilled a simulated data gap")

    def test_apply_gaps_removes_transactions_inside_the_windows(self):
        gap_windows = [(date(2024, 4, 1), date(2024, 4, 20))]
        txs = [
            RawTx(
                d=day,
                direction=Direction.IN,
                amount=100.0,
                channel=Channel.UPI,
                counterparty_type=CounterpartyType.CUSTOMER,
                category="sales",
            )
            for day in (date(2024, 3, 31), date(2024, 4, 5), date(2024, 4, 21))
        ]
        kept = {t.d for t in apply_gaps(txs, gap_windows)}
        self.assertEqual(kept, {date(2024, 3, 31), date(2024, 4, 21)})

    def test_gap_windows_stay_inside_the_history(self):
        rng = random.Random(3)
        for _ in range(50):
            for gap_start, gap_end in compute_gap_windows(rng, START, END, 2):
                self.assertGreaterEqual(gap_start, START)
                self.assertLessEqual(gap_start, END)


class TestGeneratedProfilesArePaired(unittest.TestCase):
    """End-to-end: no orphaned reversal on either side of the split."""

    def test_every_reversal_has_a_plausible_original_on_the_same_side(self):
        for seed in range(12):
            rng = random.Random(seed)
            profile = build_profile(
                rng,
                profile_index=seed,
                archetype=list(Archetype)[seed % 4],
                tier=list(HealthTier)[seed % 4],
                cash_heavy=False,
                short_history=False,
            )
            split = profile.meta.split.split_date
            assert split is not None

            for window_name, transactions in (
                ("seen", profile.transactions_seen),
                ("holdout", profile.transactions_holdout),
            ):
                originals = {
                    (t.date, round(t.amount, 2))
                    for t in transactions
                    if t.category != "upi_reversal"
                }
                for reversal in transactions:
                    if reversal.category != "upi_reversal":
                        continue
                    # The original sits on the same day or the day before.
                    same_day = (reversal.date, round(reversal.amount, 2))
                    prior_day = (
                        reversal.date - timedelta(days=1),
                        round(reversal.amount, 2),
                    )
                    self.assertTrue(
                        same_day in originals or prior_day in originals,
                        f"seed {seed}: orphaned reversal in the {window_name} "
                        f"window on {reversal.date} for {reversal.amount}",
                    )


if __name__ == "__main__":
    unittest.main()
