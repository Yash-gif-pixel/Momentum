# Data Schema

This document describes the synthetic dataset produced by
`backend/generator/generate_dataset.py`. It's written to be defensible to a
judge: every design choice below is either a documented heuristic or an
explicit "this is our own choice, not a sourced statistic."

**All data in this repository is 100% synthetic.** No real bank statement,
GST, Udyam, or credit-bureau data is used, referenced, or scraped anywhere.

## Transaction object

Each profile is a list of transaction objects shaped to resemble a simulated
Account Aggregator (AA) payload — not a flat CSV. The Pydantic model lives at
`backend/generator/schema.py::Transaction`:

| Field | Type | Notes |
|---|---|---|
| `date` | `YYYY-MM-DD` | |
| `direction` | `"in" \| "out"` | |
| `amount` | number | INR, always positive |
| `channel` | `"upi" \| "cash" \| "neft" \| "card" \| "cheque"` | |
| `counterparty_type` | `"customer" \| "supplier" \| "utility" \| "rent" \| "personal" \| "unknown"` | |
| `category` | string | e.g. `"sales"`, `"raw_material"`, `"electricity_bill"`, `"personal_transfer"` |
| `note` | string \| null | short reference-style tag, e.g. `"UPI/482913/sales"` |
| `likely_shadow_supplier` | bool \| null | only ever set (true/false) when `counterparty_type == "personal"` — see below |

## Profile JSON shape

Each profile file is one JSON object:

```
{
  "meta": {
    "profile_id": "MSME0001",
    "archetype": "street_food_vendor",
    "latent_health_tier": "thriving",
    "is_cash_heavy_edge_case": false,
    "is_short_history_edge_case": false,
    "history_start_date": "2024-03-01",
    "history_end_date": "2026-08-31",
    "months_available": 30,
    "split": { "seen_months": 24, "holdout_months": 6, "split_date": "2026-03-01" }
  },
  "transactions_seen": [ ...Transaction... ],
  "transactions_holdout": [ ...Transaction... ]
}
```

### The 24/6 split

For a full-length profile, `history_start_date` → `history_end_date` spans 30
months. `transactions_seen` holds the first 24 months (usable as model
features by a later task); `transactions_holdout` holds the last 6 months
(reserved for a different, later task to derive labels from — no labeling
logic is implemented here). `split.split_date` marks the exact boundary: every
`transactions_seen` date is `< split_date`, every `transactions_holdout` date
is `>= split_date`.

Short-history edge-case profiles (see below) have less than 12 months of
total history — there isn't enough data to hold 6 months back, so
`split.holdout_months == 0`, `split.split_date == null`, and everything lives
in `transactions_seen`.

`latent_health_tier` is generator-internal ground truth for a later labeling
task. It is **not** meant to be used as a model feature — a real credit model
would not have access to it.

## Business archetypes

Each profile is assigned exactly one archetype, which shapes its income
rhythm and expense structure:

- **street_food_vendor** — daily small inflows (cash/UPI-heavy), a weekend
  bump, a monsoon dip (Jun–Sep), and a festival spike (Oct 1 – Nov 15).
  Daily small raw-material purchases from suppliers; a small daily stall fee
  (`rent`) and shared-meter electricity bill.
- **kirana_store** — steady daily inflows with low variance, monthly lump
  supplier payments (stock restocking) rather than daily small ones, plus
  monthly shop rent and electricity.
- **tailor_salon** — a strong weekly rhythm (weekend-heavy), and strong
  seasonal peaks during Diwali and the Nov–Feb wedding season. Occasional
  (not daily) fabric/material purchases.
- **gig_worker** — irregular inflows, including a deliberately higher chance
  of zero-income days, with a gradual upward trend over the 30 months. No
  rent; a small monthly phone/data recharge stands in for a utility cost.

## Latent health tiers

Every profile is assigned exactly one of four tiers. The **target
proportions across the full 500+ dataset are this project's own design
choice for a synthetic prototype, not sourced from any external statistic**:
thriving ~30%, stable ~35%, struggling ~22%, failing ~13%. The actual
generated distribution will vary somewhat around these targets because tier
assignment is a weighted random draw per profile.

Each tier distinctly parameterizes:

| Tier | Monthly growth | Income volatility (σ) | Missed-day probability | Shock probability / month | Bill on-time rate | Cash bias |
|---|---|---|---|---|---|---|
| thriving | +1.0% | 10% | 2% | 2% | 95% | more digital |
| stable | +0.2% | 16% | 5% | 4% | 85% | neutral |
| struggling | −0.6% | 26% | 12% | 8% | 60% | more cash |
| failing | −1.5% | 36% | 25% | 15% | 35% | most cash |

- **Growth rate** compounds monthly against the archetype's base daily
  revenue.
- **Income volatility** is applied as a per-day Gaussian multiplier on top of
  the seasonal/growth-adjusted expected revenue.
- **Missed/zero-income days** are days where no income transaction is
  generated at all.
- **Shocks** are monthly events (illness, equipment failure) that suppress
  that month's income (severity drawn per-tier) and, half the time, add a
  one-off `equipment_repair` / `medical_expense` outflow.
- **Bill-payment discipline** governs whether the monthly rent/utility is paid
  on time (within 2 days of the due date) or late (6–20 days late, tagged
  `"LATE PAYMENT"` in the `note` field when no digital reference exists).
- **Cash bias** shifts the channel-selection weights toward cash (struggling/
  failing) or away from it (thriving/stable), on top of the archetype's base
  channel mix.

## Noise injection

Regardless of tier, every profile gets:

- **Failed/reversed UPI transactions** — a small sample of UPI transactions
  get a paired reversal (opposite direction, same amount, `category:
  "upi_reversal"`, `note: "REVERSED"`) 0–1 days later.
- **Midnight batch-settlement sweeps** — small aggregator-style adjustment
  entries (`category: "batch_settlement"`, `counterparty_type: "unknown"`,
  `note: "UPI SETTLEMENT BATCH"`), ~3% of days.
- **Rounding artifacts** — tiny (₹0.50–₹5) inflow entries, ~1% of days
  (`category: "rounding_adjustment"`).
- **Short gaps** — 0–2 contiguous 2–7 day windows per profile with no
  transactions at all, simulating a failed AA data pull. (Short-history
  edge-case profiles never get gaps, to keep their already-short history
  interpretable.)

## Edge cases (deliberately included, not filtered out)

- **Cash-heavy profiles** (~15 of 500+) — channel-selection weights are
  overridden so roughly 70%+ of their transactions are cash. Randomly
  assigned, independent of archetype/tier.
- **Short-history profiles** (~15 of 500+) — total history is 4–11 months
  (strictly under 12), with `split.holdout_months == 0`. These exist to test
  a later coverage/sufficiency check, not to be scored normally.

