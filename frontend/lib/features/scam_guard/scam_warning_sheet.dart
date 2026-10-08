import 'package:flutter/material.dart';

import 'scam_warning.dart';

enum ScamWarningAction { cancel, payAnyway }

Future<ScamWarningAction?> showScamWarningSheet(
  BuildContext context,
  ScamWarning warning,
) {
  return showModalBottomSheet<ScamWarningAction>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => ScamWarningSheet(warning: warning),
  );
}

class ScamWarningSheet extends StatelessWidget {
  const ScamWarningSheet({super.key, required this.warning});

  final ScamWarning warning;

  @override
  Widget build(BuildContext context) {
    final isDanger = warning.level == WarningLevel.danger;
    final title = isDanger ? 'This looks like a scam' : 'Be careful';
    final color = isDanger ? Theme.of(context).colorScheme.error : Colors.orange;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          8,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  isDanger ? Icons.gpp_bad_outlined : Icons.warning_amber_rounded,
                  color: color,
                  size: 30,
                  semanticLabel: isDanger ? 'Scam warning' : 'Caution warning',
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title, style: Theme.of(context).textTheme.titleLarge),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...warning.reasons.map(
              (reason) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  '),
                    Expanded(child: Text(reason)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text('Checked on your device in ${warning.elapsedMs.toStringAsFixed(1)} ms'),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: () => Navigator.pop(context, ScamWarningAction.cancel),
              child: const Text('Cancel payment'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => Navigator.pop(context, ScamWarningAction.payAnyway),
              child: const Text('Pay anyway'),
            ),
          ],
        ),
      ),
    );
  }
}
