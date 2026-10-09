import 'dart:convert';

import 'package:scam_guard/scam_guard.dart';

/// The hosted Scam Guard API, simulated in the browser for this prototype.
///
/// Requests are validated like a real endpoint would validate them, then run
/// through the real on-device SDK (package:scam_guard). Nothing leaves the
/// browser. The endpoint uses the reserved `.example` documentation domain.

const kScamGuardEndpoint = 'https://api.momentum.example/v1/scam-guard/check';
const kDemoApiKey = 'mk_test_demo_7f3a9c';
const kWrongApiKey = 'mk_test_wrong_000000';

/// Simulated network latency for [simulateCheck].
const kSimulatedLatency = Duration(milliseconds: 150);

/// One documented warning sign: what the SDK calls it, its points, and when
/// it fires. `scam_guard_api_screen_test.dart` checks these against
/// `packages/scam_guard/lib/src/rules.dart`.
class SignalDoc {
  final String code;
  final int points;
  final String firesWhen;
  const SignalDoc(this.code, this.points, this.firesWhen);
}

const List<SignalDoc> kSignalDocs = [
  SignalDoc('KNOWN_SCAM_VPA', 60,
      'UPI ID is on the warning list (demo list in this prototype)'),
  SignalDoc('BRAND_IMPERSONATION_VPA', 30,
      'UPI ID combines a brand (e.g. sbi, hdfc, paytm, phonepe, gpay, amazon) '
          'with support/kyc/care/refund/official/helpdesk'),
  SignalDoc('KYC_OR_ACCOUNT_BLOCK', 25,
      'Note mentions KYC, account blocked, PAN, Aadhaar or OTP'),
  SignalDoc('INVALID_VPA_FORMAT', 25, "UPI ID doesn't look like name@bank"),
  SignalDoc('URGENCY_LANGUAGE', 20,
      'Note pressures you: urgent, immediately, last chance, jaldi, turant…'),
  SignalDoc('REFUND_OR_PRIZE_BAIT', 20,
      'Note offers a refund, cashback, prize, lottery or reward'),
  SignalDoc('AMOUNT_FAR_ABOVE_USUAL', 15,
      "Amount is at least 3× the user's usual payment"),
  SignalDoc('HIGH_DIGIT_HANDLE', 15,
      'UPI ID is 8+ characters and at least 80% digits'),
  SignalDoc('FIRST_TIME_PAYEE', 10, 'User has never paid this payee'),
  SignalDoc('NAME_VPA_MISMATCH', 10,
      'Shown name has nothing in common with the UPI ID'),
];

/// Decision thresholds and the amount rule, as documented on the page.
const int kWarnFromScore = 30;
const int kBlockFromScore = 60;
const int kAmountMultiple = 3;

/// A named sample request for the docs and the Try-it console.
class SampleRequest {
  final String id;
  final String label;
  final Map<String, dynamic> body;
  const SampleRequest(this.id, this.label, this.body);
}

/// The same four requests the phone-app simulation uses.
const List<SampleRequest> kSampleRequests = [
  SampleRequest('kyc_scam', 'KYC scam', {
    'payee_vpa': 'sbi-kyc-help@ybl',
    'payee_name': 'SBI Support',
    'amount_inr': 9999,
    'note': 'urgent KYC update or account blocked',
    'is_first_time_payee': true,
  }),
  SampleRequest('prize_scam', 'Prize scam', {
    'payee_vpa': 'fictional-prize-desk@demo',
    'payee_name': 'Prize Desk',
    'amount_inr': 4999,
    'note': 'you have won a cashback reward, pay fee to claim',
    'is_first_time_payee': true,
  }),
  SampleRequest('urgent_large', 'Urgent, large amount', {
    'payee_vpa': 'meena.traders@okicici',
    'payee_name': 'Meena Traders',
    'amount_inr': 45000,
    'note': 'urgent advance, pay today',
    'is_first_time_payee': true,
    'typical_amount_inr': 2000,
  }),
  SampleRequest('normal', 'Normal payment', {
    'payee_vpa': 'ravi@okaxis',
    'payee_name': 'Ravi Kumar',
    'amount_inr': 200,
    'note': 'lunch',
    'is_first_time_payee': false,
  }),
];

SampleRequest sampleRequest(String id) =>
    kSampleRequests.firstWhere((s) => s.id == id);

int _requestCounter = 0;

String _decision(ScamRiskLevel level) => switch (level) {
      ScamRiskLevel.low => 'allow',
      ScamRiskLevel.medium => 'warn',
      ScamRiskLevel.high => 'block',
    };

Map<String, dynamic> _invalid(String field, String reason) => {
      'error': 'invalid_request',
      'message': '$field: $reason',
    };