Both edge-case flags are recorded explicitly in `meta.is_cash_heavy_edge_case`
/ `meta.is_short_history_edge_case` so downstream code can find them
deliberately rather than having to infer them statistically.

## Shadow P2M tagging heuristic

For every transaction with `counterparty_type == "personal"`, the generator
adds a derived `likely_shadow_supplier: true | false`.

**Rationale:** in real AA data, a personal UPI VPA that is paid repeatedly on
a regular rhythm and in a stable amount band is more likely to actually be an
informal supplier or customer paid via a personal handle (common for small
MSMEs — e.g. a fixed weekly payment to an unregistered raw-material supplier)
than a genuine one-off personal transfer.

**Exact heuristic implemented** (`generate_dataset.py::tag_shadow_p2m`):

1. Group all `personal` transactions by `(day_of_week, amount_band)`, where
   `amount_band = round(amount / 100) * 100` (₹100-wide bucket).
2. For each group, count the number of **distinct calendar months** in which
   at least one transaction in that group occurred.
3. Every transaction in a group is flagged `likely_shadow_supplier = true` if
   that group appears in **3 or more distinct months**; otherwise `false`.

This schema has no time-of-day field (AA payloads here are daily-granularity),
so day-of-week + amount-band recurrence is used as the observable proxy for
"same rhythm, same counterparty" — a genuine one-off gift or emergency
transfer will essentially never land in the same weekday/amount bucket across
3+ separate months by chance, while a recurring informal-supplier payment
will.

This is a simple, auditable heuristic chosen for defensibility in a pitch —
not a claim of ground truth. A profile can (and does, in the generator) also
contain a deliberately-constructed recurring "shadow supplier" pattern (fixed
weekday, stable amount band, weekly cadence) so the heuristic has true
positives to catch in the synthetic data.

## Demo profile: `demo_profile_lakshmi.json`

Hand-tuned via `generate_dataset.py::build_demo_profile_lakshmi`: a
`street_food_vendor`, `thriving` tier, with volatility, missed-day
probability, and shock probability all turned down and bill-payment
discipline turned up, plus a slightly higher growth rate. This is the profile
used live in the pitch — it's tuned to visibly look like a steady, growing
business with a clear festival-season spike when its monthly totals are
printed or plotted, not just to statistically pass the generator's own
tier logic.

### Three more demo profiles, added to match the frontend's hardcoded ids

The frontend skeleton hardcodes 4 demo profile ids
(`credify_http_service.dart::getAvailableProfileIds`); only `lakshmi_vendor_001`
had a matching committed profile. `data/demo_profile_thin_file.json`,
`data/demo_profile_ramesh_carpentry.json` and
`data/demo_profile_dormancy_gap.json` were added to cover the other 3, all
via `generate_dataset.py` builder functions following the same
hand-tuning pattern as `build_demo_profile_lakshmi`:

- **`build_demo_profile_thin_file`** — `kirana_store`, `stable` tier, a fixed
  seed landing on 5 months of history (`NOT_ASSESSABLE`). Backs
  `thin_file_002`. Deliberately its own dedicated builder rather than an
  alias to `data/sample_profile.json`: that file is picked as "whichever
  short-history, non-cash-heavy profile happens to come first" in `main()`'s
  bulk-generation loop -- deterministic under a fixed `--seed`, but its exact
  identity is an accident of loop order, and would silently change if the
  bulk generation logic or edge-case counts ever changed. A demo id a
  frontend hardcodes needs an identity independent of that.
- **`build_demo_profile_ramesh_carpentry`** — `tailor_salon`, `stable` tier,
  otherwise plain generation (no special tuning). **The generator has no
  dedicated "carpentry" archetype** — only `street_food_vendor`,
  `kirana_store`, `tailor_salon`, `gig_worker` exist. `tailor_salon` is used
  as the closest available fit (a materials-plus-service small trade with a
  weekly rhythm), a deliberate and documented substitution, not a silent
  guess. Adding a real carpentry archetype would need its own generator
  parameters (base revenue, seasonal pattern, expense structure) and was out
  of scope for a single demo profile.
- **`build_demo_profile_dormancy_gap`** — `kirana_store`, `failing` tier,
  with a 60-day gap carved directly out of the middle of its seen window.
  The generator's own noise model (`apply_gaps`) only produces short 2-7 day
  gaps, realistic for an occasional missed AA data pull but too brief to
  read as "this business went dormant" live in a demo; this profile needed
  a much longer, narratively legible gap, so it is removed directly rather
  than relying on that noise path. Scores `vitality_score: 15`,
  `manual_review` — `months_would_cover_emi_of_last_24` drops to 7 of 24 and
  `ontime_bill_payment_rate` to 24%, both surfacing as concerns. Notably,
  the 61-day `longest_dry_streak_days` itself does *not* surface as a
  concern — an honest side effect of that feature's documented coherence-
  filter behavior (see "Reason codes" below), not a bug in this profile.

All three are served via `GET /api/profiles/{profile_id}`
(`backend/api/README.md`), not through the bulk-generated, gitignored
`/data/generated/` — they're committed alongside `demo_profile_lakshmi.json`
since they're referenced by a fixed, known id, not sampled from the 500+
population.

---

# Feature extraction, sufficiency and labels

Everything below documents the second stage of the pipeline: turning a profile
into 12 features, deciding whether it can be scored at all, and deriving the
held-out ground-truth label. No scoring or model training happens here.

## The leakage boundary

This is the rule the rest of this stage is built around:

| Months | Window | Who may read it |
|---|---|---|
| 1–24 | `transactions_seen` | `feature_engine.py` only |
| 25–30 | `transactions_holdout` | `label_engine.py` only |

A feature that can see the held-out window produces a model that validates
brilliantly and fails in production, so the boundary is **enforced, not
trusted**. `backend/common/windows.py::assert_within_window` raises
`LeakageError` if either engine is handed a transaction outside its permitted
range, and each engine calls it before computing anything.

`feature_engine` and `label_engine` never import each other. Their shared
money definitions live in `backend/common/cashflow.py`, which is a set of pure
functions with no opinion about which months it is given.

**The one value that crosses the boundary, and why it is safe.** The label
needs the indicative EMI, which is defined from months 1–24. Rather than
recomputing it, `derive_label(profile, indicative_emi)` takes it as a plain
number from the caller. This is what a lender actually has — the EMI is sized
up front from the history in hand — and it keeps the label engine from ever
reading the seen window.

Two kinds of test defend this:

- **Tripwire tests** smuggle a held-out transaction into the seen list and
  assert `LeakageError` is raised.
