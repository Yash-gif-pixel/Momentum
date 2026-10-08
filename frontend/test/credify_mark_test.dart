import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:credify_frontend/theme/credify_theme.dart';
import 'package:credify_frontend/widgets/credify_mark.dart';

void main() {
  Widget host(double size, {Color? color}) => MaterialApp(
        theme: CredifyTheme.dark,
        home: Scaffold(
          body: Center(
            child: color == null
                ? CredifyMark(size: size)
                : CredifyMark(size: size, color: color),
          ),
        ),
      );

  testWidgets('it paints at the nav-bar size without throwing', (tester) async {
    // 32x32 is the real constraint from the brand spec; the glyph sits inside
    // a slightly smaller box within it.
    await tester.pumpWidget(host(21));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(CredifyMark)), const Size(21, 21));
  });

  testWidgets('it scales without throwing', (tester) async {
    for (final size in [12.0, 17.0, 21.0, 64.0, 256.0]) {
      await tester.pumpWidget(host(size));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'failed at ${size}px');
      expect(tester.getSize(find.byType(CredifyMark)), Size(size, size));
    }
  });

  testWidgets('it is square regardless of the surrounding box',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: CredifyTheme.dark,
        home: const Scaffold(
          body: SizedBox(
            width: 300,
            height: 40,
            child: Center(child: CredifyMark(size: 24)),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.getSize(find.byType(CredifyMark)), const Size(24, 24));
    expect(tester.takeException(), isNull);
  });

  test('the icons and the in-app mark share one geometry', () {
    // tools/mark.py renders the browser icons and credify_mark.dart paints the
    // in-app one; neither can generate the other, so the numbers are duplicated
    // by hand. This fails if they drift.
    final dart = File('lib/widgets/credify_mark.dart').readAsStringSync();
    final python = File('../tools/mark.py').readAsStringSync();

    for (final value in [
      '0.615', // baseline
      '0.745', // dashed line
      '0.165', // left edge
      '0.835', // right edge
      '0.052', // dash stroke weight
    ]) {
      expect(dart, contains(value),
          reason: 'credify_mark.dart lost the constant $value');
      expect(python, contains(value),
          reason: 'tools/mark.py disagrees with credify_mark.dart on $value');
    }
  });

  test('the icons the manifest promises actually exist', () {
    for (final name in [
      'web/favicon.png',
      'web/icons/Icon-192.png',
      'web/icons/Icon-512.png',
      'web/icons/Icon-maskable-192.png',
      'web/icons/Icon-maskable-512.png',
    ]) {
      final file = File(name);
      expect(file.existsSync(), isTrue, reason: '$name is missing');
      expect(file.lengthSync(), greaterThan(200), reason: '$name looks empty');
    }
  });

  test('no Flutter template placeholders are left in the web shell', () {
    // These shipped as "credify_frontend" and "A new Flutter project" — the
    // tab title and the install prompt are the first things a judge sees.
    final index = File('web/index.html').readAsStringSync();
    final manifest = File('web/manifest.json').readAsStringSync();

    for (final source in [index, manifest]) {
      expect(source, isNot(contains('A new Flutter project')));
      expect(source, isNot(contains('credify_frontend')));
      expect(source, isNot(contains('0175C2'))); // Flutter's default blue
    }
    expect(index, contains('<title>Credify'));
    expect(manifest, contains('"short_name": "Credify"'));
  });

  test('the old Clover leaf icon is gone from the shell', () {
    // The project was renamed from Clover; eco_rounded was the leftover leaf.
    for (final name in ['lib/main.dart', 'lib/screens/landing_screen.dart']) {
      expect(
        File(name).readAsStringSync(),
        isNot(contains('eco_rounded')),
        reason: '$name still shows the old Clover leaf',
      );
    }
  });
}
