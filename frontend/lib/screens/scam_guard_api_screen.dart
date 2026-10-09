import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/credify_theme.dart';
import '../widgets/credify_shell_widgets.dart';
import '../widgets/motion/motion.dart';
import 'scam_guard_api/simulated_api.dart';

export 'scam_guard_api/simulated_api.dart';

/// Developer-facing page for the Scam Guard API: what it is, an API key,
/// integration docs, copy-paste snippets and a small Try-it console.
///
/// The hosted API is simulated in the browser ([simulateCheck]); the
/// on-device SDK it calls is the real engine.
class ScamGuardApiScreen extends StatefulWidget {
  /// Simulated network latency; tests pass [Duration.zero].
  final Duration latency;

  const ScamGuardApiScreen({super.key, this.latency = kSimulatedLatency});

  @override
  State<ScamGuardApiScreen> createState() => _ScamGuardApiScreenState();
}

enum _KeyChoice { demo, generated, wrong }

class _ScamGuardApiScreenState extends State<ScamGuardApiScreen> {
  final Set<String> _validKeys = {kDemoApiKey};
  String? _generatedKey;
  Map<String, dynamic>? _example;

  String _sampleId = 'kyc_scam';
  _KeyChoice _keyChoice = _KeyChoice.demo;
  bool _sending = false;
  (int, Map<String, dynamic>, Duration)? _response;
  String? _sendError;

  int _snippetTab = 0;

  @override
  void initState() {
    super.initState();
    _loadExample();
  }

  /// The Response example is a real run of kyc_scam, not hardcoded JSON.
  Future<void> _loadExample() async {
    final (_, body, _) = await simulateCheck(
      apiKey: kDemoApiKey,
      validKeys: {kDemoApiKey},
      body: sampleRequest('kyc_scam').body,
      latency: widget.latency,
    );
    if (mounted) setState(() => _example = body);
  }

  void _generateKey() {
    final rng = math.Random.secure();
    final hex = List.generate(
      12,
      (_) => rng.nextInt(16).toRadixString(16),
    ).join();
    final key = 'mk_test_$hex';
    setState(() {
      _generatedKey = key;
      _validKeys.add(key);
      _keyChoice = _KeyChoice.generated;
    });
  }

