"""Pydantic models for the synthetic MSME transaction + profile schema.

These models describe the shape of the simulated Account Aggregator (AA)
transaction payload produced by generate_dataset.py. They are the source of
truth for what a "profile JSON file" looks like on disk in /data/generated/
(and for the two committed samples in /data/).

See /docs/DATA_SCHEMA.md for the full narrative documentation (archetypes,
health tiers, noise model, Shadow-P2M heuristic).
"""

from __future__ import annotations

from datetime import date
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field, model_validator


class Direction(str, Enum):
    IN = "in"
    OUT = "out"


class Channel(str, Enum):
    UPI = "upi"
    CASH = "cash"
    NEFT = "neft"
    CARD = "card"
    CHEQUE = "cheque"


class CounterpartyType(str, Enum):
    CUSTOMER = "customer"
    SUPPLIER = "supplier"
    UTILITY = "utility"
    RENT = "rent"
    PERSONAL = "personal"
    UNKNOWN = "unknown"


class Archetype(str, Enum):
    STREET_FOOD_VENDOR = "street_food_vendor"
    KIRANA_STORE = "kirana_store"
    TAILOR_SALON = "tailor_salon"
    GIG_WORKER = "gig_worker"


class HealthTier(str, Enum):
    """Latent ground-truth business health tier.

    This is generator-internal ground truth, not a feature a model should see.
    It exists so a later labeling task can derive outcomes without this task
    building any labeling logic itself.
    """

    THRIVING = "thriving"
    STABLE = "stable"
    STRUGGLING = "struggling"
    FAILING = "failing"


class Transaction(BaseModel):
    date: date
    direction: Direction
    amount: float = Field(gt=0, description="INR, positive")
    channel: Channel
    counterparty_type: CounterpartyType
    category: str
    note: Optional[str] = None
    likely_shadow_supplier: Optional[bool] = Field(
        default=None,
        description=(
            "Only populated (true/false) when counterparty_type == 'personal'. "
            "Derived heuristic flag — see docs/DATA_SCHEMA.md 'Shadow P2M tagging'."
        ),
    )

    @model_validator(mode="after")
    def _shadow_flag_only_for_personal(self) -> "Transaction":
        if self.counterparty_type != CounterpartyType.PERSONAL:
            if self.likely_shadow_supplier is not None:
                raise ValueError(
                    "likely_shadow_supplier may only be set when "
                    "counterparty_type == 'personal'"
                )
        return self


class SplitInfo(BaseModel):
    """Marks the structural 24-months-seen / 6-months-holdout boundary.

    seen months are index [0, seen_months) counting from history_start_date;
    holdout months are the remaining months up to history_end_date. Profiles
    with total history shorter than 12 months (edge cases, by design) have
    holdout_months == 0 — there is not enough history to hold anything back,
    and all transactions live in transactions_seen.
    """

    seen_months: int
    holdout_months: int
    split_date: Optional[date] = Field(
        default=None,
        description="First date of the holdout window; null when holdout_months == 0.",
    )


class ProfileMeta(BaseModel):
    profile_id: str
    archetype: Archetype
    latent_health_tier: HealthTier = Field(
        description="Ground truth for later labeling tasks. Not a model feature."
    )
    is_cash_heavy_edge_case: bool = False
    is_short_history_edge_case: bool = False
    history_start_date: date
    history_end_date: date
    months_available: int = Field(
        description="Total number of calendar months spanned by this profile's history."
    )
    split: SplitInfo


class Profile(BaseModel):
    meta: ProfileMeta
    transactions_seen: list[Transaction]
    transactions_holdout: list[Transaction] = Field(default_factory=list)
