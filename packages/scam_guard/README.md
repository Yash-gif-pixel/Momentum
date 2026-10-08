# Scam Guard

Scam Guard is a pure-Dart, synchronous heuristic SDK for checking payment details immediately before a host app shows its UPI PIN screen. It uses simple text and VPA pattern rules; it is not machine learning and does not verify a recipient or guarantee that a payment is safe. The host app can show its result as a human-readable, non-blocking warning.

## Public API

Import `package:scam_guard/scam_guard.dart`. Create a `const ScamGuard()` and call `check` with the required `payeeVpa` and `amountInr`, plus optional `payeeName`, `note`, and `context`. `ScamContext` carries optional host-app history (`isFirstTimePayee` and `typicalAmountInr`); pass it when the host app knows that information. Omitted or unknown context leaves the new context-based signals inactive. The call remains backward compatible when `context` is omitted. It returns `ScamCheckResult` with a `ScamRiskLevel`, a score from 0 to 100, matching `ScamSignal`s, elapsed time, and `shouldWarn`.

## Signals

| Signal code | Weight | What triggers it |
|---|---:|---|
| `INVALID_VPA_FORMAT` | 25 | VPA does not match `<handle>@<provider>` (handle letters/digits/dot/hyphen/underscore; provider letters only). |
| `URGENCY_LANGUAGE` | 20 | Note contains urgency terms such as urgent, immediately, last chance, turant, jaldi, or abhi. |
| `KYC_OR_ACCOUNT_BLOCK` | 25 | Note mentions KYC, blocked/suspended account, PAN in an identity context (PAN card, number, no, details, update, or verification), Aadhaar, or OTP. |
| `REFUND_OR_PRIZE_BAIT` | 20 | Note mentions refund, cashback, lottery, prize, reward, or “you have won”. |
| `BRAND_IMPERSONATION_VPA` | 30 | VPA handle combines a support-style term and a known brand/bank-style term. |
| `HIGH_DIGIT_HANDLE` | 15 | Handle has at least 8 characters and at least 80% are digits. |
| `NAME_VPA_MISMATCH` | 10 | A supplied payee name has tokens of 3+ characters and none occur in the VPA handle. |
| `KNOWN_SCAM_VPA` | 60 | VPA exactly matches the small synthetic demo blocklist. |
| `FIRST_TIME_PAYEE` | 10 | Host context confirms this is the first payment to the payee. |
| `AMOUNT_FAR_ABOVE_USUAL` | 15 | Host context provides a positive typical amount and the current payment is at least 3 times that amount. |

Signals are case-insensitive. The three note-based signals also recognize the Devanagari keywords तुरंत, जल्दी, अभी, आखिरी मौका; केवाईसी, खाता बंद, खाता ब्लॉक, आधार, ओटीपी, पैन कार्ड; and रिफंड, कैशबैक, लॉटरी, इनाम, आप जीत गए. These Hindi terms are matched as normalized-note substrings. Dart's `RegExp` `\b` boundary only recognizes ASCII letters as word characters, so Devanagari terms are checked separately without `\b`; English and romanised Hinglish terms retain their word-boundary regexes. Each note signal is added at most once, even when both forms match. The score is the sum of triggered weights, capped at 100. Levels are low below 30, medium from 30 to below 60, and high from 60.

**Non-blocking by design: the SDK never stops, delays, or intercepts a payment.** It performs no network, file, or payment-rail access; the host payment app remains responsible for showing or dismissing any warning.
