import 'package:scam_guard/scam_guard.dart';

const String kScamGuardEndpoint =
    'https://api.momentum.example/v1/scam-guard/check';
const String kDemoApiKey = 'mk_test_demo_7f3a9c';
const String kWrongApiKey = 'mk_test_wrong_000000';

// Synthetic payment-app context overlay used only by this simulator. The SDK
// package and its 10 published rule weights remain unchanged.
const int _mediumRiskThreshold = 30;
const int _highRiskThreshold = 60;
const int _maximumRiskScore = 100;

List<Map<String, dynamic>> _contextSignals(Map<String, dynamic> context) {
  final signals = <Map<String, dynamic>>[];
  void add(String code, String message, int weight) {
    signals.add({
      'code': code,
      'message': message,
      'weight': weight,
      'source': 'simulated_payment_context',
    });
  }

  final recentPayeePayments = context['recent_payments_to_payee_10m'] as int? ?? 0;
  if (recentPayeePayments >= 3) {
    add(
      'RAPID_PAYEE_PAYMENT_VELOCITY',
      '$recentPayeePayments payments to this recipient in 10 minutes is unusual.',
      20,
    );
  }

  final similarPayments = context['similar_payments_last_hour'] as int? ?? 0;
  if (similarPayments >= 3) {
    add(
      'POSSIBLE_SPLIT_PAYMENT_PATTERN',
      '$similarPayments similar transfers were made in the last hour.',
      20,
    );
  }

  if (context['beneficiary_details_changed_recently'] == true) {
    add(
      'RECENT_BENEFICIARY_CHANGE',
      'The saved payment details for this recipient changed recently.',
      35,
    );
  }

  final reports = context['recipient_risk_reports'] as int? ?? 0;
  if (reports > 0) {
    add(
      'SYNTHETIC_RECIPIENT_RISK_REPORTS',
      'The demo risk feed has $reports report(s) associated with this recipient.',
      45,
    );
  }

  if (context['unexpected_collect_request'] == true) {
    add(
      'UNEXPECTED_PAYMENT_REQUEST',
      'This payment request was marked unexpected by the user or host app.',
      20,
    );
  }

  if (context['payment_started_from_external_link'] == true) {
    add(
      'EXTERNAL_PAYMENT_LINK',
      'The payment was opened from an external link.',
      15,
    );
  }

  if (context['new_device_session'] == true) {
    add(
      'NEW_DEVICE_SESSION',
      'The payment is being made from a new device or app session.',
      10,
    );
  }

  if (context['recent_sim_change'] == true) {
    add(
      'RECENT_SIM_CHANGE',
      'The host app reports a recent SIM change.',
      15,
    );
  }

  if (context['active_screen_sharing'] == true) {
    add(
      'ACTIVE_SCREEN_SHARING',
      'Screen sharing is active during this payment.',
      25,
    );
  }

  return signals;
}

String maskApiKey(String key) {
  if (key.length < 10) return '••••';
  return '${key.substring(0, 8)}••••${key.substring(key.length - 2)}';
}

class SimulatedApiResponse {
  final int statusCode;
  final Map<String, dynamic> body;
  final Duration latency;

  const SimulatedApiResponse({
    required this.statusCode,
    required this.body,
    required this.latency,
  });

  bool get isOk => statusCode == 200;
}

class SimulatedScamGuardApi {
  final Set<String> validKeys;
  final Duration simulatedLatency;
  int _requestCount = 0;

  SimulatedScamGuardApi({
    this.validKeys = const {kDemoApiKey},
    this.simulatedLatency = const Duration(milliseconds: 180),
  });

