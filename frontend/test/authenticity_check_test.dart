import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:credify_frontend/models/analyze_response.dart';
import 'package:credify_frontend/theme/credify_theme.dart';
import 'package:credify_frontend/widgets/authenticity_card.dart';

/// The backend's contract for this field is deliberate in two ways the UI
/// must not undo: absent means "could not assess" rather than "passed", and
/// the check never influenced the score.
///
/// The flagged branch never occurs for any committed demo profile (the
/// lowest is Arjun at 0.1887 against a 0.08 floor), so clicking through the
/// running app can only ever exercise the quiet state. The rendering tests
/// below drive the card directly for exactly that reason.
void main() {
  Map<String, dynamic> baseJson() => {
        'profile_id': 'p',
        'outcome': 'SCORED',
        'vitality_score': 91.0,
        'band': 'strong_candidate',
        'confidence': 'high',
        'reason_codes': {'strengths': [], 'concerns': []},
        'affordability': {
          'indicative_emi_low': 1.0,
          'indicative_emi_high': 2.0,
          'months_would_cover_emi_of_last_24': 24,
        },
        'monthly_cashflow': [],
        'disclaimer': 'd',
      };

  test('a natural check parses with its observed value and floor', () {
    final json = baseJson()
      ..['authenticity_check'] = {
        'status': 'natural',
        'signal': 'income_coefficient_of_variation',
        'observed': 0.40865922472354477,
        'floor': 0.08,
        'note': 'Month-to-month income variation is within the range real '
            'businesses in this dataset show.',
      };

    final check = AnalyzeResponse.fromJson(json).authenticityCheck;
    expect(check, isNotNull);
    expect(check!.isUnusuallyUniform, isFalse);
    expect(check.observed, closeTo(0.4087, 0.0001));
    expect(check.floor, 0.08);
    expect(check.signal, 'income_coefficient_of_variation');
  });

  test('an unusually_uniform check is recognised', () {
    final json = baseJson()
      ..['authenticity_check'] = {
        'status': 'unusually_uniform',
        'signal': 'income_coefficient_of_variation',
        'observed': 0.001,
        'floor': 0.08,
        'note': 'worth a manual look, not a low score.',
      };

    final check = AnalyzeResponse.fromJson(json).authenticityCheck;
    expect(check!.isUnusuallyUniform, isTrue);
    expect(check.note, contains('manual look'));
  });

  test('a missing check is null, not a synthesised pass', () {
    // "Cannot tell" and "passed" are different answers. If this ever
    // defaulted to a natural AuthenticityCheck, the UI would show a clean
    // bill of health for a profile the backend declined to assess.
    final response = AnalyzeResponse.fromJson(baseJson());
    expect(response.authenticityCheck, isNull);
  });

  test('an older backend without the field still parses', () {
    // The field is optional server-side and was added after this client
    // shipped, so its absence must never throw.
    expect(
      () => AnalyzeResponse.fromJson(jsonDecode(jsonEncode(baseJson()))),
      returnsNormally,
    );
  });

  Widget host(AuthenticityCheck check) => MaterialApp(
        theme: CredifyTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(child: AuthenticityCard(check: check)),
        ),
      );

  AuthenticityCheck check({
    required String status,
    required double observed,
    String note = "This business's income shows less month-to-month variation "
        'than typical for any real trail in this dataset — worth a manual '
        'look, not a low score.',
  }) =>
      AuthenticityCheck(
        status: status,
        signal: 'income_coefficient_of_variation',
        observed: observed,
        floor: 0.08,
        note: note,
      );

  testWidgets('the flagged state shows the backend note and the numbers',
      (tester) async {
    await tester
        .pumpWidget(host(check(status: 'unusually_uniform', observed: 0.001)));

    expect(find.text('UNUSUALLY UNIFORM INCOME PATTERN'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget); // observed, as a percentage
    expect(find.textContaining('floor 8%'), findsOneWidget);
    expect(find.textContaining('worth a manual'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the flagged state says plainly that it did not move the score',
      (tester) async {
    // The feature is only defensible if the UI never lets this read as a
    // penalty. If either of these disappears, it starts to.
    await tester
        .pumpWidget(host(check(status: 'unusually_uniform', observed: 0.02)));
    expect(find.text('NOT A SCORE FACTOR'), findsOneWidget);
    expect(find.textContaining('did not change the score above'), findsOneWidget);
  });

  testWidgets('the flagged state allows that a real business can land here',
      (tester) async {
    await tester
        .pumpWidget(host(check(status: 'unusually_uniform', observed: 0.02)));
    expect(find.textContaining('fixed monthly contract'), findsOneWidget);
  });

  testWidgets('the natural state is one quiet line, not a card', (tester) async {
    await tester.pumpWidget(host(check(status: 'natural', observed: 0.4087)));

    expect(find.textContaining('Data pattern check passed'), findsOneWidget);
    expect(find.textContaining('41%'), findsOneWidget);
    // No alarm language on the path every demo profile actually takes.
    expect(find.text('UNUSUALLY UNIFORM INCOME PATTERN'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('both states render at phone width without overflowing',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester
        .pumpWidget(host(check(status: 'unusually_uniform', observed: 0.001)));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(host(check(status: 'natural', observed: 0.4087)));
    expect(tester.takeException(), isNull);
  });

  test('the field round-trips through toJson', () {
    final json = baseJson()
      ..['authenticity_check'] = {
        'status': 'unusually_uniform',
        'signal': 'income_coefficient_of_variation',
        'observed': 0.02,
        'floor': 0.08,
        'note': 'n',
      };
    final round = AnalyzeResponse.fromJson(
      AnalyzeResponse.fromJson(json).toJson(),
    );
    expect(round.authenticityCheck!.status, 'unusually_uniform');
    expect(round.authenticityCheck!.observed, 0.02);
  });
}
