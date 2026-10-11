class DemoScenario {
  final String id;
  final String title;
  final String subtitle;
  final String payeeVpa;
  final String payeeName;
  final double amountInr;
  final String note;
  final bool isFirstTimePayee;
  final double? typicalAmountInr;
  final DemoPaymentContext paymentContext;
  final bool isScam;

  const DemoScenario({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.payeeVpa,
    required this.payeeName,
    required this.amountInr,
    required this.note,
    required this.isFirstTimePayee,
    this.typicalAmountInr,
    this.paymentContext = const DemoPaymentContext(),
    required this.isScam,
  });

  Map<String, dynamic> toRequestBody() => {
        'payee_vpa': payeeVpa,
        'payee_name': payeeName,
        'amount_inr': amountInr,
        'note': note,
        'is_first_time_payee': isFirstTimePayee,
        if (typicalAmountInr != null) 'typical_amount_inr': typicalAmountInr,
        'payment_context': paymentContext.toJson(),
      };
}

/// Synthetic context supplied by the host payment app in this simulation.
/// No contact list, message body, PIN, account balance, or real device signal
/// is collected. These parameters do not change the published SDK.
class DemoPaymentContext {
  final int recentPaymentsToPayee10m;
  final int similarPaymentsLastHour;
  final bool beneficiaryDetailsChangedRecently;
  final int recipientRiskReports;
  final bool unexpectedCollectRequest;
  final bool paymentStartedFromExternalLink;
  final bool newDeviceSession;
  final bool recentSimChange;
  final bool activeScreenSharing;

  const DemoPaymentContext({
    this.recentPaymentsToPayee10m = 0,
    this.similarPaymentsLastHour = 0,
    this.beneficiaryDetailsChangedRecently = false,
    this.recipientRiskReports = 0,
    this.unexpectedCollectRequest = false,
    this.paymentStartedFromExternalLink = false,
    this.newDeviceSession = false,
    this.recentSimChange = false,
    this.activeScreenSharing = false,
  });

  Map<String, dynamic> toJson() => {
        'recent_payments_to_payee_10m': recentPaymentsToPayee10m,
        'similar_payments_last_hour': similarPaymentsLastHour,
        'beneficiary_details_changed_recently': beneficiaryDetailsChangedRecently,
        'recipient_risk_reports': recipientRiskReports,
        'unexpected_collect_request': unexpectedCollectRequest,
        'payment_started_from_external_link': paymentStartedFromExternalLink,
        'new_device_session': newDeviceSession,
        'recent_sim_change': recentSimChange,
        'active_screen_sharing': activeScreenSharing,
      };

  List<String> get activeFactors => [
        if (recentPaymentsToPayee10m >= 3)
          '$recentPaymentsToPayee10m payments to this recipient in 10 minutes',
        if (similarPaymentsLastHour >= 3)
          '$similarPaymentsLastHour similar transfers in the last hour',
        if (beneficiaryDetailsChangedRecently)
          'Recipient payment details changed recently',
        if (recipientRiskReports > 0)
          '$recipientRiskReports synthetic recipient risk report(s)',
        if (unexpectedCollectRequest) 'Unexpected payment request',
        if (paymentStartedFromExternalLink)
          'Payment opened from an external link',
        if (newDeviceSession) 'New device or app session',
        if (recentSimChange) 'Recent SIM change reported by the app',
        if (activeScreenSharing) 'Screen sharing is active',
      ];
}