  String get _selectedKey => switch (_keyChoice) {
    _KeyChoice.demo => kDemoApiKey,
    _KeyChoice.generated => _generatedKey ?? kDemoApiKey,
    _KeyChoice.wrong => kWrongApiKey,
  };

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      final r = await simulateCheck(
        apiKey: _selectedKey,
        validKeys: _validKeys,
        body: sampleRequest(_sampleId).body,
        latency: widget.latency,
      );
      if (mounted) setState(() => _response = r);
    } catch (e) {
      if (mounted) setState(() => _sendError = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: staggered([
              const PageHeader(
                pillIcon: Icons.shield_outlined,
                eyebrow: 'SCAM GUARD API',
                title: 'One check before\nthe UPI PIN.',
                subtitle:
                    'Any UPI app sends the payment it is about to make. '
                    'Scam Guard answers allow, warn or block — with the '
                    'reasons.',
              ),
              const _Banner(),
              const SizedBox(height: 22),
              _keyCard(context),
              const _HowItWorks(),
              const _EndpointCard(),
              const _RequestTable(),
              _responseCard(context),
              const _DecisionRules(),
              const _SignalTable(),
              const _ErrorsCard(),
              _integrateCard(context),
              _tryItCard(context),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _keyCard(BuildContext context) {
    final t = context.tokens;
    return _Section(
      label: 'Your API key',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _KeyRow(label: 'Demo key', value: kDemoApiKey),
          if (_generatedKey != null) ...[
            const SizedBox(height: 10),
            _KeyRow(label: 'Your test key', value: _generatedKey!),
          ],
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 220,
              child: CredifyButton(
                label: 'Generate test key',
                icon: Icons.key_outlined,
                ghost: true,
                onPressed: _generateKey,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Demo keys only — generated in your browser, not stored. Real '
            'keys would be issued per partner app.',
            style: TextStyle(color: t.textTertiary, fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  Widget _responseCard(BuildContext context) {
    final t = context.tokens;
    return _Section(
      label: 'Response',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _DocTable(
            headers: ['Field', 'Type', 'Meaning'],
            rows: [
              ['request_id', 'string', 'ID for this check'],
              ['decision', 'string', 'allow, warn or block'],
              ['level', 'string', 'low, medium or high'],
              ['score', 'number', 'Risk score (0–100)'],
              ['should_warn', 'boolean', 'True for warn or block'],
              ['signals', 'array', 'Reasons fired: [{code, message, weight}]'],
              ['engine_elapsed_ms', 'number', 'Time the engine took'],
              ['sdk', 'string', 'Engine that answered'],
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Example — the kyc_scam request, run through the engine just now:',
            style: TextStyle(color: t.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 8),
          _example == null
              ? Text(
                  'Running…',
                  style: TextStyle(color: t.textTertiary, fontSize: 13),
                )
              : _CodeBlock(prettyJson(_example)),
        ],
      ),
    );
  }

  Widget _integrateCard(BuildContext context) {
    final snippets = [curlSnippet(), jsSnippet(), kDartSnippet];
    return _Section(
      label: 'Integrate',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 0, label: Text('curl')),
                  ButtonSegment(value: 1, label: Text('JavaScript (fetch)')),
                  ButtonSegment(value: 2, label: Text('Dart (on-device SDK)')),
                ],
                selected: {_snippetTab},
                onSelectionChanged: (s) =>
                    setState(() => _snippetTab = s.first),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _CodeBlock(snippets[_snippetTab]),
        ],
      ),
    );
  }

  Widget _tryItCard(BuildContext context) {
    final t = context.tokens;
    final keyOptions = [
      (_KeyChoice.demo, 'Demo key'),
      if (_generatedKey != null) (_KeyChoice.generated, 'Your generated key'),
      (_KeyChoice.wrong, 'Wrong key'),
    ];
    final response = _response;
    return _Section(
      label: 'Try it',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Request',
            style: TextStyle(color: t.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in kSampleRequests)
                ChoiceChip(
                  label: Text(s.id),
                  selected: _sampleId == s.id,
                  onSelected: _sending
                      ? null
                      : (_) => setState(() => _sampleId = s.id),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'API key',
            style: TextStyle(color: t.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (choice, label) in keyOptions)
                ChoiceChip(
                  label: Text(label),
                  selected: _keyChoice == choice,
                  onSelected: _sending
                      ? null
                      : (_) => setState(() => _keyChoice = choice),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(_selectedKey, style: _mono(t.textTertiary, 12)),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 200,
              child: CredifyButton(
                label: _sending ? 'Sending…' : 'Send request',
                icon: Icons.send_rounded,
                onPressed: _sending ? null : _send,
              ),
            ),
          ),
          if (_sendError != null) ...[
            const SizedBox(height: 12),
            Text(
              'Error: $_sendError',
              style: TextStyle(color: t.negative, fontSize: 13),
            ),
          ],
          if (response != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                // Pulses once for every new response.
                PulseOnce(
                  trigger: response,
                  color: response.$1 == 200 ? t.positive : t.negative,
                  radius: BorderRadius.circular(6),
                  child: StatusBadge(
                    label: 'HTTP ${response.$1}',
                    color: response.$1 == 200 ? t.positive : t.negative,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${response.$3.inMilliseconds} ms',
                  style: TextStyle(color: t.textSecondary, fontSize: 12.5),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _CodeBlock(prettyJson(response.$2)),
          ],
        ],
      ),
    );
  }
}

// ── Pieces ──────────────────────────────────────────────────────────────────

TextStyle _mono(Color color, double size) => TextStyle(
  color: color,
  fontSize: size,
  fontFamily: 'monospace',
  fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
  height: 1.5,
);

void _copy(BuildContext context, String text) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    const SnackBar(content: Text('Copied'), duration: Duration(seconds: 2)),
  );
}

class _Section extends StatelessWidget {
  final String label;
  final Widget child;
  const _Section({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(label),
          GlassCard(child: child),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: t.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: t.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Prototype: the hosted API is simulated in your browser. The '
              'on-device SDK is real. A phone-app simulation is shown '
              'separately.',
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyRow extends StatelessWidget {
  final String label;
  final String value;
  const _KeyRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 6,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(color: t.textSecondary, fontSize: 12.5),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: t.pillFill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: t.hairline),
          ),
          child: SelectableText(value, style: _mono(t.textPrimary, 13.5)),
        ),
        _CopyButton(text: value),
      ],
    );
  }
}

class _CopyButton extends StatelessWidget {
  final String text;
  const _CopyButton({required this.text});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return TextButton.icon(
      onPressed: () => _copy(context, text),
      icon: Icon(Icons.copy_rounded, size: 15, color: t.accentA),
      label: Text('Copy', style: TextStyle(color: t.accentA, fontSize: 12.5)),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  final String code;
  const _CodeBlock(this.code);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: t.pillFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.hairline),
      ),
      child: Stack(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(14, 14, 80, 14),
            child: SelectableText(code, style: _mono(t.textPrimary, 12.5)),
          ),
          Positioned(top: 2, right: 2, child: _CopyButton(text: code)),
        ],
      ),
    );
  }
}