- **An invariance test** mutates the held-out window violently (amounts ×1000,
  window emptied, replaced with a single large cash transaction) and asserts
  that *not one of the 12 feature values moves*. This is the test that catches
  a leak which keeps its dates tidy and slips past the tripwire.

A control test asserts the label *does* change with the held-out window, so
the invariance test cannot pass trivially.

## The 12 features

All computed from months 1–24 only. Grouped by the six families in
`FEATURE_FAMILIES`, which downstream scoring reuses to populate the API
contract's `reason_codes.feature` values.

| Family | Feature | Definition |
|---|---|---|
| Regularity | `pct_weeks_with_income` | Share of calendar weeks in the window containing at least one customer inflow. |
| | `income_coefficient_of_variation` | Sample standard deviation of monthly income ÷ mean monthly income. |
| | `longest_dry_streak_days` | Longest unbroken run of days with no trading income, including leading and trailing silence. |
| Growth | `trend_last_6_months` | Last 6 months vs **the same 6 calendar months a year earlier**, as a fraction. See the seasonality note below. |
| | `year_over_year_change` | Months 13–24 income vs months 1–12, as a fraction. Needs 24 months. |
| Discipline | `expense_to_income_ratio` | Total operating outflows ÷ total business income. |
| | `ontime_bill_payment_rate` | Share of rent/utility bills paid by the 7th of the month. |
| Resilience | `cash_buffer_days` | Median monthly surplus ÷ average daily expense. Flow-derived proxy — the payload has no balance field. Negative means the typical month burns cash. |
| | `worst_monthly_dip_pct` | (median monthly income − worst month) ÷ median. 1.0 means a month earned nothing. |
| Affordability | `months_would_cover_emi_of_last_24` | **Flagship.** Count of the 24 months where income ≥ indicative EMI + that month's essential expenses. |
| Trail | `digital_share` | Share of transaction value on UPI/NEFT/card/cheque. |
| | `cash_share` | Share of transaction value in cash. |

### Why `trend_last_6_months` is season-matched

These businesses are strongly seasonal by construction — a street food vendor's
monsoon is always weaker than its festival season. A raw 6-month slope
therefore reports whichever season the window happens to end in. On this
dataset it scored the visibly-growing demo profile at **−3%**, purely because
months 19–24 end in the monsoon.

So with 18+ months of history the feature compares the last 6 months against
the same 6 calendar months a year earlier — this monsoon against last monsoon.
The demo profile then reads **+17%**, which matches what the plotted cashflow
actually does. Below 18 months that comparison is impossible and it falls back
to a normalised least-squares slope, which *is* seasonality-exposed; that
fallback affects only short-history profiles, which are already gated to
`LOW_CONFIDENCE` or `NOT_ASSESSABLE`.

### The flagship is a count, and must be normalized before comparing

`months_would_cover_emi_of_last_24` is an **absolute count**, because the API
contract fixes it as an `int`. It is therefore bounded by how much history a
profile has: a business that covered the EMI in **all 11 of its 11 months**
scores 11, which sits below a 24-month business that missed four.

Ranking profiles on the raw count would penalize a thin file for being thin —
the exact exclusion this project exists to undo. Downstream scoring must
either compare only within the `FULL` cohort (all of which have the same
24-month window) or divide by the window length. The denominator travels with
the feature in the feature table as `sufficiency_months_available`, so the rate
is recoverable without adding a thirteenth feature.

### Noise and reversals

Every money calculation excludes the generator's `batch_settlement` and
`rounding_adjustment` artifacts, so a handful of rupee-scale entries can never
register as a week of trading or inflate a ratio. `upi_reversal` is **not**
excluded — a reversal is a real correction, and is netted off the transaction
it reverses (a reversed customer inflow nets business income back to zero).

Because that netting only works when both halves are present, the generator
guarantees a reversal is never separated from its original. A reversal
normally lands on the same day or the next day, but falls back to the same day
whenever the later date would run past the end of the history, land inside a
data gap, or **cross the seen/held-out split** — which would otherwise strand
a correction to seen-window activity on the held-out side of the boundary and
depress the first held-out month's income. Gap windows are likewise decided
before noise is injected, so noise never refills a gap and a gap never removes
one half of a pair.

### Nulls are deliberate

A feature that is genuinely undefined returns `null`, not a fabricated zero.
Across the 521 profiles:

| Feature | Nulls | Why |
|---|---|---|
| `year_over_year_change` | 15 (2.9%) | Needs 24 months; these are the 15 short-history profiles. |
| `trend_last_6_months` | 5 (1.0%) | Needs 6 months; these have 4–5. |

Every other feature, including the flagship, computes for all 521 profiles.

## Sufficiency gate

Runs **before** any scoring is attempted. A thin file must come back as "we
cannot assess this" rather than as a low score — a low score reads as *this
business is bad* when the truth is *we do not have enough of their history
yet*, and conflating the two is exactly how thin-file businesses get locked
out of credit.

| Outcome | Condition |
|---|---|
| `NOT_ASSESSABLE` | < 6 months of history **OR** < 8 transactions/month |
| `LOW_CONFIDENCE` | 6–12 months of history **OR** 8–15 transactions/month |
| `FULL` | Everything else |

Either condition alone is enough to gate: a long history cannot rescue a
sparse trail, and a dense trail cannot rescue a short history.

**These thresholds are this prototype's own design choice. They are not drawn
from any regulatory standard or published methodology.** The reasoning:

- **Why 6 months and not 3?** These businesses are strongly seasonal, and both
  the monsoon dip and the festival spike last roughly a quarter. A 3-month
  window can sit entirely inside one of them, so it measures the season rather
  than the business — a vendor assessed across a single festival looks
  exceptional, and the same vendor assessed across a single monsoon looks like
  it is failing. Six months is the shortest window that necessarily spans more
  than one seasonal regime.
- **Why 12 months for full confidence?** Twelve months closes a full seasonal
  cycle, so every month can be compared against its own counterpart. Below
  that, growth and volatility features are still measurable but are partly
  reporting where in the year the window happened to fall — hence "low
  confidence" rather than "not assessable".
- **Why ~8 transactions/month?** Below roughly two transactions a week there is
  no rhythm left to measure: regularity, dry streaks and volatility collapse
  into noise, and a single missed week swings them wildly.
- **Why 15 for full confidence?** Between 8 and 15 a month the trail is real
  but thin. Features compute, but each rests on few enough observations that a
  couple of missing entries materially move them.

Density counts **only real business transactions** — settlement sweeps and
rounding artifacts are excluded, so a trail cannot clear the density bar on
noise alone.

**Cash-heavy is not a deficiency.** All 15 planted cash-heavy profiles pass the
gate as `FULL`. They have plenty of transactions; those transactions are simply
in cash. Gating them would rebuild the exclusion this project exists to undo.

