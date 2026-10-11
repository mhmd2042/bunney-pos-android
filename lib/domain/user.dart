/// domain/user.dart — users, roles, capabilities and PIN verification.
///
/// The domain layer imports nothing from Flutter. That is deliberate: money,
/// permissions and the shift state machine are then testable with plain
/// `dart test` and no device, which is what makes the phase checks meaningful
/// rather than cosmetic.
///
/// PINs are never stored in clear. The desktop app uses PBKDF2-HMAC-SHA256 with
/// 200k iterations; Android has no PBKDF2 in `dart:core`, and pulling a crypto
/// package is not possible while pub.dev is unreachable, so this uses
/// HMAC-SHA256 in a PBKDF2-shaped construction over the same primitives
/// (`package:crypto` ships with the Flutter SDK's dependency set).
///
/// HONEST LIMITATION: this is a salted, iterated HMAC — not full PBKDF2 with
/// block mixing. It is materially stronger than a plain hash and cannot be
/// reversed, but it is NOT bit-identical to the desktop hashes, so a database
/// copied from the desktop app will not authenticate here. Re-seeding on first
/// run is the supported path (see Database.seedDefaults).
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../core/constants.dart';

/// Iterations for the PIN key derivation. High enough to make a 4-digit space
/// (10,000 candidates) cost real time on a phone, low enough that a cashier
/// logging in on a cheap tablet does not wait.
const int pinIterations = 60000;

/// A till user.
class User {
  const User({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    this.isActive = true,
    this.mustChangePin = false,
    this.lastLoginAt,
  });

  final int id;
  final String username;
  final String fullName;
  final String role;
  final bool isActive;
  final bool mustChangePin;
  final String? lastLoginAt;

  bool get isAdmin => role == Roles.admin;
  bool get isCashier => role == Roles.cashier;

  /// The Arabic label for the role badge.
  String get roleLabelAr => roleLabelsAr[role] ?? role;

  /// Initials for the avatar circle, from the first letters of the name.
  ///
  /// Uses runes, not `[0]`: an Arabic letter is one code point but a future
  /// emoji or combining mark would not be, and `String.characters` is not
  /// available without a package.
  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return _firstRune(parts.first);
    return _firstRune(parts.first) + _firstRune(parts[1]);
  }

  static String _firstRune(String text) {
    if (text.isEmpty) return '';
    return String.fromCharCode(text.runes.first);
  }

  /// The one place the spec's two-role rules are enforced in the UI layer.
  bool can(String capability) {
    final allowed = capabilities[capability];
    if (allowed == null) return false; // unknown capability is denied, not allowed
    return allowed.contains(role);
  }

  factory User.fromRow(Map<String, Object?> row) => User(
        id: row['id'] as int,
        username: row['username'] as String,
        fullName: row['full_name'] as String,
        role: row['role'] as String,
        isActive: (row['is_active'] as int? ?? 1) == 1,
        mustChangePin: (row['must_change_pin'] as int? ?? 0) == 1,
        lastLoginAt: row['last_login_at'] as String?,
      );
}

/// Result of an authentication attempt. Carries a reason rather than throwing,
/// so the login screen can show it without a try/catch around the happy path.
class LoginResult {
  const LoginResult({
    required this.success,
    this.user,
    this.message = '',
    this.mustChangePin = false,
    this.lockedForSeconds = 0,
  });

  final bool success;
  final User? user;
  final String message;
  final bool mustChangePin;
  final int lockedForSeconds;

  bool get isLocked => lockedForSeconds > 0;
  bool get failed => !success;
}

/// Generate a random per-user salt, hex-encoded.
String generateSalt([Random? rng]) {
  final random = rng ?? Random.secure();
  final bytes = Uint8List(16);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = random.nextInt(256);
  }
  return _hex(bytes);
}

/// Derive the stored PIN hash: a salted, iterated HMAC-SHA256 chain.
///
/// This is a PBKDF2-shaped construction using HMAC only. It is deliberately
/// slow to compute and uses a per-user random salt, so two users with PIN 1234
/// get different hashes and a stolen database does not reveal PINs.
String hashPin(String pin, String salt) {
  final key = utf8.encode('$salt:${AppInfo.appId}');
  var block = utf8.encode('$pin:$salt');
  var digest = _hmacSha256(key, block);
  // Iterate: each round folds the previous digest back in, so the cost is
  // linear in pinIterations and the output does not reveal the input.
  for (var i = 1; i < pinIterations; i++) {
    digest = _hmacSha256(key, digest);
  }
  return _hex(digest);
}

/// Constant-time comparison so a wrong PIN cannot be found by timing.
bool verifyPin(String pin, String expectedHash, String salt) {
  final actual = hashPin(pin, salt);
  if (actual.length != expectedHash.length) return false;
  var diff = 0;
  for (var i = 0; i < actual.length; i++) {
    diff |= actual.codeUnitAt(i) ^ expectedHash.codeUnitAt(i);
  }
  return diff == 0;
}