/// Runs one simulated API call: checks the key, validates the body, then
/// calls the real SDK. Returns the HTTP status, the JSON body and the total
/// latency. [latency] defaults to [kSimulatedLatency]; pass
/// [Duration.zero] in tests (no timer is created then).
Future<(int status, Map<String, dynamic> body, Duration latency)>
    simulateCheck({
  required String apiKey,
  required Set<String> validKeys,
  required Map<String, dynamic> body,
  Duration latency = kSimulatedLatency,
}) async {
  final clock = Stopwatch()..start();
  if (latency > Duration.zero) await Future<void>.delayed(latency);

  (int, Map<String, dynamic>, Duration) reply(
          int status, Map<String, dynamic> json) =>
      (status, json, clock.elapsed);

  if (!validKeys.contains(apiKey)) {
    return reply(401, {
      'error': 'invalid_api_key',
      'message': 'Missing or invalid X-API-Key header.',
    });
  }

  final vpa = body['payee_vpa'];
  if (vpa is! String || vpa.trim().isEmpty) {
    return reply(422, _invalid('payee_vpa', 'required, a non-empty string'));
  }
  final amount = body['amount_inr'];
  if (amount is! num || amount <= 0) {
    return reply(422, _invalid('amount_inr', 'required, a number > 0'));
  }
  final typical = body['typical_amount_inr'];
  if (typical != null && (typical is! num || typical <= 0)) {
    return reply(422, _invalid('typical_amount_inr', 'must be a number > 0'));
  }
  final name = body['payee_name'];
  if (name != null && name is! String) {
    return reply(422, _invalid('payee_name', 'must be a string'));
  }
  final note = body['note'];
  if (note != null && note is! String) {
    return reply(422, _invalid('note', 'must be a string'));
  }
  final firstTime = body['is_first_time_payee'];
  if (firstTime != null && firstTime is! bool) {
    return reply(422, _invalid('is_first_time_payee', 'must be a boolean'));
  }

  final result = const ScamGuard().check(
    payeeVpa: vpa,
    amountInr: amount.toDouble(),
    payeeName: name as String?,
    note: note as String?,
    context: ScamContext(
      isFirstTimePayee: firstTime as bool?,
      typicalAmountInr: (typical as num?)?.toDouble(),
    ),
  );

  _requestCounter++;
  return reply(200, {
    'request_id': 'sim_${_requestCounter.toString().padLeft(4, '0')}',
    'decision': _decision(result.level),
    'level': result.level.name,
    'score': result.score,
    'should_warn': result.shouldWarn,
    'signals': [
      for (final s in result.signals)
        {'code': s.code, 'message': s.message, 'weight': s.weight},
    ],
    'engine_elapsed_ms': result.elapsed.inMicroseconds / 1000,
    'sdk': 'scam_guard (on-device rules)',
  });
}

/// Two-space pretty JSON.
String prettyJson(Object? value) =>
    const JsonEncoder.withIndent('  ').convert(value);

/// Code samples for the Integrate tabs.
String curlSnippet() {
  final body = prettyJson(sampleRequest('kyc_scam').body)
      .split('\n')
      .map((l) => '  $l')
      .join('\n')
      .trimLeft();
  return 'curl -X POST $kScamGuardEndpoint \\\n'
      '  -H "X-API-Key: \$MOMENTUM_API_KEY" \\\n'
      '  -H "Content-Type: application/json" \\\n'
      "  -d '$body'";
}

String jsSnippet() {
  final body = prettyJson(sampleRequest('kyc_scam').body)
      .split('\n')
      .map((l) => '  $l')
      .join('\n')
      .trimLeft();
  return 'const res = await fetch("$kScamGuardEndpoint", {\n'
      '  method: "POST",\n'
      '  headers: {\n'
      '    "X-API-Key": process.env.MOMENTUM_API_KEY,\n'
      '    "Content-Type": "application/json",\n'
      '  },\n'
      '  body: JSON.stringify($body),\n'
      '});\n'
      'const result = await res.json();\n'
      'if (result.should_warn) {\n'
      '  // show warning before PIN\n'
      '}';
}

const String kDartSnippet = "import 'package:scam_guard/scam_guard.dart';\n"
    '\n'
    'final result = const ScamGuard().check(\n'
    "  payeeVpa: 'sbi-kyc-help@ybl',\n"
    '  amountInr: 9999,\n'
    "  payeeName: 'SBI Support',\n"
    "  note: 'urgent KYC update or account blocked',\n"
    '  context: const ScamContext(isFirstTimePayee: true),\n'
    ');\n'
    'if (result.shouldWarn) {\n'
    '  /* show warning before PIN */\n'
    '}';
