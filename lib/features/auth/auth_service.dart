import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AuthStatus {
  uninitialized, // First run, no passcode set
  locked,        // Passcode set, but not logged in
  authenticated, // Successfully logged in
}

class AuthState {
  final AuthStatus status;
  final bool isBiometricsAvailable;
  final bool isBiometricsEnabled;
  final String? errorMessage;

  AuthState({
    required this.status,
    required this.isBiometricsAvailable,
    required this.isBiometricsEnabled,
    this.errorMessage,
  });

  AuthState copyWith({
    AuthStatus? status,
    bool? isBiometricsAvailable,
    bool? isBiometricsEnabled,
    String? errorMessage,
  }) {
    return AuthState(
      status: status ?? this.status,
      isBiometricsAvailable: isBiometricsAvailable ?? this.isBiometricsAvailable,
      isBiometricsEnabled: isBiometricsEnabled ?? this.isBiometricsEnabled,
      errorMessage: errorMessage,
    );
  }
}

class AuthService extends Notifier<AuthState> {
  final _storage = const FlutterSecureStorage();
  final _localAuth = LocalAuthentication();

  static const _pinHashKey = 'nwt_pin_hash';
  static const _pinSaltKey = 'nwt_pin_salt';
  static const _biometricsEnabledKey = 'nwt_biometrics_enabled';

  @override
  AuthState build() {
    // Asynchronously initialize settings on first run
    Future.microtask(() => _init());

    return AuthState(
      status: AuthStatus.locked,
      isBiometricsAvailable: false,
      isBiometricsEnabled: false,
    );
  }

  Future<void> _init() async {
    try {
      final hasPin = await _storage.containsKey(key: _pinHashKey);
      final biometricsAvailable = await _localAuth.canCheckBiometrics && await _localAuth.isDeviceSupported();
      final bioEnabledStr = await _storage.read(key: _biometricsEnabledKey);
      final isBioEnabled = bioEnabledStr == 'true';

      state = AuthState(
        status: hasPin ? AuthStatus.locked : AuthStatus.uninitialized,
        isBiometricsAvailable: biometricsAvailable,
        isBiometricsEnabled: isBioEnabled,
      );

      // Proactively trigger biometrics if enabled and app is locked
      if (hasPin && isBioEnabled && biometricsAvailable) {
        await authenticateWithBiometrics();
      }
    } catch (e) {
      state = state.copyWith(errorMessage: 'Initialization failed: $e');
    }
  }

  // Generate random salt
  String _generateSalt() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    return base64Url.encode(values);
  }

  // Hash PIN using SHA-256
  String _hashPin(String pin, String salt) {
    final bytes = utf8.encode(pin + salt);
    return sha256.convert(bytes).toString();
  }

  /// Registers a new PIN and configures biometrics setting
  Future<bool> registerPasscode(String pin, bool enableBiometrics) async {
    try {
      if (pin.length < 4) {
        state = state.copyWith(errorMessage: 'Passcode must be at least 4 digits.');
        return false;
      }

      final salt = _generateSalt();
      final hash = _hashPin(pin, salt);

      await _storage.write(key: _pinHashKey, value: hash);
      await _storage.write(key: _pinSaltKey, value: salt);
      await _storage.write(key: _biometricsEnabledKey, value: enableBiometrics ? 'true' : 'false');

      state = state.copyWith(
        status: AuthStatus.authenticated,
        isBiometricsEnabled: enableBiometrics,
        errorMessage: null,
      );
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to set passcode: $e');
      return false;
    }
  }

  /// Verifies entered PIN against stored hash
  Future<bool> verifyPasscode(String pin) async {
    try {
      final storedHash = await _storage.read(key: _pinHashKey);
      final salt = await _storage.read(key: _pinSaltKey);

      if (storedHash == null || salt == null) {
        state = state.copyWith(status: AuthStatus.uninitialized);
        return false;
      }

      final computedHash = _hashPin(pin, salt);
      if (computedHash == storedHash) {
        state = state.copyWith(status: AuthStatus.authenticated, errorMessage: null);
        return true;
      } else {
        state = state.copyWith(errorMessage: 'Invalid passcode.');
        return false;
      }
    } catch (e) {
      state = state.copyWith(errorMessage: 'Verification error: $e');
      return false;
    }
  }

  /// Authenticate using native Biometrics (Face ID/Touch ID)
  Future<bool> authenticateWithBiometrics() async {
    if (!state.isBiometricsAvailable || !state.isBiometricsEnabled) return false;

    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Authenticate to unlock Net Worth Tracker',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );

      if (authenticated) {
        state = state.copyWith(status: AuthStatus.authenticated, errorMessage: null);
        return true;
      }
      return false;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Biometric authentication error: $e');
      return false;
    }
  }

  /// Log out (lock the app)
  void lock() {
    state = state.copyWith(status: AuthStatus.locked);
    // Try to trigger biometrics right away on lock for easy re-entry
    if (state.isBiometricsEnabled && state.isBiometricsAvailable) {
      authenticateWithBiometrics();
    }
  }

  /// Clear all stored credentials (for testing or reset)
  Future<void> resetCredentials() async {
    await _storage.delete(key: _pinHashKey);
    await _storage.delete(key: _pinSaltKey);
    await _storage.delete(key: _biometricsEnabledKey);
    state = state.copyWith(
      status: AuthStatus.uninitialized,
      isBiometricsEnabled: false,
    );
  }
}

final authServiceProvider = NotifierProvider<AuthService, AuthState>(AuthService.new);
