import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'scam_warning.dart';
import 'scam_warning_sheet.dart';

class PaymentDemoScreen extends StatefulWidget {
  const PaymentDemoScreen({super.key, required this.checker});

  final ScamChecker checker;

  @override
  State<PaymentDemoScreen> createState() => _PaymentDemoScreenState();
}

class _PaymentDemoScreenState extends State<PaymentDemoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _vpaController = TextEditingController();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _pinController = TextEditingController();
  bool _showPin = false;
  bool _complete = false;

  @override
  void dispose() {
    _vpaController.dispose();
    _nameController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  void _fillPreset({
    required String vpa,
    required String name,
    required String amount,
    required String note,
  }) {
    _vpaController.text = vpa;
    _nameController.text = name;
    _amountController.text = amount;
    _noteController.text = note;
  }

  Future<void> _proceed() async {
    if (!_formKey.currentState!.validate()) return;
    final warning = widget.checker(
      payeeVpa: _vpaController.text.trim(),
      amountInr: double.parse(_amountController.text.trim()),
      payeeName: _nameController.text.trim(),
      note: _noteController.text.trim(),
    );
    if (warning.level == WarningLevel.none) {
      setState(() => _showPin = true);
      return;
    }
    final action = await showScamWarningSheet(context, warning);
    if (!mounted) return;
    if (action == ScamWarningAction.payAnyway) {
      setState(() => _showPin = true);
    }
  }

  void _onPinChanged(String value) {
    if (value.length == 4) setState(() => _complete = true);
  }

  void _reset() {
    setState(() {
      _showPin = false;
      _complete = false;
      _pinController.clear();
      _vpaController.clear();
      _nameController.clear();
      _amountController.clear();
      _noteController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scam Guard demo')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _complete
                ? _successView()
                : _showPin
                    ? _pinView()
                    : _formView(),
          ),
        ),
      ),
    );
  }

  Widget _formView() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Send money', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('Choose a sample or enter fictional payment details.'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                label: const Text('Local shop'),
                onPressed: () => _fillPreset(
                  vpa: 'corner.shop@example',
                  name: 'Corner Shop',
                  amount: '240',
                  note: 'Groceries',
                ),
              ),
              ActionChip(
                label: const Text('KYC scam'),
                onPressed: () => _fillPreset(
                  vpa: 'demo.kyc@example',
                  name: 'Demo KYC Desk',
                  amount: '1',
                  note: 'Urgent KYC update',
                ),
              ),
              ActionChip(
                label: const Text('Refund scam'),
                onPressed: () => _fillPreset(
                  vpa: 'demo.refund@example',
                  name: 'Demo Refund Desk',
                  amount: '99',
                  note: 'Refund processing fee',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          TextFormField(
            key: const Key('payee-vpa'),
            controller: _vpaController,
            decoration: const InputDecoration(labelText: 'Payee UPI ID (VPA)'),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Enter a payee UPI ID'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('payee-name'),
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Payee name'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('amount'),
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount (₹)'),
            validator: (value) {
              final amount = double.tryParse(value?.trim() ?? '');
              if (amount == null || amount <= 0) return 'Enter an amount above ₹0';
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('note'),
            controller: _noteController,
            decoration: const InputDecoration(labelText: 'Note'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('proceed'),
            onPressed: _proceed,
            child: const Text('Proceed to pay'),
          ),
        ],
      ),
    );
  }

  Widget _pinView() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        MaterialBanner(
          content: const Text('Demo only: no real payment is made.'),
          leading: const Icon(Icons.info_outline),
          actions: const [SizedBox.shrink()],
        ),
        const SizedBox(height: 28),
        Text('Enter your UPI PIN', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text('Paying ${_amountController.text} to ${_nameController.text.isEmpty ? _vpaController.text : _nameController.text}'),
        const SizedBox(height: 20),
        TextField(
          key: const Key('pin'),
          controller: _pinController,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
          onChanged: _onPinChanged,
          decoration: const InputDecoration(
            labelText: '4-digit demo PIN',
            hintText: '••••',
          ),
        ),
      ],
    );
  }

  Widget _successView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
            const SizedBox(height: 16),
            Text('Demo payment complete', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('No money was sent.'),
            const SizedBox(height: 24),
            FilledButton(onPressed: _reset, child: const Text('New payment')),
          ],
        ),
      ),
    );
  }
}