### How the gate lands on this dataset

| Outcome | Profiles |
|---|---|
| `FULL` | 506 |
| `LOW_CONFIDENCE` | 10 |
| `NOT_ASSESSABLE` | 5 |

All 15 gated profiles are exactly the 15 short-history edge cases planted in
Y1 — none reaches `FULL`. Note that on this dataset the gate is driven
**entirely by the months rule**: the sparsest profile in the whole set is 27.9
transactions/month, far above the 8/15 density thresholds, because Y1 planted
short-history and cash-heavy edge cases but no low-density ones. The density
branch is therefore covered by unit tests using synthetic sparse profiles
rather than by the generated data.

## Label definition

Derived from the held-out window (months 25–30) only, and behaviourally
grounded rather than an arbitrary cutoff.

1. **Indicative EMI** = 20% of median monthly income over months 1–24.
2. **Essential expenses** = the profile's *actual* recurring outflows —
   `utility`, `rent` and `supplier` counterparties — as they appear in the data
   for each held-out month.
3. For each of the 6 held-out months, ask the question the borrower actually
   faces: after the month's essential running costs, was there enough income
   left to service the EMI?

   ```
   covered(month)  ⟺  income(month) ≥ indicative_emi + essentials(month)
   ```

4. **Label = 1 ("default")** if that fails in **2 or more** of the 6 months,
   otherwise **0**.

**Why 2 months and not 1?** One shortfall is a normal shock for a seasonal
micro-business — an illness, a monsoon week, a broken cart. Branding that a
default would mislabel most of the healthy population. Two or more is a
pattern of being unable to carry the obligation.

The same EMI definition drives the flagship
`months_would_cover_emi_of_last_24` feature, evaluated over months 1–24 instead
of 25–30, so the feature and the label measure the same thing at two different
points in time.

### Two edge cases worth stating explicitly

**A business that stopped trading entirely is a default, not an absence.** If
the held-out window exists but contains no transactions at all, that is the
most severe default there is — six months of zero income against a live
obligation. It is labeled 1. Treating an empty window as "unlabelable" would
silently drop the worst cases from validation and bias the measured default
rate downward.

**A business with no measurable income in months 1–24 is unlabelable.** The
indicative EMI would be zero, and the coverage test would collapse into
`income ≥ essentials` — labeling a dead business as certain to repay. No lender
would size an obligation against no income, so `derive_label` returns `None`.

**Short-history profiles cannot be labeled** either: with no held-out window
there is nothing to label, so those 15 profiles are excluded from validation
rather than guessed at.

### Label distribution

| | Count | Share |
|---|---|---|
| No default (0) | 456 | 90.1% |
| Default (1) | 50 | 9.9% |
| Unlabelable | 15 | — |

The label was never shown the latent health tier, but recovers it cleanly,
which is the main evidence that it measures something real:

| Latent tier | n | Default rate |
|---|---|---|
| thriving | 181 | 0.6% |
| stable | 165 | 1.2% |
| struggling | 93 | 14.0% |
| failing | 67 | 50.7% |

The classes are imbalanced (9.9% positive), which is realistic for a lending
portfolio but means the modeling stage should use stratified splits and rank
metrics such as AUC rather than accuracy.

## Fairness by design

A credit model built on alternative data can launder a demographic proxy into
a score without anyone intending it — and once it is in the training data it is
nearly impossible to spot by looking at the score. So the prohibition is
structural: `feature_engine.py` carries an explicit `EXCLUDED_FIELDS` list, and
`backend/tests/test_fairness.py` parses the AST of every module on the feature
path and fails the build if any banned name is read as an attribute.

**Present in the schema, excluded from features:**

| Field | Why |
|---|---|
| `latent_health_tier` | Generator ground truth — using it would be self-fulfilling label leakage, not a signal a lender could observe. |
| `is_cash_heavy_edge_case` | Generator internal. |
| `is_short_history_edge_case` | Generator internal. |
| `note` | Free-text memo carrying counterparty VPA handles and personal names, which proxy for identity, community and geography. |

**Reserved — must never be introduced as features:** any geography field
(`pincode`, `postal_code`, `district`, `state`, `city`, `village`, `ward`,
`latitude`, `longitude`, `address`, `region`); any demographic field
(`gender`, `sex`, `age`, `date_of_birth`, `caste`, `religion`, `community`,
`language`, `mother_tongue`, `marital_status`, `education`, `disability`); any
identity document (`aadhaar`, `pan`, `voter_id`, `borrower_name`,
`applicant_name`); and merchant classification (`merchant_category_code`,
`mcc`, `merchant_category`, `merchant_name`, `business_name`), since MCC-style
codes proxy for the demographics of who runs and who patronises a given trade.

A test asserts the "present in schema" half really does still exist on the
models and the "reserved" half really does not, so the list cannot rot into
names that no longer mean anything.

`digital_share` and `cash_share` are computed and stored but are
**informational only and must never be used to penalize cash-heavy
businesses.** A cash-heavy street vendor is not a worse credit risk for being
cash-heavy. They exist so the product can describe the quality of a trail and
explain a `LOW_CONFIDENCE` outcome — not to move a score downward. A test
asserts that two profiles with identical cashflow and opposite channel mixes
receive the same sufficiency outcome and the same affordability result.

`build_feature_table.py` is deliberately outside the AST scan: it reads
`latent_health_tier` on purpose, to write the gitignored validation file. That
it keeps ground truth *out* of the feature table is asserted separately.

## Worked example: `demo_profile_lakshmi`

A `thriving` `street_food_vendor` with 24 months of seen history.

| Family | Feature | Value | Reading |
|---|---|---|---|
| Regularity | `pct_weeks_with_income` | 1.00 | Earned in every single week of the window. |
| | `income_coefficient_of_variation` | 0.41 | Variable, but that is the festival/monsoon cycle, not instability. |
| | `longest_dry_streak_days` | 6 | Longest silence is one short data gap. |
| Growth | `trend_last_6_months` | +0.19 | 19% up on the same 6 months a year earlier. |
| | `year_over_year_change` | +0.19 | 19% up year on year — consistent with the above. |
| Discipline | `expense_to_income_ratio` | 0.37 | Keeps ~63 paise of every rupee earned. |
| | `ontime_bill_payment_rate` | 1.00 | Every rent and utility bill paid by the 7th. |
| Resilience | `cash_buffer_days` | 46.0 | Typical monthly surplus covers ~46 days of running costs. |
| | `worst_monthly_dip_pct` | 0.50 | Worst month ran 50% below typical — the monsoon. |
| Affordability | `months_would_cover_emi_of_last_24` | **24** | Could have serviced the EMI in all 24 of its 24 months. |
| Trail | `digital_share` | 0.86 | Mostly digital — informational only. |
| | `cash_share` | 0.14 | |