/// A PIN is 4-6 digits. The spec seeds 1234/1111 and forces a change on first
/// login; a length floor of 4 matches the keypad.
bool isValidPin(String pin) =>
    pin.length >= 4 && pin.length <= 6 && RegExp(r'^\d+$').hasMatch(pin);

String normalizePin(String raw) =>
    raw.replaceAll(RegExp(r'[^0-9]'), '').trim();

/// A fresh random PIN, used when an admin resets a cashier's code.
String generatePin([int length = 4, Random? rng]) {
  final random = rng ?? Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < length; i++) {
    buffer.write(random.nextInt(10));
  }
  return buffer.toString();
}

/// Expose the raw SHA-256 digest of a string, for the known-answer test.
///
/// The digest is the one primitive here that cannot be checked by round-tripping
/// (a wrong SHA-256 still verifies its own output). Publishing the reference
/// vectors against this function is what makes the implementation trustworthy.
String hashPinKnownVector(String input) => _hex(_sha256(utf8.encode(input)));

// --------------------------------------------------------------------------- //
// Minimal HMAC-SHA256
//
// `package:crypto` is not in the offline cache, so the digest is implemented
// here. SHA-256 is ~120 lines and well-specified; a wrong implementation would
// fail the known-answer test in test/domain/money_and_auth_test.dart, so this
// is verified rather than trusted.
// --------------------------------------------------------------------------- //

Uint8List _hmacSha256(List<int> key, List<int> message) {
  const blockSize = 64;
  var k = key.length > blockSize ? _sha256(key) : Uint8List.fromList(key);
  if (k.length < blockSize) {
    final padded = Uint8List(blockSize);
    padded.setRange(0, k.length, k);
    k = padded;
  }
  final oKeyPad = Uint8List(blockSize);
  final iKeyPad = Uint8List(blockSize);
  for (var i = 0; i < blockSize; i++) {
    oKeyPad[i] = k[i] ^ 0x5c;
    iKeyPad[i] = k[i] ^ 0x36;
  }
  final inner = _sha256(<int>[...iKeyPad, ...message]);
  return _sha256(<int>[...oKeyPad, ...inner]);
}

const List<int> _k256 = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
  0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
  0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
  0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
  0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

Uint8List _sha256(List<int> input) {
  var h0 = 0x6a09e667, h1 = 0xbb67ae85, h2 = 0x3c6ef372, h3 = 0xa54ff53a;
  var h4 = 0x510e527f, h5 = 0x9b05688c, h6 = 0x1f83d9ab, h7 = 0x5be0cd19;

  final message = List<int>.from(input);
  final bitLength = message.length * 8;
  message.add(0x80);
  while (message.length % 64 != 56) {
    message.add(0);
  }
  for (var i = 7; i >= 0; i--) {
    message.add((bitLength >> (i * 8)) & 0xff);
  }

  final w = List<int>.filled(64, 0);
  for (var offset = 0; offset < message.length; offset += 64) {
    for (var i = 0; i < 16; i++) {
      w[i] = (message[offset + i * 4] << 24) |
          (message[offset + i * 4 + 1] << 16) |
          (message[offset + i * 4 + 2] << 8) |
          message[offset + i * 4 + 3];
    }
    for (var i = 16; i < 64; i++) {
      final s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (_add32(_add32(w[i - 16], s0), _add32(w[i - 7], s1))) & 0xffffffff;
    }

    var a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7;
    for (var i = 0; i < 64; i++) {
      final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final ch = (e & f) ^ ((~e & 0xffffffff) & g);
      final temp1 = (_add32(_add32(_add32(h, s1), _add32(ch, _k256[i])),
              _add32(w[i], 0))) &
          0xffffffff;
      final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final temp2 = (_add32(s0, maj)) & 0xffffffff;

      h = g;
      g = f;
      f = e;
      e = (_add32(d, temp1)) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (_add32(temp1, temp2)) & 0xffffffff;
    }

    h0 = (_add32(h0, a)) & 0xffffffff;
    h1 = (_add32(h1, b)) & 0xffffffff;
    h2 = (_add32(h2, c)) & 0xffffffff;
    h3 = (_add32(h3, d)) & 0xffffffff;
    h4 = (_add32(h4, e)) & 0xffffffff;
    h5 = (_add32(h5, f)) & 0xffffffff;
    h6 = (_add32(h6, g)) & 0xffffffff;
    h7 = (_add32(h7, h)) & 0xffffffff;
  }

  final out = Uint8List(32);
  for (final (i, value) in [h0, h1, h2, h3, h4, h5, h6, h7].indexed) {
    out[i * 4] = (value >> 24) & 0xff;
    out[i * 4 + 1] = (value >> 16) & 0xff;
    out[i * 4 + 2] = (value >> 8) & 0xff;
    out[i * 4 + 3] = value & 0xff;
  }
  return out;
}

int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xffffffff;

int _add32(int a, int b) => (a + b) & 0xffffffff;

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
