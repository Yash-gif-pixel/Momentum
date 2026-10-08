import 'scam_warning.dart';

// Not used by the app; kept for tests.
// Demo stand-in. Replaced by package:scam_guard via an adapter.
ScamWarning demoScamChecker({
  required String payeeVpa,
  required double amountInr,
  String? payeeName,
  String? note,
}) {
  final content = '${payeeVpa.toLowerCase()} ${payeeName?.toLowerCase() ?? ''} '
      '${note?.toLowerCase() ?? ''}';
  const dangerKeywords = ['kyc', 'urgent'];
  const cautionKeywords = ['refund', 'lottery'];

  final dangerMatches = dangerKeywords
      .where((keyword) => content.contains(keyword))
      .toList();
  final cautionMatches = cautionKeywords
      .where((keyword) => content.contains(keyword))
      .toList();
  if (dangerMatches.isNotEmpty) {
    return ScamWarning(
      level: WarningLevel.danger,
      reasons: [
        'The payment note or recipient contains a high-risk phrase: '
            '${dangerMatches.join(', ')}.',
        'Scammers may use urgent messages to pressure you into sending money.',
      ],
      elapsedMs: 2.4,
    );
  }
  if (cautionMatches.isNotEmpty) {
    return ScamWarning(
      level: WarningLevel.caution,
      reasons: [
        'The payment note or recipient contains a phrase often used in scams: '
            '${cautionMatches.join(', ')}.',
      ],
      elapsedMs: 1.8,
    );
  }
  return const ScamWarning(
    level: WarningLevel.none,
    reasons: [],
    elapsedMs: 1.2,
  );
}
