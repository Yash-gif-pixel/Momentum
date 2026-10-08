import 'models.dart';
import 'rules.dart';
import 'blocklist.dart';

class ScamGuard {
  const ScamGuard();

  ScamCheckResult check({
    required String payeeVpa,
    required double amountInr,
    String? payeeName,
    String? note,
  }) {
    final stopwatch = Stopwatch()..start();
    final vpa = payeeVpa.trim().toLowerCase();
    final handle = vpa.contains('@') ? vpa.substring(0, vpa.indexOf('@')) : vpa;
    final normalizedNote = (note ?? '').toLowerCase();
    final signals = <ScamSignal>[];

    void add(String code, String message, int weight) {
      signals.add(ScamSignal(code: code, message: message, weight: weight));
    }

    if (!RegExp(r'^[a-z0-9._-]+@[a-z]+$').hasMatch(vpa)) {
      add('INVALID_VPA_FORMAT', 'This payment address does not look like a standard UPI ID.', invalidVpaWeight);
    }
    if (RegExp(r'\b(urgent|urgently|immediately|last chance|right now|turant|jaldi|abhi)\b').hasMatch(normalizedNote) ||
        urgencyDevanagariKeywords.any(normalizedNote.contains)) {
      add('URGENCY_LANGUAGE', 'The note pressures you to pay urgently.', urgencyLanguageWeight);
    }
    if (RegExp(r'\b(kyc|account\s+(?:is\s+)?(?:blocked|suspended)|pan\s+(?:card|number|no|details)|update\s+pan|pan\s+update|pan\s+verification|aadhaar|aadhar|otp)\b').hasMatch(normalizedNote) ||
        kycOrAccountBlockDevanagariKeywords.any(normalizedNote.contains)) {
      add('KYC_OR_ACCOUNT_BLOCK', 'The note mentions account or identity details that scammers may request.', kycOrAccountBlockWeight);
    }
    if (RegExp(r'\b(refund|cashback|lottery|prize|reward|you have won)\b').hasMatch(normalizedNote) ||
        refundOrPrizeBaitDevanagariKeywords.any(normalizedNote.contains)) {
      add('REFUND_OR_PRIZE_BAIT', 'The note offers a refund, prize, or reward.', refundOrPrizeBaitWeight);
    }

    final hasSupportWord = supportWords.keys.any((word) => handle.contains(word));
    final hasBrandWord = brandWords.any((word) => handle.contains(word));
    if (hasSupportWord && hasBrandWord) {
      add('BRAND_IMPERSONATION_VPA', 'This payment address combines a brand name with a support-style name.', brandImpersonationVpaWeight);
    }

    final digits = RegExp(r'\d').allMatches(handle).length;
    if (handle.length >= highDigitMinimumLength && digits / handle.length >= highDigitMinimumRatio) {
      add('HIGH_DIGIT_HANDLE', 'This payment address has an unusually long, mostly numeric name.', highDigitHandleWeight);
    }

    if (payeeName != null) {
      final tokens = payeeName.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((token) => token.length >= 3);
      if (tokens.isNotEmpty && !tokens.any(handle.contains)) {
        add('NAME_VPA_MISMATCH', 'The account name does not seem to match the payment address.', nameVpaMismatchWeight);
      }
    }
    if (knownScamVpas.contains(vpa)) {
      add('KNOWN_SCAM_VPA', 'This payment address is on the SDK’s demo warning list.', knownScamVpaWeight);
    }

    final score = signals.fold<int>(0, (sum, signal) => sum + signal.weight).clamp(0, maximumRiskScore).toInt();
    final level = score >= highRiskThreshold
        ? ScamRiskLevel.high
        : score >= mediumRiskThreshold
            ? ScamRiskLevel.medium
            : ScamRiskLevel.low;
    stopwatch.stop();
    return ScamCheckResult(level: level, score: score, signals: List.unmodifiable(signals), elapsed: stopwatch.elapsed);
  }
}