**Sufficiency:** `FULL` — 24 months of history at 244.0 transactions/month.

**Held-out check (not a feature):** indicative EMI ₹11,298; 0 of the 6 held-out
months fell short, so the label is **0 (no default)** — which is what the
feature profile above would lead you to expect.

## Feature table

`python3 -m backend.scripts.build_feature_table` writes two files, and the
separation between them is the point:

- **`data/feature_table.csv`** — committed, 521 rows. `profile_id`, the 12
  features, the sufficiency outcome, and the two figures the gate ran on
  (`sufficiency_months_available`, `sufficiency_transactions_per_month`).
  **This is the only file a model may read.** Nulls are written as empty cells.
- **`data/labels_holdout.csv`** — **gitignored**, 506 rows. The held-out label,
  months failed, the indicative EMI and the latent health tier. **Validation
  only; never a model input.**

The script refuses to run if any ground-truth column appears in the feature
table schema, so the two can never quietly merge.

CSV rather than Parquet: the table is ~520 rows, and CSV keeps the pipeline
dependency-free (standard library only, beyond the pydantic the generator
already required) so any teammate can run it without setting up an environment.
The feature table is small enough (~105 KB) to commit, unlike the bulk profile
data, which stays gitignored and regenerable.

---

# Scorecard model, reason codes and validation

This documents the third stage of the pipeline: a logistic regression trained
on Y2's feature table, and the inference layer (`backend/model/scorecard.py`)
that turns a profile into an `AnalyzeResponse` matching Y1's API contract
exactly.

## Leakage safety, carried into the model layer

`train_scorecard.py` never reads a raw transaction. It reads
`data/feature_table.csv` (already computed from months 1-24 only, by Y2) and
`data/labels_holdout.csv` (already derived from months 25-30 only, by Y2) and
fits on the numbers, not the dates. The genuinely new leakage surface Y3
introduces is `scorecard.py`'s affordability and monthly-cashflow blocks,
which are computed directly from `profile.transactions_seen` outside of
`extract_features` -- a second, independent place a future edit could wire up
`transactions_holdout` by mistake.

That surface is tested the same way Y2 tested `extract_features`:
`backend/tests/test_model_leakage.py` runs the entire `analyze_profile()`
pipeline against a profile whose held-out window is mutated (amounts
inflated 1000x, emptied, directions flipped) and asserts the response is
byte-for-byte identical regardless. The mutation is placed deliberately at a
date *inside* the seen window, not at the real split boundary -- a leak
placed right at the boundary gets filtered out by ordinary month-key
matching regardless of which list it came from, so a test built that way
would prove only that date filtering works, not that
`transactions_holdout` is actually unread. Verified by deliberately wiring
both blocks to read `transactions_seen + transactions_holdout`: both
mutations were caught (6 failures each), and the clean code passes cleanly.

`train_scorecard.py` also refuses, structurally, to train on anything the
sufficiency gate would refuse to score: a labeled row whose
`sufficiency_outcome` is not `FULL` is excluded before it reaches the
regression (`load_training_table`, tested in `test_model_leakage.py`), so the
model was never fit on a trail it would then decline to score at inference
time -- and the reverse holds too, since `scorecard.py` never calls the model
for anything but a `FULL` profile.

## Training

`python3 -m backend.model.train_scorecard` (needs the venv described below --
this is the one part of the pipeline that needs numpy/scikit-learn).

- **Population**: every profile with `sufficiency_outcome == FULL` AND a
  label in `labels_holdout.csv` -- 506 of the 521 profiles. On the current
  dataset this happens to be the full labeled set (every labeled profile is
  FULL), but the check is explicit and enforced, not assumed.
- **Split**: stratified on the label, by profile_id (the table is already one
  row per business), `test_size=0.25`, `random_state=42` -- 379 train / 127
  test. Every FULL+labeled profile has exactly 24 months of seen history
  (asserted before training proceeds), which is what makes the flagship
  affordability feature's raw count comparable across the population without
  normalization -- see the warning in `feature_engine.py`.
- **Standardization**: z-score, `StandardScaler` fit on the training split
  only, applied to both splits.
- **Target**: the model is fit on **vitality** (1 = no default), not default
  directly -- i.e. `y = 1 - label`. This is so a positive coefficient always
  means "this feature helps this business," matching the reason-code
  contribution formula (`coefficient x standardized value`, positive =
  strength) literally, with no sign-flipping needed downstream.
  `vitality_score = round(100 x P(vitality=1))`, equivalently
  `round(100 x (1 - p_default))`. AUC is still reported in the standard
  "predicting default" framing -- numerically identical either way, since AUC
  is invariant under flipping both the label and the score direction.
- **Model**: `LogisticRegression(C=0.3, max_iter=2000, random_state=42)`. `C`
  was chosen by 5-fold cross-validation **on the training split only**
  (never touching the test split) over `C in {1.0, 0.5, 0.3, 0.2, 0.1, 0.05,
  0.02, 0.01}`: mean CV AUC peaked at `C=0.3` (0.9772 ± 0.0138), close to the
  unregularized default (0.9763), and degraded below `C=0.1` as
  regularization began erasing real signal. This was deliberately not tuned
  against the test-set AUC -- a single ~127-row test split is noisy enough
  that chasing its number would just fit the hyperparameter to that noise.
- **Predictive features**: 10 of the 12, not 12. `digital_share` and
  `cash_share` are excluded from the regression entirely -- see "Fairness in
  the model itself" below.

## Fairness in the model itself, not just at feature-extraction time

Y2 documented that `digital_share`/`cash_share` are "informational only,
never used to penalize cash-heavy businesses." Y3 enforces that literally:
`backend.model.artifact.PREDICTIVE_FEATURES` excludes both, so they are
**never part of the regression's input matrix**. They have no coefficient,
so `compute_contributions` never produces a value for them, so they can
never appear in `reason_codes.strengths` or `reason_codes.concerns`, and they
cannot move `vitality_score` by so much as a rounding error. This is checked
behaviourally in `test_model_artifact.py`: two feature dictionaries identical
except for `digital_share`/`cash_share` produce **exactly** the same
predicted probability.

This is also the statistically correct call independent of fairness:
`digital_share + cash_share == 1` exactly (perfect collinearity), which would
make their individual coefficients numerically unstable and essentially
arbitrary -- a second, values-independent reason to exclude both rather than
leave the split to solver behaviour.

## Coefficient sign sanity check (all 10, verified against ground truth)

