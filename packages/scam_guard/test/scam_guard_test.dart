import 'package:scam_guard/scam_guard.dart';
import 'package:test/test.dart';

void main() {
  const guard = ScamGuard();

  ScamCheckResult check(String vpa, {String? name, String? note, ScamContext? context}) => guard.check(
        payeeVpa: vpa,
        amountInr: 500,
        payeeName: name,
        note: note,
        context: context,
      );

  void hasCode(ScamCheckResult result, String code, bool expected) {
    expect(result.signals.any((signal) => signal.code == code), expected);
  }

  group('individual rules', () {
    test('invalid VPA format', () {
      hasCode(check('not-a-vpa'), 'INVALID_VPA_FORMAT', true);
      hasCode(check('ramesh.kirana@okaxis'), 'INVALID_VPA_FORMAT', false);
    });
    test('urgency language', () {
      hasCode(check('shop@okaxis', note: 'Pay abhi, last chance!'), 'URGENCY_LANGUAGE', true);
      hasCode(check('shop@okaxis', note: 'Payment for groceries'), 'URGENCY_LANGUAGE', false);
      hasCode(check('shop@okaxis', note: 'तुरंत भुगतान करें'), 'URGENCY_LANGUAGE', true);
      hasCode(check('shop@okaxis', note: 'किराने का सामान'), 'URGENCY_LANGUAGE', false);
      expect(check('shop@okaxis', note: 'Pay urgently, तुरंत भुगतान करें').signals.where((s) => s.code == 'URGENCY_LANGUAGE').length, 1);
    });
    test('KYC or account block language', () {
      hasCode(check('shop@okaxis', note: 'Your account is blocked; send OTP'), 'KYC_OR_ACCOUNT_BLOCK', true);
      hasCode(check('shop@okaxis', note: 'Thank you for shopping'), 'KYC_OR_ACCOUNT_BLOCK', false);
      hasCode(check('shop@okaxis', note: 'आपका खाता बंद हो जाएगा, ओटीपी भेजें'), 'KYC_OR_ACCOUNT_BLOCK', true);
      hasCode(check('shop@okaxis', note: 'दूध और ब्रेड'), 'KYC_OR_ACCOUNT_BLOCK', false);
      expect(check('shop@okaxis', note: 'Send OTP now; ओटीपी भेजें').signals.where((s) => s.code == 'KYC_OR_ACCOUNT_BLOCK').length, 1);
    });
    test('PAN matches only in identity contexts', () {
      hasCode(check('shop@okaxis', note: 'pan masala and supari'), 'KYC_OR_ACCOUNT_BLOCK', false);
      hasCode(check('shop@okaxis', note: 'paan shop daily stock'), 'KYC_OR_ACCOUNT_BLOCK', false);
      hasCode(check('shop@okaxis', note: 'Update your PAN card today'), 'KYC_OR_ACCOUNT_BLOCK', true);
      hasCode(check('shop@okaxis', note: 'share PAN number for KYC'), 'KYC_OR_ACCOUNT_BLOCK', true);
    });
    test('refund or prize bait', () {
      hasCode(check('shop@okaxis', note: 'You have won cashback'), 'REFUND_OR_PRIZE_BAIT', true);
      hasCode(check('shop@okaxis', note: 'Monthly grocery order'), 'REFUND_OR_PRIZE_BAIT', false);
      hasCode(check('shop@okaxis', note: 'आप जीत गए! इनाम पाने के लिए भुगतान करें'), 'REFUND_OR_PRIZE_BAIT', true);
      hasCode(check('shop@okaxis', note: 'दूध और ब्रेड'), 'REFUND_OR_PRIZE_BAIT', false);
      expect(check('shop@okaxis', note: 'cashback offer, कैशबैक पाएं').signals.where((s) => s.code == 'REFUND_OR_PRIZE_BAIT').length, 1);
    });
    test('brand impersonation VPA', () {
      hasCode(check('paytm.support@okaxis'), 'BRAND_IMPERSONATION_VPA', true);
      hasCode(check('ramesh.kirana@okaxis'), 'BRAND_IMPERSONATION_VPA', false);
    });
    test('high digit handle', () {
      hasCode(check('12345678@okaxis'), 'HIGH_DIGIT_HANDLE', true);
      hasCode(check('ramesh123@okaxis'), 'HIGH_DIGIT_HANDLE', false);
    });
    test('payee name mismatch', () {
      hasCode(check('other.shop@okaxis', name: 'Ramesh Kirana'), 'NAME_VPA_MISMATCH', true);
      hasCode(check('ramesh.kirana@okaxis', name: 'Ramesh Kirana'), 'NAME_VPA_MISMATCH', false);
      hasCode(check('other.shop@okaxis'), 'NAME_VPA_MISMATCH', false);
    });
    test('known synthetic demo VPA', () {
      hasCode(check('fictional-prize-desk@demo'), 'KNOWN_SCAM_VPA', true);
      hasCode(check('shop@okaxis'), 'KNOWN_SCAM_VPA', false);
    });
  });

  group('host-supplied context rules', () {
    test('first-time payee fires only when explicitly true', () {
      hasCode(check('shop@okaxis', context: const ScamContext(isFirstTimePayee: true)), 'FIRST_TIME_PAYEE', true);
      hasCode(check('shop@okaxis', context: const ScamContext(isFirstTimePayee: false)), 'FIRST_TIME_PAYEE', false);
      hasCode(check('shop@okaxis', context: const ScamContext()), 'FIRST_TIME_PAYEE', false);
      hasCode(check('shop@okaxis'), 'FIRST_TIME_PAYEE', false);
    });

    test('far-above-usual amount uses a positive typical amount and inclusive boundary', () {
      hasCode(check('shop@okaxis', context: const ScamContext(typicalAmountInr: 100)), 'AMOUNT_FAR_ABOVE_USUAL', true);
      hasCode(guard.check(payeeVpa: 'shop@okaxis', amountInr: 299.99, context: const ScamContext(typicalAmountInr: 100)),
          'AMOUNT_FAR_ABOVE_USUAL', false);
      hasCode(guard.check(payeeVpa: 'shop@okaxis', amountInr: 300, context: const ScamContext(typicalAmountInr: 100)),
          'AMOUNT_FAR_ABOVE_USUAL', true);
      hasCode(check('shop@okaxis'), 'AMOUNT_FAR_ABOVE_USUAL', false);
      hasCode(check('shop@okaxis', context: const ScamContext()), 'AMOUNT_FAR_ABOVE_USUAL', false);
      hasCode(guard.check(payeeVpa: 'shop@okaxis', amountInr: 500, context: const ScamContext(typicalAmountInr: 0)),
          'AMOUNT_FAR_ABOVE_USUAL', false);
      hasCode(guard.check(payeeVpa: 'shop@okaxis', amountInr: 500, context: const ScamContext(typicalAmountInr: -10)),
          'AMOUNT_FAR_ABOVE_USUAL', false);
    });

    test('context combines with existing evidence but is not enough by itself to warn', () {
      final combined = guard.check(
        payeeVpa: 'paytm.support@okaxis',
        amountInr: 300,
        note: '',
        context: const ScamContext(isFirstTimePayee: true, typicalAmountInr: 100),
      );
      expect(combined.level, ScamRiskLevel.medium);
      expect(combined.score, 55);
      expect(combined.shouldWarn, true);

      final firstTimeOnly = check('shop@okaxis', context: const ScamContext(isFirstTimePayee: true));
      expect(firstTimeOnly.level, ScamRiskLevel.low);
      expect(firstTimeOnly.score, 10);
      expect(firstTimeOnly.shouldWarn, false);
    });
  });

  test('calls without context preserve established scores and signal codes', () {
    final cases = <(String, String?, String?, int, ScamRiskLevel, List<String>)>[
      ('ramesh.kirana@okaxis', 'Ramesh Kirana', 'groceries', 0, ScamRiskLevel.low, []),
      ('not-a-vpa', null, null, 25, ScamRiskLevel.low, ['INVALID_VPA_FORMAT']),
      ('paytm.support@okaxis', null, null, 30, ScamRiskLevel.medium, ['BRAND_IMPERSONATION_VPA']),
      (
        'paytm.support@okaxis',
        'Unknown Merchant',
        'Urgent! You have won a refund; send OTP abhi',
        100,
        ScamRiskLevel.high,
        ['URGENCY_LANGUAGE', 'KYC_OR_ACCOUNT_BLOCK', 'REFUND_OR_PRIZE_BAIT', 'BRAND_IMPERSONATION_VPA', 'NAME_VPA_MISMATCH'],
      ),
    ];
    for (final (vpa, name, note, score, level, codes) in cases) {
      final result = guard.check(payeeVpa: vpa, amountInr: 500, payeeName: name, note: note);
      expect(result.level, level);
      expect(result.score, score);
      expect(result.signals.map((signal) => signal.code).toList(), codes);
    }
  });

  test('clean payment is low with no signals', () {
    final result = check('ramesh.kirana@okaxis', name: 'Ramesh Kirana', note: 'groceries');
    expect(result.level, ScamRiskLevel.low);
    expect(result.score, 0);
    expect(result.signals, isEmpty);
    expect(result.shouldWarn, false);
  });

  test('multi-signal scam is high', () {
    final result = check('paytm.support@okaxis', name: 'Unknown Merchant', note: 'Urgent! You have won a refund; send OTP abhi');
    expect(result.level, ScamRiskLevel.high);
    expect(result.shouldWarn, true);
    expect(result.signals.length, greaterThanOrEqualTo(4));
  });

  test('malformed and extreme inputs never throw', () {
    final cases = <(String, String?)>[
      ('', null),
      ('shop@okaxis', ''),
      ('😀@okaxis', '😀'),
      (List<String>.filled(20000, 'x').join(), List<String>.filled(20000, 'y').join()),
    ];
    for (final (vpa, note) in cases) {
      expect(() => check(vpa, note: note), returnsNormally);
    }
  });

  test('1000 varied checks each complete in under 50ms', () {
    for (var i = 0; i < 1000; i++) {
      final result = check(i.isEven ? 'ramesh.kirana@okaxis' : 'paytm.support@okaxis',
          name: i.isEven ? 'Ramesh Kirana' : 'Someone Else',
          note: i % 3 == 0 ? 'Urgent payment abhi' : 'groceries');
      expect(result.elapsed, lessThan(const Duration(milliseconds: 50)));
    }
  });
}
