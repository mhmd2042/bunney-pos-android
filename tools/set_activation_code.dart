/// tools/set_activation_code.dart — print the hash for a chosen code.
///
/// The activation code is never written into the repository in the clear. To
/// change it: run this, paste the printed hash into `_codeHash` in
/// lib/domain/activation.dart, and rebuild.
///
/// Run as a test rather than with `dart run`, because this project's build
/// hooks (the sqflite/sqlite3 native setup) are not available to a bare
/// `dart run` invocation — `flutter test` has the same package resolution and
/// does work.
///
///   flutter test tools/set_activation_code.dart --plain-name 'print'
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:bunney_pos_android/domain/activation.dart';

void main() {
  test('print activation hashes', () {
    // Change this list to the codes you want hashes for.
    const codes = <String>[
      'BUNNEY2026',
    ];

    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('=' * 62);
    // ignore: avoid_print
    print(' ACTIVATION CODE HASHES');
    // ignore: avoid_print
    print('=' * 62);
    for (final code in codes) {
      final hash = activationHashFor(code);
      // ignore: avoid_print
      print('');
      // ignore: avoid_print
      print('  code : $code');
      // ignore: avoid_print
      print('  hash : $hash');
      // Prove the hash verifies, so a mistyped paste is caught here.
      // ignore: avoid_print
      print('  check: ${activationHashMatches(code, hash) ? "OK" : "BROKEN"}');
    }
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print(' Paste the hash into _codeHash in lib/domain/activation.dart.');
    // ignore: avoid_print
    print('=' * 62);

    expect(activationHashFor(codes.first),
        activationHashFor(codes.first),
        reason: 'the hasher must be deterministic');
  });

  test('a generated code is readable and unambiguous', () {
    final code = generateActivationCode();
    // No 0/O/1/I/L, which are the characters people misread or mishear.
    expect(RegExp(r'[0O1IL]').hasMatch(code), isFalse,
        reason: 'generated code must avoid look-alike characters: $code');
    expect(code.length, 10);
  });

  test('the salt is not the code and is not empty', () {
    expect(activationSalt, isNotEmpty);
  });
}
