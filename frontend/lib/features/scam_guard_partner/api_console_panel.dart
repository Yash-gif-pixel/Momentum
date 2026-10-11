import 'dart:convert';

import 'package:flutter/material.dart';

import 'simulated_scam_guard_api.dart';

class ApiConsolePanel extends StatefulWidget {
  final bool guardEnabled;
  final bool wrongApiKey;
  final ValueChanged<bool> onWrongApiKeyChanged;
  final Map<String, dynamic>? requestBody;
  final String? usedApiKey;
  final SimulatedApiResponse? response;

  const ApiConsolePanel({
    super.key,
    required this.guardEnabled,
    required this.wrongApiKey,
    required this.onWrongApiKeyChanged,
    required this.requestBody,
    required this.usedApiKey,
    required this.response,
  });

  @override
  State<ApiConsolePanel> createState() => _ApiConsolePanelState();
}

class _ApiConsolePanelState extends State<ApiConsolePanel> {
  bool _expanded = false;
  int _selectedExample = 0;

  static const _ink = Color(0xFF252A33);
  static const _muted = Color(0xFF747B87);
  static const _accent = Color(0xFF4657A8);
  static const _panel = Color(0xFFF5F6F8);

  static const _examples = [
    '''curl -X POST https://api.momentum.example/v1/scam-guard/check \\
  -H "Content-Type: application/json" \\
  -H "X-API-Key: YOUR_DEMO_KEY" \\
  -d '{"payee_vpa":"ravi@okaxis","amount_inr":200}' ''',
    '''const response = await fetch(
  'https://api.momentum.example/v1/scam-guard/check',
  {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-API-Key': 'YOUR_DEMO_KEY',
    },
    body: JSON.stringify({ payee_vpa: 'ravi@okaxis', amount_inr: 200 }),
  },
);''',
    '''final result = const ScamGuard().check(
  payeeVpa: 'ravi@okaxis',
  amountInr: 200,
);''',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE9EBEF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.terminal_rounded, color: _accent, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Under the hood — API call',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          if (!widget.guardEnabled)
            _messageBox('No check is made — the payment goes straight to the UPI PIN.')
          else ...[
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Simulate wrong API key',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _ink),
                  ),
                ),
                Switch.adaptive(
                  key: const ValueKey('wrong-api-key-switch'),
                  value: widget.wrongApiKey,
                  activeTrackColor: const Color(0xFF5264B6),
                  onChanged: widget.onWrongApiKeyChanged,
                ),
              ],
            ),
            Text(
              widget.wrongApiKey ? 'The next call will return 401.' : 'Uses the demo key on the next call.',
              style: const TextStyle(color: _muted, fontSize: 10),
            ),
            const SizedBox(height: 12),
            if (widget.response == null || widget.requestBody == null)
              _messageBox('Tap Pay with Scam Guard on to see the request.')
            else
              _requestDetails(),
          ],
          const SizedBox(height: 16),
          Container(height: 1, color: const Color(0xFFE9EBEF)),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: const ValueKey('integrate-expansion'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              initiallyExpanded: _expanded,
              onExpansionChanged: (value) => setState(() => _expanded = value),
              title: const Text('Integrate in 5 lines', style: TextStyle(color: _ink, fontWeight: FontWeight.w700, fontSize: 13)),
              children: [
                Wrap(
                  spacing: 7,
                  children: [
                    _exampleTab('curl', 0),
                    _exampleTab('JavaScript', 1),
                    _exampleTab('Dart', 2),
                  ],
                ),
                const SizedBox(height: 9),
                _codeBox(_examples[_selectedExample], maxHeight: 205),
                const SizedBox(height: 8),
                const Text(
                  'Illustrative — the endpoint is a placeholder for this simulation.',
                  style: TextStyle(fontSize: 10, color: _muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _requestDetails() {
    final response = widget.response!;
    final requestBody = widget.requestBody!;
    final key = widget.usedApiKey ?? kDemoApiKey;
    final statusColor = response.isOk ? const Color(0xFF288253) : const Color(0xFFB62F3B);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
          'POST $kScamGuardEndpoint',
          style: const TextStyle(color: _ink, fontWeight: FontWeight.w700, fontSize: 11),
        ),
        const SizedBox(height: 7),
        _codeBox(
          'Content-Type: application/json\nX-API-Key: ${maskApiKey(key)}',
          maxHeight: 58,
        ),
        const SizedBox(height: 9),
        const Text('REQUEST BODY', style: TextStyle(color: _muted, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.7)),
        const SizedBox(height: 5),
        _codeBox(_pretty(requestBody), maxHeight: 190),
        const SizedBox(height: 10),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(9)),
              child: Text('${response.statusCode}', style: TextStyle(color: statusColor, fontWeight: FontWeight.w800, fontSize: 12)),
            ),
            const SizedBox(width: 9),
            Text('${response.latency.inMicroseconds / 1000.0} ms', style: const TextStyle(color: _muted, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 7),
        const Text('RESPONSE', style: TextStyle(color: _muted, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.7)),
        const SizedBox(height: 5),
        _codeBox(_pretty(response.body), maxHeight: 240),
        const SizedBox(height: 8),
        const Text(
          'Signals identify their source: the 10-rule SDK or the separate '
          'synthetic payment-context layer. Context weights are demo-only and '
          'are not part of the published SDK.',
          style: TextStyle(color: _muted, fontSize: 10, height: 1.4),
        ),
      ],
    );
  }

  String _pretty(Map<String, dynamic> value) => const JsonEncoder.withIndent('  ').convert(value);

  Widget _codeBox(String code, {required double maxHeight}) => Container(
        width: double.infinity,
        constraints: BoxConstraints(maxHeight: maxHeight),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(12)),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: SelectableText(
              code,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Color(0xFF3C424D), height: 1.4),
            ),
          ),
        ),
      );

  Widget _messageBox(String message) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(13)),
        child: Text(message, style: const TextStyle(color: _muted, fontSize: 11, height: 1.45)),
      );

  Widget _exampleTab(String label, int index) {
    final selected = _selectedExample == index;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _selectedExample = index),
      labelStyle: TextStyle(fontSize: 10, color: selected ? Colors.white : _ink),
      selectedColor: _accent,
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: selected ? _accent : const Color(0xFFE2E4E9)),
    );
  }
}
