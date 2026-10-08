import 'package:flutter/material.dart';

import '../../theme/credify_theme.dart';
import 'payment_demo_screen.dart';
import 'scam_guard_adapter.dart';

void main() {
  runApp(const ScamGuardPreviewApp());
}

class ScamGuardPreviewApp extends StatelessWidget {
  const ScamGuardPreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Scam Guard demo',
      debugShowCheckedModeBanner: false,
      theme: CredifyTheme.light,
      darkTheme: CredifyTheme.dark,
      home: PaymentDemoScreen(checker: scamGuardChecker),
    );
  }
}
