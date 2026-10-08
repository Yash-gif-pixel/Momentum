import 'package:flutter_test/flutter_test.dart';
import 'package:credify_frontend/models/bureau_record.dart';
import 'package:credify_frontend/models/persona_meta.dart';
import 'package:credify_frontend/services/credify_http_service.dart';

/// The bureau lookup is a demo-side simulation. These lock the two properties
/// that make it honest: almost every demo borrower is genuinely invisible to a
/// bureau, and the one who is not has a file that is thin and stale rather
/// than a flattering one.
void main() {
  test('the credit-invisible borrowers have no bureau file', () {
    for (final id in const [
      'lakshmi_vendor_001',
      'thin_file_002',
      'dormancy_gap_003',
      'ramesh_carpentry_004',
      'uniform_trail_007',
    ]) {
      expect(
        BureauRecord.forId(id),
        isNull,
        reason: '$id should have no bureau record',
      );
    }
  });

  test('an unknown profile id has no bureau file', () {
    expect(BureauRecord.forId('not_a_real_profile'), isNull);
  });

  // The live service hardcodes its profile list, so a profile added to the
  // backend is invisible in the UI until it is added here too. That is exactly
  // how meera_tailor_005 was missed once.
  test('every offered profile id has display metadata', () {
    final ids = CredifyHttpService(baseUrl: 'http://localhost:8000')
        .getAvailableProfileIds();

    expect(ids, contains('meera_tailor_005'));
    expect(ids, contains('arjun_kirana_006'));
    expect(ids, contains('uniform_trail_007'));
    expect(ids.length, 7);

    for (final id in ids) {
      final meta = PersonaMeta.forId(id);
      expect(
        meta.name,
        isNot(equals(id)),
        reason: '$id has no PersonaMeta entry and would render its raw id',
      );
    }
  });

  test('the thin-file borrower has a low, stale file', () {
    final r = BureauRecord.forId('meera_tailor_005');
    expect(r, isNotNull);
    // Low enough that a bureau-only policy would decline her, which is the
    // whole point of showing it next to a healthy cash-flow signal.
    expect(r!.score, lessThan(650));
    expect(r.quality, BureauFileQuality.thinAndStale);
    expect(r.scale, '300–900');
    expect(r.vintage.toLowerCase(), contains('months ago'));
    expect(r.summary, isNotEmpty);
  });

  // The inverse demo case: a file a bureau-only policy would approve on,
  // attached to a business whose cashflow is shrinking. If this score ever
  // drifts down the card stops making its point.
  test('the clean-file borrower has a high, current file', () {
    final r = BureauRecord.forId('arjun_kirana_006');
    expect(r, isNotNull);
    expect(r!.score, greaterThan(750));
    expect(r.quality, BureauFileQuality.healthy);
    expect(r.scale, '300–900');
    expect(r.summary, isNotEmpty);
  });
}
