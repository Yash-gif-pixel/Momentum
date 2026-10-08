import 'package:scam_guard/scam_guard.dart';

import 'scam_warning.dart';

ScamWarning scamGuardChecker({
  required String payeeVpa,
  required double amountInr,
  String? payeeName,
  String? note,
}) {
  final result = const ScamGuard().check(
    payeeVpa: payeeVpa,
    amountInr: amountInr,
    payeeName: payeeName,
    note: note,
  );
  return scamWarningFromResult(result);
}

ScamWarning scamWarningFromResult(ScamCheckResult result) {
  final level = switch (result.level) {
    ScamRiskLevel.low => WarningLevel.none,
    ScamRiskLevel.medium => WarningLevel.caution,
    ScamRiskLevel.high => WarningLevel.danger,
  };

  return ScamWarning(
    level: level,
    reasons: result.signals.map((signal) => signal.message).toList(),
    elapsedMs: result.elapsed.inMicroseconds / 1000.0,
  );
}
