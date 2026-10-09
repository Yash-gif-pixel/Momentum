import 'package:flutter/foundation.dart';
import '../models/analyze_response.dart';
import '../services/credify_api_service.dart';

enum LenderStep { idle, bureauChecked, credifying, done }

class AppState extends ChangeNotifier {
  static const consentValidity = Duration(days: 30);

  final CredifyApiService service;

  AppState(this.service);

  // ── Selected profile ─────────────────────────────────────────────────────
  // A borrower has to be SOMEONE before the user picks, or every screen that
  // reads this would need a null branch. So the id is defaulted but
  // [hasPickedProfile] stays false until the user actually chooses, and the
  // consent rail highlights nothing until then -- a pre-lit card reads as
  // "we have already decided for you", which is the opposite of the point.
  String _selectedProfileId = 'lakshmi_vendor_001';
  String get selectedProfileId => _selectedProfileId;

  bool _hasPickedProfile = false;
  bool get hasPickedProfile => _hasPickedProfile;

  List<String> get availableProfileIds => service.getAvailableProfileIds();

  void selectProfile(String id) {
    _selectedProfileId = id;
    _hasPickedProfile = true;
    // Reset flow so the new profile goes through bureau check again
    _lenderStep = LenderStep.idle;
    _analyzeResult = null;
    _analyzeError = null;
    _consentApproved = false;
    _consentGrantedAt = null;
    _consentExpiresAt = null;
    _consentRevokedAt = null;
    _consentReceiptId = null;
    _analysisGeneration++;
    notifyListeners();
  }

  // ── Consent state ─────────────────────────────────────────────────────────
  bool _consentApproved = false;
  bool _consentLoading = false;
  DateTime? _consentGrantedAt;
  DateTime? _consentExpiresAt;
  DateTime? _consentRevokedAt;
  String? _consentReceiptId;
  bool get consentApproved =>
      _consentApproved &&
      _consentExpiresAt != null &&
      DateTime.now().isBefore(_consentExpiresAt!);
  bool get consentExpired =>
      _consentApproved &&
      _consentExpiresAt != null &&
      !DateTime.now().isBefore(_consentExpiresAt!);
  bool get consentLoading => _consentLoading;
  DateTime? get consentGrantedAt => _consentGrantedAt;
  DateTime? get consentExpiresAt => _consentExpiresAt;
  DateTime? get consentRevokedAt => _consentRevokedAt;
  String? get consentReceiptId => _consentReceiptId;
  DateTime? get consentDataPeriodStart {
    final grantedAt = _consentGrantedAt;
    if (grantedAt == null) return null;
    return DateTime(grantedAt.year - 2, grantedAt.month, grantedAt.day);
  }
  DateTime? get consentDataPeriodEnd => _consentGrantedAt;

  Future<void> approveConsent() async {
    _consentLoading = true;
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 1200));
    _consentApproved = true;
    _consentGrantedAt = DateTime.now();
    _consentExpiresAt = _consentGrantedAt!.add(consentValidity);
    _consentRevokedAt = null;
    _consentReceiptId =
        'DEMO-${_consentGrantedAt!.microsecondsSinceEpoch.toRadixString(36).toUpperCase()}';
    _consentLoading = false;
    _lenderStep = LenderStep.idle;
    _analyzeResult = null;
    _analyzeError = null;
    notifyListeners();
  }

  void revokeConsent() {
    _consentApproved = false;
    _consentRevokedAt = DateTime.now();
    _analysisGeneration++;
    _analyzeLoading = false;
    _lenderStep = LenderStep.idle;
    _analyzeResult = null;
    _analyzeError = null;
    notifyListeners();
  }

  // ── Lender screen step machine ─────────────────────────────────────────
  LenderStep _lenderStep = LenderStep.idle;
  LenderStep get lenderStep => _lenderStep;

  void runBureauCheck() {
    _lenderStep = LenderStep.bureauChecked;
    notifyListeners();
  }

  // ── Analyze result ────────────────────────────────────────────────────
  AnalyzeResponse? _analyzeResult;
  bool _analyzeLoading = false;
  String? _analyzeError;

  int _analysisGeneration = 0;
  AnalyzeResponse? get analyzeResult => consentApproved ? _analyzeResult : null;
  bool get analyzeLoading => _analyzeLoading;
  String? get analyzeError => _analyzeError;

  Future<void> runCredifyAnalysis() async {
    if (!consentApproved) return;
    final generation = ++_analysisGeneration;
    final profileId = _selectedProfileId;
    _lenderStep = LenderStep.credifying;
    _analyzeLoading = true;
    _analyzeError = null;
    notifyListeners();

    try {
      final result = await service.analyzeProfile(profileId);
      if (generation == _analysisGeneration && consentApproved) {
        _analyzeResult = result;
        _lenderStep = LenderStep.done;
      }
    } catch (e) {
      if (generation == _analysisGeneration && consentApproved) {
        _analyzeError = e.toString();
        _lenderStep = LenderStep.bureauChecked;
      }
    } finally {
      if (generation == _analysisGeneration) {
        _analyzeLoading = false;
        notifyListeners();
      }
    }
  }

  void resetLenderFlow() {
    _analysisGeneration++;
    _analyzeLoading = false;
    _lenderStep = LenderStep.idle;
    _analyzeResult = null;
    _analyzeError = null;
    notifyListeners();
  }
}
