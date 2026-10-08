"""Data-pattern authenticity: is this income trail *too* clean to be real?

The opposite failure mode from `backend.features.sufficiency`. The gate asks
whether there is ENOUGH data to say anything; this asks whether the data that
is there looks like it came from a real business at all. A fabricated or
template-generated trail tends to be smoother than any real one -- real
income has monsoons, festivals, wedding seasons, sick weeks and bad months.

STRICTLY AN ANNOTATION. Nothing here is consulted by `assess_sufficiency` or
by the model, and `check_authenticity` is called only after a score has
already been decided. It cannot move `vitality_score`, `band`, `outcome`,
`confidence` or any other existing field -- a flag here is a prompt for a
human to look, never a deduction. That separation is deliberate: a real
business with unusually steady income (a shop on a fixed monthly contract,
say) would otherwise be silently penalised for being well-run.

Calibration
-----------
The floor below was not chosen from the generator's `TIER_PARAMS` volatility
settings, which turn out to be the wrong reference entirely. Those govern
DAILY multiplicative noise; monthly income CV is dominated by seasonality
(monsoon dip, festival bumps, wedding season) that survives any amount of
daily smoothing. build_demo_profile_lakshmi is the clearest illustration:
`volatility=0.06`, the tightest setting in the whole generator, yet its
actual monthly income CV is 0.409 -- mid-pack, nowhere near a floor.

Measured over all 520 generated profiles plus the committed demo profiles
(see backend/tests/test_authenticity.py, which re-derives these and fails if
they drift):

    profiles with >= 12 monthly income observations   505    min CV 0.1229
    profiles with <  12 monthly income observations    15    min CV 0.0410

_UNIFORMITY_FLOOR = 0.08 sits below every long-history profile in the
population by a factor of ~1.5, and far above the ~0.0 a fabricated flat
trail produces.

Why the minimum-months guard exists
-----------------------------------
The three lowest CVs in the whole population belong to 4- and 9-month
profiles, and the committed `thin_file_002` demo profile (4 months) sits at
CV 0.037 -- comfortably under any floor worth having. None of them are
fabricated. Sample CV over four observations is simply a low-power estimate,
and a short trail has not yet had the chance to meet a monsoon or a festival.

So below `_MIN_INCOME_MONTHS` this returns None -- "cannot tell" -- rather
than "natural", which would be an assurance the data does not support, or
"unusually_uniform", which would flag the shortest real trails in the
dataset. This does mean a fabricated SHORT trail goes unflagged. That is a
real limit, accepted knowingly: those profiles cannot be distinguished from
genuine short ones on this signal, and the sufficiency gate already refuses
to score them.
"""

from __future__ import annotations

from backend.contract.api_schema import AuthenticityCheck

# See the calibration note above. Both are module-level and imported by the
# tests rather than re-typed there, so a change here cannot silently pass.
_UNIFORMITY_FLOOR = 0.08
_MIN_INCOME_MONTHS = 12

_SIGNAL = "income_coefficient_of_variation"

_NATURAL_NOTE = (
    "Month-to-month income variation is within the range real businesses in "
    "this dataset show."
)

_UNIFORM_NOTE = (
    "This business's income shows less month-to-month variation than typical "
    "for any real trail in this dataset — worth a manual look, not a low "
    "score."
)


def check_authenticity(
    income_coefficient_of_variation: float | None,
    n_income_months: int,
) -> AuthenticityCheck | None:
    """Annotate how natural an income trail's variation looks.

    Returns None when the question cannot be answered: either the CV is not
    computable at all (fewer than 2 months of income -- the codebase's
    "None means not computable, never fabricate a zero" convention), or there
    are too few monthly observations for the CV to mean anything. Never
    returns a status it cannot support.
    """
    if income_coefficient_of_variation is None:
        return None
    if n_income_months < _MIN_INCOME_MONTHS:
        return None

    uniform = income_coefficient_of_variation < _UNIFORMITY_FLOOR
    return AuthenticityCheck(
        status="unusually_uniform" if uniform else "natural",
        signal=_SIGNAL,
        observed=float(income_coefficient_of_variation),
        floor=_UNIFORMITY_FLOOR,
        note=_UNIFORM_NOTE if uniform else _NATURAL_NOTE,
    )
