import 'package:flutter_test/flutter_test.dart';
import 'package:scam_guard/scam_guard.dart';
import 'package:credify_frontend/features/scam_guard_partner/demo_scenarios.dart';
import 'package:credify_frontend/features/scam_guard_partner/simulated_scam_guard_api.dart';

void main() {
  group('SimulatedScamGuardApi', () {
    late SimulatedScamGuardApi api;

    setUp(() {
      api = SimulatedScamGuardApi(simulatedLatency: Duration.zero);
    });

    test('scenario responses match the SDK exactly', () async {
      for (final scenario in kDemoScenarios) {
        final requestBody = scenario.toRequestBody();
        final response = await api.check(
          apiKey: kDemoApiKey,
          requestBody: requestBody,
        );
        final hasContext = requestBody.containsKey('is_first_time_payee') ||
            requestBody.containsKey('typical_amount_inr');
        final expected = const ScamGuard().check(
          payeeVpa: scenario.payeeVpa,
          amountInr: scenario.amountInr,
          payeeName: scenario.payeeName,
          note: scenario.note,
          context: hasContext
              ? ScamContext(
                  isFirstTimePayee: scenario.isFirstTimePayee,
                  typicalAmountInr: scenario.typicalAmountInr,
                )
              : null,
        );

        expect(response.statusCode, 200, reason: scenario.id);
        expect(response.body['level'], expected.level.name, reason: scenario.id);
        expect(response.body['score'], expected.score, reason: scenario.id);
        expect(
          (response.body['signals'] as List)
              .map((signal) => signal['code'])
              .toList(),
          expected.signals.map((signal) => signal.code).toList(),
          reason: scenario.id,
        );
        if (scenario.id == 'prize_scam' || scenario.id == 'unusual_amount') {
          // Printed by `flutter test -r expanded` for reporting actual SDK output.
          // ignore: avoid_print
          print(
            '${scenario.id}: level=${response.body['level']}, '
            'score=${response.body['score']}, '
            'signals=${(response.body['signals'] as List).map((signal) => signal['code']).toList()}',
          );
        }
        if (scenario.id == 'prize_scam') {
          expect(response.body['level'], 'high');
          expect(response.body['decision'], 'block');
        }
        if (scenario.id == 'unusual_amount') {
          expect(response.body['level'], 'medium');
          expect(response.body['decision'], 'warn');
        }
      }
    });

    test('KYC scenario warns and normal scenario allows', () async {
      final kyc = await api.check(
        apiKey: kDemoApiKey,
        requestBody: kDemoScenarios.first.toRequestBody(),
      );
      expect(kyc.body['should_warn'], isTrue);

      final normal = await api.check(
        apiKey: kDemoApiKey,
        requestBody: kDemoScenarios.last.toRequestBody(),
      );
      expect(normal.body['level'], 'low');
      expect(normal.body['decision'], 'allow');
    });

    test('invalid API key returns 401 without running a valid response', () async {
      final response = await api.check(
        apiKey: kWrongApiKey,
        requestBody: kDemoScenarios.first.toRequestBody(),
      );
      expect(response.statusCode, 401);
      expect(response.body['error'], 'invalid_api_key');
      expect(response.body, contains('request_id'));
    });

    test('invalid request fields return 422', () async {
      final missingPayee = await api.check(
        apiKey: kDemoApiKey,
        requestBody: {'amount_inr': 10},
      );
      expect(missingPayee.statusCode, 422);
      expect(missingPayee.body['message'], startsWith('payee_vpa:'));

      final zeroAmount = await api.check(
        apiKey: kDemoApiKey,
        requestBody: {'payee_vpa': 'ravi@okaxis', 'amount_inr': 0},
      );
      expect(zeroAmount.statusCode, 422);
      expect(zeroAmount.body['message'], startsWith('amount_inr:'));

      final negativeTypicalAmount = await api.check(
        apiKey: kDemoApiKey,
        requestBody: {
          'payee_vpa': 'ravi@okaxis',
          'amount_inr': 10,
          'typical_amount_inr': -5,
        },
      );
      expect(negativeTypicalAmount.statusCode, 422);
      expect(
        negativeTypicalAmount.body['message'],
        startsWith('typical_amount_inr:'),
      );
    });

    test('request IDs increment across successful and error calls', () async {
      final first = await api.check(
        apiKey: kDemoApiKey,
        requestBody: kDemoScenarios.last.toRequestBody(),
      );
      final second = await api.check(
        apiKey: kWrongApiKey,
        requestBody: kDemoScenarios.last.toRequestBody(),
      );
      final third = await api.check(
        apiKey: kDemoApiKey,
        requestBody: kDemoScenarios.last.toRequestBody(),
      );
      final fourth = await api.check(
        apiKey: kDemoApiKey,
        requestBody: {'amount_inr': 10},
      );

      expect(first.body['request_id'], 'sim_0001');
      expect(second.body['request_id'], 'sim_0002');
      expect(third.body['request_id'], 'sim_0003');
      expect(fourth.body['request_id'], 'sim_0004');
    });

    test('API key masking keeps only the expected prefix and suffix', () {
      expect(maskApiKey(kDemoApiKey), 'mk_test_••••9c');
      expect(maskApiKey('short'), '••••');
    });
  });
}