**Target convention, stated precisely.** Y2's `label` field is `1 = default`,
`0 = no default` (`backend/labels/label_engine.py`, `label: int  # 1 ==
default, 0 == no default`). `train_scorecard.py` fits on
`y_vitality = 1 - label`, so `y_vitality = 1` means **no default / viable**.
The model's `predict_proba` therefore gives `P(vitality = 1) = P(no
default)`, and **a positive coefficient means "higher standardized value of
this feature pushes toward no default"** -- helps the business. This is the
one and only sign convention used anywhere below; there is no second,
competing framing to get confused between.

Every one of the 10 predictive features was checked against this convention
**two independent ways**: (1) against `reason_codes.py`'s own
`higher_is_better` domain expectation, and (2) against the **raw ground-truth
correlation with the actual default label**, computed directly from
`labels_holdout.csv` and completely independent of the trained model or any
convention this codebase assumes:

| Feature | Coefficient | Ground-truth corr. with default | Sign check |
|---|---|---|---|
| `months_would_cover_emi_of_last_24` | +1.19 | r = -0.730 | correct |
| `ontime_bill_payment_rate` | +0.74 | r = -0.479 | correct |
| `expense_to_income_ratio` | -0.73 | r = +0.426 | correct |
| `worst_monthly_dip_pct` | +0.71 | r = +0.307 | **flipped** |
| `trend_last_6_months` | +0.44 | r = -0.433 | correct |
| `pct_weeks_with_income` | -0.25 | r = +0.072 | **flipped** |
| `year_over_year_change` | +0.24 | r = -0.436 | correct |
| `cash_buffer_days` | +0.22 | r = -0.171 | correct |
| `income_coefficient_of_variation` | -0.12 | r = +0.115 | correct |
| `longest_dry_streak_days` | +0.08 | r = -0.016 | **flipped** |

(Reading the correlation column: `r > 0` means a higher raw value associates
with *more* default in the raw data, so an *intuitively correct* coefficient
on the vitality target should be negative for those rows, and positive where
`r < 0`. That is exactly what "correct" checks above.)

**Direct answer on `income_coefficient_of_variation` (-0.123) and
`expense_to_income_ratio` (-0.731):** both are **correctly signed**, under
either framing. Higher income volatility and a higher expense-to-income ratio
both genuinely associate with more default in the raw data (r = +0.115 and
r = +0.426 respectively), and both get a negative vitality coefficient --
i.e. the model agrees with the ground truth on direction, for both. Neither
belongs in the same bucket as the 3 features below that are actually
sign-flipped.

**But there is a real, separate multicollinearity story about magnitude for
these two**, checked rather than assumed -- their full pairwise correlation
against every other predictive feature:

- `expense_to_income_ratio` has the **second-strongest** univariate
  correlation with default of all 10 features (r = +0.426), yet its
  coefficient (-0.731, while still substantial) does not fully reflect that
  strength, because it is meaningfully collinear with two other features
  already in the model: `cash_buffer_days` (r = -0.627) and
  `months_would_cover_emi_of_last_24` (r = -0.551). All three measure a
  closely related "can this business afford things" signal, and the model
  distributes credit for that signal across the three of them rather than
  concentrating it in one coefficient.
- `income_coefficient_of_variation` has a genuinely **weak** univariate
  signal to start with (r = +0.115 -- third-weakest of the 10), and on top of
  that is diffusely correlated (0.21-0.38, no single dominant pair) with five
  other features that also carry volatility/momentum information:
  `worst_monthly_dip_pct` (r = +0.380), `ontime_bill_payment_rate`
  (r = -0.300), `cash_buffer_days` (r = -0.238), `year_over_year_change`
  (r = -0.227), `trend_last_6_months` (r = -0.207). What little independent
  signal it carries is spread thin across five correlated partners rather
  than concentrated.

**This magnitude effect is explicitly NOT hidden by the reason-code
coherence filter.** The filter (below) only ever silences a feature whose
*sign* disagrees with its own raw value's favorable/unfavorable read --
`income_coefficient_of_variation` and `expense_to_income_ratio` pass that
check cleanly (they are correctly signed) and do surface as real reason
codes for real profiles (18.2% and 70.2% of the FULL cohort respectively --
see "Reason-code frequency" below). The limitation here is different and
narrower: a reader comparing raw coefficient magnitudes across features
should not conclude `income_coefficient_of_variation` is unimportant to
default risk in general -- only that its *independent, partial* contribution
once several correlated volatility measures are already in the model is
smaller than its raw univariate signal would suggest. That is a property of
fitting 10 correlated features jointly, not a data or arithmetic error, and
is recorded here as a documented limitation rather than silently left for a
reader to puzzle out from the coefficients dict alone.

### The 3 features that ARE sign-flipped

| Feature | Fitted coefficient (vitality target) | Naive expectation | Why |
|---|---|---|---|
| `worst_monthly_dip_pct` | +0.71 | negative (a worse dip should hurt) | Collinear with the growth-trend features (r = -0.52 to -0.70 with `trend_last_6_months`/`year_over_year_change`/`ontime_bill_payment_rate`), which carry the real signal; its own univariate correlation with default (r = +0.31) **is** in the intuitive direction. |
| `pct_weeks_with_income` | -0.25 | positive (more weeks earning should help) | Near-zero univariate correlation with default (r = +0.07) once a profile has already cleared the FULL sufficiency gate -- the gate itself is what filters for a readable weekly rhythm, so little independent variance is left to explain. |
| `longest_dry_streak_days` | +0.08 | negative (longer gaps should hurt) | Same story, r = -0.02 -- essentially no independent signal in this cohort. Small magnitude, rarely decisive. |

This was checked, not guessed: cross-validated regularization (above) does
not fix it -- these two features simply carry little independent signal in
the FULL cohort, and no amount of `C` recovers signal that is not there.
`train_scorecard.py` now runs this exact check automatically on every
training pass (comparing each coefficient's sign against
`reason_codes.py`'s `higher_is_better`) and prints a flag next to any
feature that disagrees, so this stays a live diagnostic rather than a
one-time note that can silently go stale.

**This is not swept under the rug in the reason codes.** Each feature
template carries an `is_favorable(value)` domain check independent of the
model. A candidate reason code is only accepted if the raw value's own
favorable/unfavorable read **agrees** with the bucket the statistical
contribution is proposing; a disagreement is skipped, not shown backwards.
Concretely, this means a profile with income arriving in 98% of weeks will
never see that reported as a concern, even though the fitted coefficient
technically points that way for some profiles -- the mismatch is caught and
the reason code is silently omitted instead. Measured across the whole FULL
cohort, this is why `worst_monthly_dip_pct` appears in a reason code for only
3.0% of profiles and `pct_weeks_with_income` for only 9.5%, versus 87.9% for
`ontime_bill_payment_rate` (a cleanly-signed, high-signal feature) -- see
"Reason-code frequency" below for the full table. See
`backend/model/reason_codes.py`'s module docstring for the complete
reasoning and `test_model_reason_codes.py::TestCoherenceFiltering` for the
test that proves a flipped-sign feature is skipped rather than misreported.

## Score formula

`vitality_score` is **not** a linear read of the predicted probability. It is
this profile's percentile rank against a frozen reference population,
inverted so 100 is safest:

    p_default = 1 - sigmoid(intercept + sum(coefficient[f] * standardized_value[f] for f in the 10 predictive features))
    percentile_of_default_risk = rank of p_default within the frozen reference distribution, as a fraction [0, 1]
    vitality_score = round(100 * (1 - percentile_of_default_risk))   # clipped to [0, 100]

**Why not the obvious `round(100 * (1 - p_default))`?** That was the original
formula, and it produced a badly degenerate score histogram -- see
"Validation results" below. Predicted default probabilities on this dataset
are heavily right-skewed (most businesses are genuinely low-risk), so a
linear transform crushed 83.8% of all scored profiles into the single 90-100
bucket, leaving almost no resolution to distinguish a merely-good business
from an excellent one. A percentile-rank transform fixes this **by
construction**: mapping any distribution through its own empirical CDF always
produces an exactly uniform score spread on the reference population, and an
approximately uniform one on any new population drawn similarly.

**The reference population is the TEST split's predicted default
probabilities**, frozen at training time and stored in the artifact -- the
same split `band_cutoffs` is calibrated from, deliberately, so a profile's
score and its band are two consistent statements about the same reference
cohort rather than two different ones. Using the test split for this
calibration step does not compromise `auc_test`'s validity: score/band
calibration happens strictly *after* AUC is computed and never feeds back
into how the model was fit, so it carries none of the overfitting risk that
reusing test data for model *selection* would.

**The honest trade-off:** `vitality_score` stops being a direct read of
"probability this business does not default" and becomes "how this
business's risk compares to the reference cohort's risk distribution." That
is a real change in what the number means, not a free lunch. It is also
exactly how many real-world credit scores work -- a 3-digit score is
typically a rescaled rank against a reference population, not a raw PD read
off directly -- so it is a precedented, defensible design choice rather than
an ad hoc one. `predict_default_probability` (the actual `P(default)`, on its
natural 0-1 scale) remains available separately for anything that needs the
literal probability rather than the rank-based product-facing number --
`band_cutoffs.band_for` uses it directly, not `vitality_score`.

Implemented once, in `backend/model/artifact.py`
(`vitality_score_from_default_probability`), and reused identically by
`validate.py` and `scorecard.py` -- the classic "looks good in the notebook,
wrong in production" bug is a model that scores differently depending on who
re-implements the arithmetic; there is exactly one implementation here.

## Band cutoffs -- calibrated, not guessed

Thresholds on **predicted default probability**, calibrated from the actual
distribution on the held-out test split (never guessed round numbers):

| Band | Condition | Cutoff (predicted default probability) |
|---|---|---|
| `strong_candidate` | `p_default <= P25` of the test set | 0.0058 |
| `manual_review` | everything between | -- |
| `high_risk_referral` | `p_default >= P90` of the test set | 0.4181 |

**Reasoning:** the base default rate in this dataset is ~9.9%. The top
decile (`P90`) of predicted risk is therefore where a reasonably
discriminating model should concentrate most of the actual defaults, making
it a defensible line for "refer for manual underwriting." The bottom quartile
(`P25`) is a comfortably-sized "clear pass" tier without being so narrow it
is useless to a lender. Checked empirically against the test set's actual
outcomes (not just picked and left unverified):

- At the `P90` cutoff (0.4181): **14 of 127** test profiles were referred,
  and **10 of those 14** were actual defaults — **71% precision** at that
  threshold.
- At the `P25` cutoff (0.0058): **33 of 127** test profiles passed, and
  **0 of those 33** were actual defaults — the "clear pass" tier really was
  clear on this split.

### Resulting band distribution (all 506 FULL profiles, trained model)

| Band | Count | Share |
|---|---|---|
| `strong_candidate` | 145 | 28.7% |
| `manual_review` | 313 | 61.9% |
| `high_risk_referral` | 48 | 9.5% |

## Validation results

`python3 -m backend.model.validate` (also needs the venv). Everything below
is read from the committed `backend/model/artifacts/metrics.json`.

### Why AUC 0.9595 doesn't mean what it looks like

**A judge will reasonably ask: "0.96 AUC is extremely high for a credit
model -- is this a leak?" No. Here is precisely why the number is this high,
and it is not the reason that question is worried about.**

Temporal leakage -- the model seeing held-out data -- is independently ruled
out. `assert_within_window` raises the moment either engine reads a
transaction outside its assigned window, and `test_model_leakage.py` goes
further: it runs the *entire scoring pipeline* against a profile whose
held-out window is mutated (amounts scaled 1000x, emptied, directions
flipped) and asserts the output does not move by so much as a rupee. Both
checks were verified to actually catch a leak by deliberately introducing one
and confirming the tests fail. That rules out the mechanism a "0.96 must be
leaking" objection usually means.

The real reason AUC is this high is a property of **how the synthetic data is
generated, not of the model or the pipeline**: in `generate_dataset.py`,
`build_profile` calls `generate_income_days`/`generate_expense_days` **once**
with a single `tier` parameter (`thriving`/`stable`/`struggling`/`failing`)
covering the *entire* 30-month history in one continuous process -- both the
seen window (months 1-24, what the features measure) and the held-out window
(months 25-30, what the label is computed from) are two slices of output from
the *same* tier-conditioned generator run, not independently drawn periods.
The label itself is then a deterministic, rules-based function of the
held-out slice (Y2's `label_engine.py`: does income cover EMI + essentials in
at least 2 of 6 months). So months 1-24's behavioral signature and months
25-30's repayment outcome are both downstream of the *same* latent tier
variable -- the features are, in effect, a fairly direct proxy for the tier,
and the tier in turn almost determines the label. A model that reads the
features well is close to reading the tier, and the tier is close to
determining the outcome. None of that requires or implies the model ever saw
month 25 data while computing a month-1-24 feature.

**What this means practically:** this AUC measures how well *this pipeline*
recovers a signal that *this synthetic dataset's generator* deliberately
built in via a shared latent variable. It is a genuine, useful check that the
feature engineering and modeling code work correctly end to end -- a broken
pipeline (wrong window, a bug in a feature) would NOT reliably hit 0.96 on
this data, so the number is not meaningless. But it should not be read as an
estimate of what AUC a production model would achieve on real transaction
histories predicting real future repayment, where past behavior and future
outcomes are connected by messy, partially-observed, genuinely uncertain
causes (illness, a competitor opening nearby, a supplier relationship
souring) rather than by one shared, fully-determining generator parameter. A
real-world AUC should be expected to be meaningfully lower, and that would
not by itself indicate a worse model -- it would indicate real data.

- **AUC (test split, n=127): 0.9595.**
- **Coverage (all 521 profiles, gate-driven -- single source of truth from
  Y2's `sufficiency_outcome` column, not a model estimate):**

  | Outcome | Count | Share |
  |---|---|---|
  | `SCORED` (sufficiency `FULL`) | 506 | 97.12% |
  | `LOW_CONFIDENCE` | 10 | 1.92% |
  | `NOT_ASSESSABLE` | 5 | 0.96% |

- **Score histogram -- fixed, no longer degenerate.** Under the original
  linear `100*(1-p_default)` formula, 424 of 506 scored profiles (83.8%)
  landed in the single 90-100 bucket. Diagnosed as a consequence of the
  skewed label distribution (~90% no-default) combined with a well-separating
  model correctly pushing most of that healthy majority toward a probability
  near 0, and fixed by remapping `vitality_score` to a percentile rank
  against a frozen reference distribution rather than a linear transform of
  the probability (see "Score formula" above for the full reasoning). After
  the fix, on the same 506 profiles:

  | Bucket | Count |
  |---|---|
  | 0-10 | 48 |
  | 10-20 | 39 |
  | 20-30 | 43 |
  | 30-40 | 38 |
  | 40-50 | 43 |
  | 50-60 | 54 |
  | 60-70 | 60 |
  | 70-80 | 74 |
  | 80-90 | 46 |
  | 90-100 | 61 |

  Largest bucket is now 74/506 (14.6%), well under the 50%-of-population
  threshold `validate.py` flags as degenerate. `score_histogram_degenerate`
  in `metrics.json` is `false`.
- **Reason-code frequency**, across all 506 scored profiles (coherence-filtered
  as described above):

  | Feature | Appeared in |
  |---|---|
  | `ontime_bill_payment_rate` | 87.9% |
  | `months_would_cover_emi_of_last_24` | 72.7% |
  | `expense_to_income_ratio` | 70.2% |
  | `trend_last_6_months` | 65.0% |
  | `year_over_year_change` | 37.9% |
  | `income_coefficient_of_variation` | 18.2% |
  | `longest_dry_streak_days` | 12.5% |
  | `cash_buffer_days` | 11.3% |
  | `pct_weeks_with_income` | 9.5% |
  | `worst_monthly_dip_pct` | 3.0% |

## 12-vs-24-month stability check -- an honest, significant finding

25 test-split profiles were re-scored with their seen window truncated to
their first 12 months, and compared against their normal 24-month score.
**This bypasses the sufficiency gate on purpose**, since a real 12-month
profile is `LOW_CONFIDENCE` and would never reach the model in production
(`analyze_profile` would return `vitality_score: null`); the point is to
measure the underlying model's raw sensitivity to reduced history, not to
claim a 12-month profile would actually be scored.

**Result: scores do NOT stay close.** Mean absolute difference **42.44
points**, max **82 points**, and **20 of the 25** profiles swung by more than
20 points. (These numbers moved from the previous write-up's 79.84/94/24 of
25 after the percentile-rank score fix above -- the rank transform is less
sensitive to the extreme tail than the old linear one was, since it compares
relative position rather than raw probability magnitude, so some of the most
extreme swings got compressed. The underlying cause below, and the fact that
this remains a real, significant instability, are unchanged.) This is
reported as-is, not smoothed over.

**Root cause, diagnosed rather than guessed:** `months_would_cover_emi_of_last_24`
has the largest-magnitude coefficient (+1.19) and is on a 0-24 scale in the
training population (every FULL profile has 24 seen months). Evaluated on a
12-month-truncated profile, the same feature is recomputed from scratch and
naturally caps at 12 -- roughly half its normal range. Worked example
(`MSME0001`): the raw count drops from 22 (of 24) to 10 (of 12), and because
the scaler's mean/scale were fit on the 24-month population, the standardized
value collapses from z = -0.35 to z = -5.22 -- more than five standard
deviations outside anything the model saw during training. At a coefficient
of +1.19, that single feature's swing alone moves the logit by roughly -5.8,
enough on its own to move a healthy profile's predicted probability from
near-certain to near-zero.

This is exactly the risk `feature_engine.py` already flagged in its own
docstring for this feature ("this is an ABSOLUTE COUNT... ranking profiles on
the raw count would penalize a thin file for being thin") -- the stability
check turns that documented warning into a measured, quantified effect. It
is a genuine limitation of directly reusing the flagship feature outside its
original 24-month context, not a bug in the arithmetic, and matters directly
for a follow-up task: a model meant to reasonably score profiles with
different history lengths would need this feature normalized (e.g. months
covered / months available) rather than used as a raw count, or would need
separate scalers per history length. Out of scope to fix here; reported so
the next task does not rediscover it the hard way.

## Worked example: `demo_profile_lakshmi`, scored end to end

The same thriving `street_food_vendor` from Y1/Y2's worked example, now run
through the trained scorecard:

    vitality_score: 91.0
    band: strong_candidate
    confidence: high

(`vitality_score` is 91, not a flat 100, precisely because it is now a
percentile rank rather than a linear transform -- see "Score formula" above.
A perfect 100 would only mean "safer than every single profile in the
reference cohort," which is a different and much stronger claim than "this
profile has essentially no measurable default risk," the latter being what
its underlying `p_default` -- 0.002 -- already says on its own. 91 correctly
reads as "excellent, near the top, but not asserting it's literally the
single best profile ever scored.")

**Strengths** (top 3, ranked by |contribution|):

1. `ontime_bill_payment_rate` (contribution +0.729) — "Rent and utility bills
   were paid on time 100% of the time."
2. `months_would_cover_emi_of_last_24` (contribution +0.549) — "Income would
   have covered an indicative loan payment in 24 of the last 24 months."
3. `trend_last_6_months` (contribution +0.514) — "Income is up 19% versus
   the same period a year earlier — growing."

**Concerns:** none — every predictive feature reads favorably for this
profile, so nothing survives the coherence filter on the concerns side. This
is expected and correct, not a bug: "never pad with filler" applies here too.

**Affordability:** indicative EMI range ₹8,990–₹13,607 (centered on the
₹11,298 base figure — 20% of median monthly seen-window income — widened by
half the profile's own income volatility, capped to a 10–40% margin);
`months_would_cover_emi_of_last_24: 24`.

This matches Y2's own worked example for the same profile (EMI ₹11,298 base,
0 of 6 held-out months failed, label 0/no-default) end to end.
