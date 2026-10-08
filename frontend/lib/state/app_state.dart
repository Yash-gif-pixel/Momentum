import 'package:flutter/foundation.dart';
import '../models/analyze_response.dart';
import '../services/credify_api_service.dart';

enum LenderStep { idle, bureauChecked, credifying, done }

class AppState extends ChangeNotifier {
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
    notifyListeners();
  }

  // ── Consent state ─────────────────────────────────────────────────────────
  bool _consentApproved = false;
  bool _consentLoading = false;
  bool get consentApproved => _consentApproved;
  bool get consentLoading => _consentLoading;

  Future<void> approveConsent() async {
    _consentLoading = true;
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 1200));
    _consentApproved = true;
    _consentLoading = false;
    _lenderStep = LenderStep.idle;
    _analyzeResult = null;
    _analyzeError = null;
    notifyListeners();
  }

  void revokeConsent() {
    _consentApproved = false;
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

  AnalyzeResponse? get analyzeResult => _analyzeResult;
  bool get analyzeLoading => _analyzeLoading;
  String? get analyzeError => _analyzeError;

  Future<void> runCredifyAnalysis() async {
    _lenderStep = LenderStep.credifying;
    _analyzeLoading = true;
    _analyzeError = null;
    notifyListeners();

    try {
      final result = await service.analyzeProfile(_selectedProfileId);
      _analyzeResult = result;
      _lenderStep = LenderStep.done;
    } catch (e) {
      _analyzeError = e.toString();
      _lenderStep = LenderStep.bureauChecked;
    } finally {
      _analyzeLoading = false;
      notifyListeners();
    }
  }

  void resetLenderFlow() {
    _lenderStep = LenderStep.idle;
    _analyzeResult = null;
    _analyzeError = null;
    notifyListeners();
  }
}