/// A docs table that stacks each row on narrow screens.
class _DocTable extends StatelessWidget {
  final List<String> headers;
  final List<List<String>> rows;
  final List<int>? flex;
  const _DocTable({required this.headers, required this.rows, this.flex});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final f =
        flex ??
        [
          for (var i = 0; i < headers.length; i++)
            i == 0 ? 3 : (i == headers.length - 1 ? 5 : 2),
        ];
    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 560;
        Widget cell(String s, int col, {bool header = false}) => Text(
          s,
          style: col == 0 && !header
              ? _mono(t.textPrimary, 12.5)
              : TextStyle(
                  color: header ? t.textTertiary : t.textSecondary,
                  fontSize: header ? 11 : 13,
                  fontWeight: header ? FontWeight.w700 : FontWeight.w400,
                  letterSpacing: header ? 0.6 : 0,
                  height: 1.4,
                ),
        );
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final r in rows)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: t.hairline)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      cell(r[0], 0),
                      const SizedBox(height: 3),
                      cell(
                        r.sublist(1).where((s) => s.isNotEmpty).join(' · '),
                        1,
                      ),
                    ],
                  ),
                ),
            ],
          );
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  for (var i = 0; i < headers.length; i++)
                    Expanded(
                      flex: f[i],
                      child: cell(headers[i].toUpperCase(), i, header: true),
                    ),
                ],
              ),
            ),
            for (final r in rows)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: t.hairline)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < r.length; i++)
                      Expanded(
                        flex: f[i],
                        child: Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: cell(r[i], i),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  static const _steps = [
    'Your app sends payee UPI ID, name, amount, note — before showing the '
        'PIN screen.',
    'Scam Guard scores it against 10 warning signs in milliseconds.',
    'Your app shows allow / warn / block. The user can still choose — your '
        'app sets the policy.',
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return _Section(
      label: 'How it works',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: t.accentGradient,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _steps[i],
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Text(
            "Send only what's on the payment screen plus two history facts "
            '(first-time payee, usual amount). Never send the UPI PIN, '
            'balance or bank details.',
            style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _EndpointCard extends StatelessWidget {
  const _EndpointCard();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return _Section(
      label: 'Endpoint',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CodeBlock(
            'POST $kScamGuardEndpoint\n'
            'X-API-Key: <your key>\n'
            'Content-Type: application/json',
          ),
          const SizedBox(height: 10),
          Text(
            'Placeholder endpoint for this prototype.',
            style: TextStyle(color: t.textTertiary, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _RequestTable extends StatelessWidget {
  const _RequestTable();

  @override
  Widget build(BuildContext context) {
    return const _Section(
      label: 'Request body',
      child: _DocTable(
        headers: ['Field', 'Type', 'Required', 'Meaning'],
        flex: [3, 2, 2, 4],
        rows: [
          ['payee_vpa', 'string', 'required', 'Payee UPI ID'],
          ['amount_inr', 'number > 0', 'required', 'Payment amount in ₹'],
          ['payee_name', 'string', 'optional', 'Name your app shows'],
          ['note', 'string', 'optional', 'Payment note / remark'],
          [
            'is_first_time_payee',
            'boolean',
            'optional',
            'User has never paid this payee',
          ],
          [
            'typical_amount_inr',
            'number > 0',
            'optional',
            "User's usual payment size",
          ],
        ],
      ),
    );
  }
}

class _DecisionRules extends StatelessWidget {
  const _DecisionRules();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final rules = [
      ('score < $kWarnFromScore', 'low', 'allow', t.positive),
      ('$kWarnFromScore–${kBlockFromScore - 1}', 'medium', 'warn', t.warning),
      ('$kBlockFromScore+', 'high', 'block', t.negative),
    ];
    return _Section(
      label: 'Decision rules',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (range, level, decision, color) in rules)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                children: [
                  SizedBox(
                    width: 90,
                    child: Text(range, style: _mono(t.textPrimary, 13)),
                  ),
                  Text(
                    '→ $level →',
                    style: TextStyle(color: t.textSecondary, fontSize: 13),
                  ),
                  StatusBadge(label: decision, color: color),
                ],
              ),
            ),
          Text(
            'Points add up, capped at 100.',
            style: TextStyle(color: t.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _SignalTable extends StatelessWidget {
  const _SignalTable();

  @override
  Widget build(BuildContext context) {
    return _Section(
      label: 'The 10 warning signs',
      child: _DocTable(
        headers: const ['Code', 'Points', 'Fires when'],
        flex: const [4, 1, 6],
        rows: [
          for (final s in kSignalDocs) [s.code, '${s.points}', s.firesWhen],
        ],
      ),
    );
  }
}

class _ErrorsCard extends StatelessWidget {
  const _ErrorsCard();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return _Section(
      label: 'Errors',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _DocTable(
            headers: ['Status', 'Error', 'Meaning'],
            rows: [
              ['401', 'invalid_api_key', 'Missing or wrong X-API-Key'],
              ['422', 'invalid_request', 'A field is missing or invalid'],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'If Scam Guard errors or times out, continue with your normal '
            'payment flow (fail open) — never block a payment because the '
            'check failed.',
            style: TextStyle(color: t.textPrimary, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }
}
