import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/biometric_auth_service.dart';

/// Gates the Insights tab behind the device's biometric/PIN lock — see
/// InsightsLockGate, which reads [isUnlocked] and calls [authenticate].
///
/// [lockEnabled] is the persisted Settings toggle. [isUnlocked] is a
/// runtime-only session flag (never persisted, starts false on every cold
/// start) that InsightsLockGate resets via [lock] whenever the app
/// backgrounds — so turning the toggle on requires authenticating again
/// every time the app is reopened, not just the first time Insights is
/// visited.
class SecuritySettingsProvider extends ChangeNotifier {
  static const _prefKey = 'lock_insights_enabled';

  final BiometricAuthService _biometrics = BiometricAuthService();

  bool _lockEnabled = false;
  bool get lockEnabled => _lockEnabled;

  bool _isUnlocked = false;
  bool get isUnlocked => _isUnlocked;

  Future<bool> get isBiometricSupported => _biometrics.isSupported;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _lockEnabled = prefs.getBool(_prefKey) ?? false;
    notifyListeners();
  }

  /// Only ever called after the caller (the Settings toggle) has already
  /// confirmed device support and, when turning the lock on, a successful
  /// [authenticate] — so this never needs to force a re-lock itself:
  /// turning it off just clears the gate ([isUnlocked] = true, nothing
  /// left to check), and turning it on leaves whatever [isUnlocked]
  /// already is (true, from that just-completed auth) alone, rather than
  /// immediately demanding a second, redundant prompt.
  Future<void> setLockEnabled(bool enabled) async {
    _lockEnabled = enabled;
    if (!enabled) _isUnlocked = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, enabled);
  }

  Future<bool> authenticate() async {
    final ok = await _biometrics.authenticate('Authenticate to view Insights');
    if (ok) {
      _isUnlocked = true;
      notifyListeners();
    }
    return ok;
  }

  /// Re-locks Insights — called on every app backgrounding (see
  /// InsightsLockGate's WidgetsBindingObserver) regardless of which tab is
  /// currently showing, so switching back to Insights after returning to
  /// the app always requires authenticating again.
  void lock() {
    if (!_lockEnabled || !_isUnlocked) return;
    _isUnlocked = false;
    notifyListeners();
  }
}