const List<DemoScenario> kDemoScenarios = [
  DemoScenario(
    id: 'kyc_scam',
    title: 'Fake bank KYC',
    subtitle: 'Impersonates a bank, urgent KYC threat',
    payeeVpa: 'sbi-kyc-help@ybl',
    payeeName: 'SBI Support',
    amountInr: 9999,
    note: 'urgent KYC update or account blocked',
    isFirstTimePayee: true,
    isScam: true,
  ),
  DemoScenario(
    id: 'prize_scam',
    title: 'Prize / cashback bait',
    subtitle: 'Payee on the demo warning list',
    payeeVpa: 'fictional-prize-desk@demo',
    payeeName: 'Prize Desk',
    amountInr: 4999,
    note: 'you have won a cashback reward, pay fee to claim',
    isFirstTimePayee: true,
    isScam: true,
  ),
  DemoScenario(
    id: 'unusual_amount',
    title: 'Urgent large payment',
    subtitle: 'New payee, urgent note, far above usual spend',
    payeeVpa: 'meena.traders@okicici',
    payeeName: 'Meena Traders',
    amountInr: 45000,
    note: 'urgent advance, pay today',
    isFirstTimePayee: true,
    typicalAmountInr: 2000,
    isScam: false,
  ),
  DemoScenario(
    id: 'normal',
    title: 'Everyday payment',
    subtitle: 'Known contact, small amount',
    payeeVpa: 'ravi@okaxis',
    payeeName: 'Ravi Kumar',
    amountInr: 200,
    note: 'lunch',
    isFirstTimePayee: false,
    isScam: false,
  ),
];

/// Additional context-focused examples are kept separate from the original
/// SDK-rule scenarios so the published-rule examples remain easy to compare.
const List<DemoScenario> kContextDemoScenarios = [
  DemoScenario(
    id: 'silent_recipient_change',
    title: 'Quiet payee change',
    subtitle: 'Blank note; recipient details changed recently',
    payeeVpa: 'service.update@okaxis',
    payeeName: 'Service Update',
    amountInr: 1250,
    note: '',
    isFirstTimePayee: true,
    paymentContext: DemoPaymentContext(
      beneficiaryDetailsChangedRecently: true,
    ),
    isScam: true,
  ),
  DemoScenario(
    id: 'unexpected_collect_request',
    title: 'Unexpected payment request',
    subtitle: 'Blank note; request arrived through an external link',
    payeeVpa: 'quick.claim@okaxis',
    payeeName: 'Quick Claim',
    amountInr: 2400,
    note: '',
    isFirstTimePayee: false,
    paymentContext: DemoPaymentContext(
      unexpectedCollectRequest: true,
      paymentStartedFromExternalLink: true,
    ),
    isScam: true,
  ),
  DemoScenario(
    id: 'rapid_repeat_transfers',
    title: 'Repeated transfers',
    subtitle: 'Several rapid, similar payments to one recipient',
    payeeVpa: 'parcel.fee@okaxis',
    payeeName: 'Parcel Fee',
    amountInr: 1800,
    note: '',
    isFirstTimePayee: false,
    paymentContext: DemoPaymentContext(
      recentPaymentsToPayee10m: 3,
      similarPaymentsLastHour: 3,
    ),
    isScam: true,
  ),
  DemoScenario(
    id: 'recipient_risk_report',
    title: 'Recipient risk report',
    subtitle: 'Synthetic reports associated with this recipient',
    payeeVpa: 'review.flagged@okaxis',
    payeeName: 'Review Services',
    amountInr: 950,
    note: '',
    isFirstTimePayee: false,
    paymentContext: DemoPaymentContext(recipientRiskReports: 2),
    isScam: true,
  ),
  DemoScenario(
    id: 'device_safety_check',
    title: 'Device safety check',
    subtitle: 'New session while screen sharing is active',
    payeeVpa: 'daily.supply@okaxis',
    payeeName: 'Daily Supply',
    amountInr: 600,
    note: '',
    isFirstTimePayee: false,
    paymentContext: DemoPaymentContext(
      newDeviceSession: true,
      recentSimChange: true,
      activeScreenSharing: true,
    ),
    isScam: true,
  ),
  DemoScenario(
    id: 'new_payee_normal',
    title: 'New payee, routine amount',
    subtitle: 'Blank note; a first payment with no other risk context',
    payeeVpa: 'local.supplier@okaxis',
    payeeName: 'Local Supplier',
    amountInr: 400,
    note: '',
    isFirstTimePayee: true,
    paymentContext: const DemoPaymentContext(),
    isScam: false,
  ),
];

const List<DemoScenario> kAllDemoScenarios = [
  ...kDemoScenarios,
  ...kContextDemoScenarios,
];
