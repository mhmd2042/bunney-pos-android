/// domain/activation.dart — the one-time activation gate.
///
/// The spec asks for a screen that appears the first time the app is opened
/// after installation and never again: a café hands the tablet to a cashier, and
/// the app must not be usable if someone copies the APK onto their own device.
///
/// HOW IT WORKS
///   A single activation code is checked once. On success a marker is written to
///   the Android Keystore (through flutter_secure_storage) — not to
///   SharedPreferences, which is plain XML and trivially edited on a rooted
///   device. Every later launch reads that marker and skips the screen.
///
/// HONEST SCOPE — this is a speed bump, not DRM. The code ships inside the APK,
/// so anyone who unpacks it can find it, and anyone who patches the Dart code
/// can skip the check. What it does stop is the realistic case: a casual copy of
/// the installer onto another device. Making it stronger would need a server to
/// verify against, which the spec forbids ("100% offline, no external server").
/// The code is therefore stored as a salted hash rather than a literal, so it is
/// not readable by simply running `strings` on the APK.
library;

import 'dart:math';

import 'user.dart' show hashPin, verifyPin;

/// Where the "already activated" marker lives in secure storage.
const String activationFlagKey = 'bunney_activated_v1';

/// Where the activation code hash lives. The salt is a build constant: it stops
/// the code being found by `strings`, and a per-device salt would not help
/// because the check must work before any device state exists.
const String _codeSalt = 'bunney-pos-android-activation-v1';

/// The activation code, stored as a hash.
///
/// The plain value is NOT in this file. To change the code, put your new code in
/// the list at the top of `tools/set_activation_code.dart`, run
/// `flutter test tools/set_activation_code.dart`, and paste the printed hash
/// here. The README documents the operator-facing side.
const String _codeHash = 'bdbc1380b4a53eed1fc4935daf4754b5cb2e214dfe84ba4a410991c3f967c104';

/// The default hash, exposed so the gate can be constructed without repeating
/// the literal.
const String defaultActivationHash = _codeHash;

/// How many wrong codes before the gate slows down. Not a lockout — a café
/// operator who mistypes must not be locked out of their own till — but enough
/// to make guessing 10,000 codes impractical.
const int maxActivationAttemptsBeforeDelay = 3;

/// Seconds to wait after the third and each later wrong code.
const int activationDelaySeconds = 10;

/// The outcome of an activation attempt.
class ActivationResult {
  const ActivationResult({
    required this.success,
    this.message = '',
    this.delaySeconds = 0,
  });

  final bool success;
  final String message;

  /// How long to disable the button, after repeated failures.
  final int delaySeconds;

  bool get failed => !success;
  bool get isDelayed => delaySeconds > 0;
}

/// Pure activation logic, with the storage injected so it can be tested without
/// a device.
///
/// The two side effects — read/write the activated flag — are callbacks rather
/// than a direct dependency on flutter_secure_storage, which needs the Android
/// Keystore and therefore cannot run in a plain test.
class ActivationGate {
  /// The callbacks are named for what they do; the fields carry the same names
  /// so an initializing formal can be used and the intent stays obvious.
  ActivationGate({
    required this.readActivated,
    required this.writeActivated,
    String? codeHash,
  }) : _codeHash = codeHash ?? defaultActivationHash;

  final Future<bool> Function() readActivated;
  final Future<void> Function(bool) writeActivated;
  final String _codeHash;

  int _failures = 0;

  /// Whether the app has already been activated on this device.
  Future<bool> isActivated() => readActivated();

  /// Check a code and, on success, persist the marker.
  Future<ActivationResult> submit(String code) async {
    final cleaned = code.trim();
    if (cleaned.isEmpty) {
      return const ActivationResult(
          success: false, message: 'أدخل رمز التفعيل');
    }

    final candidate = _hashCode(cleaned);
    if (_constantTimeEquals(candidate, _codeHash)) {
      await writeActivated(true);
      _failures = 0;
      return const ActivationResult(success: true);
    }

    _failures++;
    if (_failures >= maxActivationAttemptsBeforeDelay) {
      return ActivationResult(
        success: false,
        message: 'رمز غير صحيح. حاول بعد $activationDelaySeconds ثانية.',
        delaySeconds: activationDelaySeconds,
      );
    }
    return const ActivationResult(success: false, message: 'رمز التفعيل غير صحيح');
  }

  /// How many wrong codes so far this run.
  int get failures => _failures;

  String _hashCode(String code) {
    // Reuses the PIN hasher: same salted-iterated construction, so there is one
    // implementation of it in the project rather than two that can drift.
    return hashPin(code, _codeSalt);
  }

  /// Compare without leaking the position of the first difference.
  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

/// Compute the hash to paste into [_codeHash] for a chosen code.
///
/// Exposed for `tools/set_activation_code.dart`, which is how the code is
/// changed without ever writing the plain value into the repository.
String activationHashFor(String code) => hashPin(code.trim(), _codeSalt);

/// A random activation code, for an operator who has none in mind.
String generateActivationCode({int length = 10, Random? rng}) {
  // Excludes characters that are easy to misread aloud or in handwriting:
  // 0/O, 1/I/L. A code gets read off a receipt or dictated over the phone.
  const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  final random = rng ?? Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < length; i++) {
    buffer.write(alphabet[random.nextInt(alphabet.length)]);
  }
  return buffer.toString();
}

/// Verify a hash against a code — used by the tool and by tests.
bool activationHashMatches(String code, String expectedHash) =>
    verifyPin(code.trim(), expectedHash, _codeSalt);

/// The salt, for a tool that needs it without duplicating the literal.
String get activationSalt => _codeSalt;
