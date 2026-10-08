// Rule weights and thresholds are heuristic demo defaults, not guarantees.
const int invalidVpaWeight = 25;
const int urgencyLanguageWeight = 20;
const int kycOrAccountBlockWeight = 25;
const int refundOrPrizeBaitWeight = 20;
const int brandImpersonationVpaWeight = 30;
const int highDigitHandleWeight = 15;
const int nameVpaMismatchWeight = 10;
const int knownScamVpaWeight = 60;

// A handle is high-digit when it contains at least 8 characters, at least 80%
// of which are digits. This rule is intentionally simple and deterministic.
const int highDigitMinimumLength = 8;
const double highDigitMinimumRatio = 0.8;
const int mediumRiskThreshold = 30;
const int highRiskThreshold = 60;
const int maximumRiskScore = 100;

// Devanagari terms use substring matching because Dart RegExp's \b boundary
// only recognizes ASCII letters as word characters.
const Set<String> urgencyDevanagariKeywords = {
  'तुरंत', 'जल्दी', 'अभी', 'आखिरी मौका',
};
const Set<String> kycOrAccountBlockDevanagariKeywords = {
  'केवाईसी', 'खाता बंद', 'खाता ब्लॉक', 'आधार', 'ओटीपी', 'पैन कार्ड',
};
const Set<String> refundOrPrizeBaitDevanagariKeywords = {
  'रिफंड', 'कैशबैक', 'लॉटरी', 'इनाम', 'आप जीत गए',
};

const Map<String, String> supportWords = {
  'support': 'support',
  'helpdesk': 'help desk',
  'care': 'care',
  'refund': 'refund',
  'kyc': 'KYC',
  'official': 'official',
};

const Set<String> brandWords = {
  'google', 'paytm', 'phonepe', 'gpay', 'amazon', 'flipkart', 'sbi', 'hdfc',
  'icici', 'axis', 'npci', 'bhim', 'airtel', 'jio',
};
