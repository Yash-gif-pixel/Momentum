enum ScamRiskLevel { low, medium, high }

class ScamContext {
  final bool? isFirstTimePayee;
  final double? typicalAmountInr;

  const ScamContext({this.isFirstTimePayee, this.typicalAmountInr});
}

class ScamSignal {
  final String code;
  final String message;
  final int weight;

  const ScamSignal({required this.code, required this.message, required this.weight});
}

class ScamCheckResult {
  final ScamRiskLevel level;
  final int score;
  final List<ScamSignal> signals;
  final Duration elapsed;

  const ScamCheckResult({required this.level, required this.score, required this.signals, required this.elapsed});

  bool get shouldWarn => level != ScamRiskLevel.low;
}
