/// The result returned by the on-device scam check.
enum WarningLevel { none, caution, danger }

class ScamWarning {
  final WarningLevel level;
  final List<String> reasons;
  final double elapsedMs;

  const ScamWarning({
    required this.level,
    required this.reasons,
    required this.elapsedMs,
  });
}

typedef ScamChecker = ScamWarning Function({
  required String payeeVpa,
  required double amountInr,
  String? payeeName,
  String? note,
});
