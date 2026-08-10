import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Thin wrapper around the local_auth plugin — biometric (fingerprint/face)
/// or device-credential (PIN/pattern/password) authentication, used to gate
/// the Insights tab when SecuritySettingsProvider.lockEnabled is on.
class BiometricAuthService {
  final LocalAuthentication _auth = LocalAuthentication();

  /// Whether this device can authenticate at all — either biometrics
  /// enrolled, or a plain device PIN/pattern/password set (which
  /// [authenticate]'s biometricOnly: false already accepts as a fallback).
  /// False means turning the Insights lock on would just permanently
  /// strand the user with no way to unlock it, so the Settings toggle
  /// checks this before enabling.
  Future<bool> get isSupported async {
    try {
      return await _auth.isDeviceSupported();
    } on PlatformException {
      return false;
    }
  }

  /// Prompts the system biometric/device-credential UI. Returns false
  /// (rather than throwing) on any failure — cancelled, no biometrics
  /// enrolled, hardware unavailable, lockout — the caller only needs to
  /// know whether it's now unlocked, not why it isn't.
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          // Falls back to device PIN/pattern/password when no biometric is
          // enrolled — Insights would otherwise be permanently inaccessible
          // on a device with a screen lock but no fingerprint/face set up.
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } on PlatformException {
      return false;
    }
  }
}
