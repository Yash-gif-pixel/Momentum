import 'package:scam_guard/scam_guard.dart';
import 'package:test/test.dart';

void main() {
  const guard = ScamGuard();

  ScamCheckResult check(String vpa, {String? name, String? note}) => guard.check(
        payeeVpa: vpa,
        amountInr: 500,
        payeeName: name,
        note: note,
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
    });
    test('KYC or account block language', () {
      hasCode(check('shop@okaxis', note: 'Your account is blocked; send OTP'), 'KYC_OR_ACCOUNT_BLOCK', true);
      hasCode(check('shop@okaxis', note: 'Thank you for shopping'), 'KYC_OR_ACCOUNT_BLOCK', false);
    });
    test('refund or prize bait', () {
      hasCode(check('shop@okaxis', note: 'You have won cashback'), 'REFUND_OR_PRIZE_BAIT', true);
      hasCode(check('shop@okaxis', note: 'Monthly grocery order'), 'REFUND_OR_PRIZE_BAIT', false);
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