  Future<SimulatedApiResponse> check({
    required String apiKey,
    required Map<String, dynamic> requestBody,
  }) async {
    final stopwatch = Stopwatch()..start();
    final requestId = 'sim_${(++_requestCount).toString().padLeft(4, '0')}';
    await Future<void>.delayed(simulatedLatency);

    if (!validKeys.contains(apiKey)) {
      return _response(
        stopwatch,
        401,
        requestId,
        'invalid_api_key',
        'Missing or invalid X-API-Key header.',
      );
    }

    final payeeVpa = requestBody['payee_vpa'];
    if (payeeVpa is! String || payeeVpa.trim().isEmpty) {
      return _response(
        stopwatch,
        422,
        requestId,
        'invalid_request',
        'payee_vpa: must be a non-empty string.',
      );
    }

    final amountInr = requestBody['amount_inr'];
    if (amountInr is! num || amountInr <= 0) {
      return _response(
        stopwatch,
        422,
        requestId,
        'invalid_request',
        'amount_inr: must be a number greater than 0.',
      );
    }

    final payeeName = requestBody['payee_name'];
    if (requestBody.containsKey('payee_name') && payeeName is! String) {
      return _response(
        stopwatch,
        422,
        requestId,
        'invalid_request',
        'payee_name: must be a string.',
      );
    }

    final note = requestBody['note'];
    if (requestBody.containsKey('note') && note is! String) {
      return _response(
        stopwatch,
        422,
        requestId,
        'invalid_request',
        'note: must be a string.',
      );
    }

    final isFirstTimePayee = requestBody['is_first_time_payee'];
    if (requestBody.containsKey('is_first_time_payee') &&
        isFirstTimePayee is! bool) {
      return _response(
        stopwatch,
        422,
        requestId,
        'invalid_request',
        'is_first_time_payee: must be a boolean.',
      );
    }

    final typicalAmountInr = requestBody['typical_amount_inr'];
    if (requestBody.containsKey('typical_amount_inr') &&
        (typicalAmountInr is! num || typicalAmountInr <= 0)) {
      return _response(
        stopwatch,
        422,
        requestId,
        'invalid_request',
        'typical_amount_inr: must be a number greater than 0.',
      );
    }

    final rawPaymentContext = requestBody['payment_context'];
    if (requestBody.containsKey('payment_context') &&
        rawPaymentContext is! Map) {
      return _response(
        stopwatch,
        422,
        requestId,
        'invalid_request',
        'payment_context: must be an object.',
      );
    }
    final paymentContext = rawPaymentContext == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(rawPaymentContext as Map);
    for (final field in [
      'recent_payments_to_payee_10m',
      'similar_payments_last_hour',
      'recipient_risk_reports',
    ]) {
      final value = paymentContext[field];
      if (value != null && (value is! int || value < 0 || value > 100000)) {
        return _response(
          stopwatch,
          422,
          requestId,
          'invalid_request',
          'payment_context.$field: must be a non-negative integer.',
        );
      }
    }
    for (final field in [
      'beneficiary_details_changed_recently',
      'unexpected_collect_request',
      'payment_started_from_external_link',
      'new_device_session',
      'recent_sim_change',
      'active_screen_sharing',
    ]) {
      final value = paymentContext[field];
      if (value != null && value is! bool) {
        return _response(
          stopwatch,
          422,
          requestId,
          'invalid_request',
          'payment_context.$field: must be a boolean.',
        );
      }
    }

    final hasContext = requestBody.containsKey('is_first_time_payee') ||
        requestBody.containsKey('typical_amount_inr');
    final result = const ScamGuard().check(
      payeeVpa: payeeVpa,
      amountInr: amountInr.toDouble(),
      payeeName: payeeName as String?,
      note: note as String?,
      context: hasContext
          ? ScamContext(
              isFirstTimePayee: isFirstTimePayee as bool?,
              typicalAmountInr: (typicalAmountInr as num?)?.toDouble(),
            )
          : null,
    );

    final contextSignals = _contextSignals(paymentContext);
    final contextScore = contextSignals.fold<int>(
      0,
      (sum, signal) => sum + (signal['weight'] as int),
    );
    final score = (result.score + contextScore)
        .clamp(0, _maximumRiskScore)
        .toInt();
    final level = score >= _highRiskThreshold
        ? ScamRiskLevel.high
        : score >= _mediumRiskThreshold
            ? ScamRiskLevel.medium
            : ScamRiskLevel.low;
    final levelName = level.name;
    final decision = switch (level) {
      ScamRiskLevel.low => 'allow',
      ScamRiskLevel.medium => 'warn',
      ScamRiskLevel.high => 'block',
    };
    final signals = [
      for (final signal in result.signals)
        {
          'code': signal.code,
          'message': signal.message,
          'weight': signal.weight,
          'source': 'sdk_rule',
        },
      ...contextSignals,
    ];
    final body = <String, dynamic>{
      'request_id': requestId,
      'decision': decision,
      'level': levelName,
      'score': score,
      'sdk_rule_score': result.score,
      'payment_context_score': contextScore,
      'should_warn': level != ScamRiskLevel.low,
      'signals': signals,
      'engine_elapsed_ms': result.elapsed.inMicroseconds / 1000,
      'sdk': 'scam_guard (10 on-device rules)',
      'simulation_note':
          'Payment-context signals and combined score are illustrative simulation logic, not part of the published SDK.',
    };
    stopwatch.stop();
    return SimulatedApiResponse(
      statusCode: 200,
      latency: stopwatch.elapsed,
      body: body,
    );
  }

  SimulatedApiResponse _response(
    Stopwatch stopwatch,
    int statusCode,
    String requestId,
    String error,
    String message,
  ) {
    final body = {
      'request_id': requestId,
      'error': error,
      'message': message,
    };
    stopwatch.stop();
    return SimulatedApiResponse(
      statusCode: statusCode,
      latency: stopwatch.elapsed,
      body: body,
    );
  }
}
