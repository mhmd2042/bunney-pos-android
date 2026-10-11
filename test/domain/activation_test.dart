/// test/domain/activation_test.dart — the one-time activation gate.
///
/// The gate has one job that matters and two that can silently fail: it must
/// accept the real code, reject everything else, and remember the success so
/// the screen never appears again. All three are asserted here, with the
/// storage injected so no device is needed.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:bunney_pos_android/domain/activation.dart';
import 'package:bunney_pos_android/domain/user.dart';

/// An in-memory stand-in for the Keystore-backed flag.
class FakeStorage {
  bool activated = false;
  int writes = 0;

  Future<bool> read() async => activated;

  Future<void> write(bool value) async {
    writes++;
    activated = value;
  }
}

ActivationGate gateFor(FakeStorage storage, {String? hash}) => ActivationGate(
      readActivated: storage.read,
      writeActivated: storage.write,
      codeHash: hash,
    );

void main() {
  // Hashing 60k iterations is the point, but 40 tests of it is slow; the gate
  // is exercised through a precomputed hash so the test runs in a second.
  late String goodHash;
  setUpAll(() {
    goodHash = activationHashFor('BUNNEY2026');
  });

  group('the shipped code', () {
    test('the hash in the source matches the documented code', () {
      // If this fails, the README's code and the build disagree and no operator
      // can activate the app. That is the failure this test exists to catch.
      expect(activationHashMatches('BUNNEY2026', defaultActivationHash), isTrue,
          reason: 'defaultActivationHash must be the hash of the documented '
              'code; regenerate with tools/set_activation_code.dart');
    });

    test('the plain code is not in the source', () {
      // The hash is a build artefact; the code itself must not be greppable.
      expect(defaultActivationHash.contains('BUNNEY'), isFalse);
      expect(defaultActivationHash.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(defaultActivationHash), isTrue);
    });
  });

  group('accepting and rejecting', () {
    test('the right code activates and is remembered', () async {
      final storage = FakeStorage();
      final gate = gateFor(storage, hash: goodHash);

      final result = await gate.submit('BUNNEY2026');

      expect(result.success, isTrue);
      expect(storage.activated, isTrue, reason: 'the flag must be persisted');
      expect(storage.writes, 1);
      expect(await gate.isActivated(), isTrue);
    });

    test('a wrong code is rejected and nothing is persisted', () async {
      final storage = FakeStorage();
      final gate = gateFor(storage, hash: goodHash);

      final result = await gate.submit('WRONG-CODE');

      expect(result.success, isFalse);
      expect(result.message, isNotEmpty);
      expect(storage.activated, isFalse);
      expect(storage.writes, 0, reason: 'a failure must not write the flag');
    });

    test('an empty or whitespace code is refused without counting', () async {
      final storage = FakeStorage();
      final gate = gateFor(storage, hash: goodHash);

      expect((await gate.submit('')).success, isFalse);
      expect((await gate.submit('   ')).success, isFalse);
      expect(gate.failures, 0, reason: 'a blank field is not a wrong guess');
    });

    test('surrounding whitespace is tolerated', () async {
      // A code is often pasted or read off paper; a stray space must not lock
      // the operator out.
      final storage = FakeStorage();
      final gate = gateFor(storage, hash: goodHash);
      expect((await gate.submit('  BUNNEY2026  ')).success, isTrue);
    });

    test('the code is case sensitive', () async {
      final storage = FakeStorage();
      final gate = gateFor(storage, hash: goodHash);
      expect((await gate.submit('bunney2026')).success, isFalse);
    });

    test('an already-activated device reports so', () async {
      final storage = FakeStorage()..activated = true;
      final gate = gateFor(storage, hash: goodHash);
      expect(await gate.isActivated(), isTrue);
    });

    test('a fresh device reports not activated', () async {
      final gate = gateFor(FakeStorage(), hash: goodHash);
      expect(await gate.isActivated(), isFalse);
    });
  });

  group('repeated failures slow down', () {
    test('the first two wrong codes do not delay', () async {
      final gate = gateFor(FakeStorage(), hash: goodHash);
      expect((await gate.submit('x')).isDelayed, isFalse);
      expect((await gate.submit('y')).isDelayed, isFalse);
      expect(gate.failures, 2);
    });

    test('the third and later wrong codes carry a delay', () async {
      final gate = gateFor(FakeStorage(), hash: goodHash);
      await gate.submit('a');
      await gate.submit('b');
      final third = await gate.submit('c');
      expect(third.isDelayed, isTrue);
      expect(third.delaySeconds, activationDelaySeconds);
      // And it stays on for later attempts.
      expect((await gate.submit('d')).isDelayed, isTrue);
    });

    test('a correct code resets the failure count', () async {
      final gate = gateFor(FakeStorage(), hash: goodHash);
      await gate.submit('a');
      await gate.submit('b');
      await gate.submit('BUNNEY2026');
      expect(gate.failures, 0);
    });

    test('there is no hard lockout — the operator is never shut out', () async {
      // A café that mistypes must be able to get in eventually. The delay slows
      // guessing; it must not make the till permanently unusable.
      final gate = gateFor(FakeStorage(), hash: goodHash);
      for (var i = 0; i < 20; i++) {
        await gate.submit('wrong$i');
      }
      final result = await gate.submit('BUNNEY2026');
      expect(result.success, isTrue,
          reason: 'the real code must always work, however many failures');
    });
  });

  group('generated codes', () {
    test('avoid characters that are misread or misheard', () {
      // A code gets dictated over the phone or read off paper: 0/O and 1/I/L
      // are the pairs people get wrong.
      for (var i = 0; i < 50; i++) {
        final code = generateActivationCode();
        expect(RegExp(r'[0O1IL]').hasMatch(code), isFalse, reason: code);
      }
    });

    test('are long enough to not be guessable by hand', () {
      expect(generateActivationCode().length, greaterThanOrEqualTo(8));
    });

    test('two generated codes differ', () {
      expect(generateActivationCode(), isNot(generateActivationCode()));
    });
  });

  group('the hash function', () {
    test('is deterministic', () {
      expect(activationHashFor('ABC'), activationHashFor('ABC'));
    });

    test('differs for different codes', () {
      expect(activationHashFor('ABC'), isNot(activationHashFor('ABD')));
    });

    test('trims before hashing, so a pasted space still works', () {
      expect(activationHashFor(' ABC '), activationHashFor('ABC'));
    });

    test('reuses the project PIN hasher rather than a second implementation',
        () {
      // Two hash implementations that can drift is the bug this guards.
      expect(activationHashFor('X'), hashPin('X', activationSalt));
    });
  });
}
