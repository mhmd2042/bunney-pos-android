/// test/domain/money_and_auth_test.dart — the phase-1 gate.
///
/// Everything here runs with plain `flutter test` and no device: the money
/// rules, the capability tree and the PIN hashing are pure Dart. That is the
/// point of keeping the domain layer free of Flutter — a wrong SHA-256 or a
/// wrong tax split fails here, not on a tablet at a café counter.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:bunney_pos_android/core/constants.dart';
import 'package:bunney_pos_android/core/money.dart';
import 'package:bunney_pos_android/domain/user.dart';

void main() {
  group('money — integer minor units', () {
    test('YER treats a whole rial as the minor unit', () {
      expect(MoneyConfig.minorUnitsPerMajor, 1);
      expect(toMinor(2500), 2500);
      expect(toMinor(2500.0), 2500);
      expect(toMajor(2500), 2500.0);
    });

    test('formats with a comma grouping and the rial symbol', () {
      expect(formatMoney(2500), '2,500 ر.ي');
      expect(formatMoney(500), '500 ر.ي');
      expect(formatMoney(1000000), '1,000,000 ر.ي');
      expect(formatMoney(0), '0 ر.ي');
      expect(formatMoney(2500, symbol: false), '2,500');
    });

    test('formats a negative amount with the sign outside the digits', () {
      expect(formatMoney(-2500), '-2,500 ر.ي');
    });

    test('a 0% rate embeds no tax', () {
      expect(extractTaxFromInclusive(2500), 0);
      expect(netFromInclusive(2500), 2500);
    });

    test('a non-zero rate extracts the embedded portion, not an addition', () {
      // 1,150 inclusive at 15% => 1,000 net + 150 tax.
      expect(extractTaxFromInclusive(1150, taxRate: 0.15), 150);
      expect(netFromInclusive(1150, taxRate: 0.15), 1000);
      // The parts always re-add to the whole — this is the property that makes
      // a receipt reconcile.
      for (final total in [1, 7, 99, 2500, 12345, 999999]) {
        final tax = extractTaxFromInclusive(total, taxRate: 0.15);
        expect(tax + netFromInclusive(total, taxRate: 0.15), total,
            reason: 'total $total must split cleanly');
      }
    });

    test('change never goes negative on an underpayment', () {
      expect(changeFor(2500, 5000), 2500);
      expect(changeFor(2500, 2500), 0);
      expect(changeFor(2500, 1000), 0);
    });

    test('margin is clamped at zero and reports a percentage', () {
      expect(marginMinor(priceMinor: 2500, costMinor: 600), 1900);
      expect(marginMinor(priceMinor: 100, costMinor: 500), 0);
      expect(marginPercent(priceMinor: 1000, costMinor: 400), closeTo(60, 0.01));
      expect(marginPercent(priceMinor: 0, costMinor: 0), 0);
    });

    test('summing a basket stays exact where a double would drift', () {
      // 0.1 + 0.2 != 0.3 in binary floating point; in minor units it is exact.
      var total = 0;
      for (var i = 0; i < 40; i++) {
        total += 2500;
      }
      expect(total, 100000);
      expect(formatMoney(total), '100,000 ر.ي');
    });
  });

  group('capabilities — the two-role tree', () {
    test('a cashier may sell but not administer', () {
      const cashier = User(
          id: 1, username: 'c', fullName: 'كاشير', role: Roles.cashier);
      expect(cashier.can('create_order'), isTrue);
      expect(cashier.can('take_payment'), isTrue);
      expect(cashier.can('open_shift'), isTrue);
      expect(cashier.can('close_shift'), isTrue);
      // The spec's explicit restrictions for the cashier role.
      expect(cashier.can('edit_prices'), isFalse);
      expect(cashier.can('view_profit'), isFalse);
      expect(cashier.can('void_order'), isFalse);
      expect(cashier.can('apply_discount'), isFalse);
      expect(cashier.can('view_reports'), isFalse);
      expect(cashier.can('manage_inventory'), isFalse);
      expect(cashier.can('manage_backups'), isFalse);
      expect(cashier.can('manage_users'), isFalse);
    });

    test('an admin may do everything the cashier may, and more', () {
      const admin =
          User(id: 2, username: 'a', fullName: 'مدير', role: Roles.admin);
      for (final capability in capabilities.keys) {
        expect(admin.can(capability), isTrue,
            reason: 'admin must hold $capability');
      }
    });

    test('an unknown capability is denied, not allowed', () {
      const admin =
          User(id: 2, username: 'a', fullName: 'مدير', role: Roles.admin);
      expect(admin.can('launch_missiles'), isFalse);
    });

    test('every capability names only real roles', () {
      for (final entry in capabilities.entries) {
        expect(entry.value, isNotEmpty, reason: '${entry.key} allows nobody');
        for (final role in entry.value) {
          expect([Roles.admin, Roles.cashier], contains(role));
        }
      }
    });

    test('a cashier cannot do anything that is admin-only', () {
      const cashier = User(
          id: 1, username: 'c', fullName: 'كاشير', role: Roles.cashier);
      final adminOnly = capabilities.entries
          .where((e) => !e.value.contains(Roles.cashier))
          .map((e) => e.key);
      for (final capability in adminOnly) {
        expect(cashier.can(capability), isFalse);
      }
    });
  });

  group('user — identity helpers', () {
    test('initials come from the first letters of the name', () {
      const user = User(
          id: 1, username: 'x', fullName: 'محمد العقيلي', role: Roles.admin);
      // First letter of each of the first two words: محمد + العقيلي -> ما
      expect(user.initials, 'ما');
      const single =
          User(id: 2, username: 'y', fullName: 'سالم', role: Roles.cashier);
      expect(single.initials, 'س');
      const blank =
          User(id: 3, username: 'z', fullName: '   ', role: Roles.cashier);
      expect(blank.initials, '?');
    });

    test('the role label is Arabic', () {
      const admin =
          User(id: 1, username: 'a', fullName: 'م', role: Roles.admin);
      expect(admin.roleLabelAr, 'المدير');
      expect(admin.isAdmin, isTrue);
      expect(admin.isCashier, isFalse);
    });

    test('a row round-trips from SQLite', () {
      final user = User.fromRow({
        'id': 3,
        'username': 'cashier',
        'full_name': 'الكاشير',
        'role': 'cashier',
        'is_active': 1,
        'must_change_pin': 0,
        'last_login_at': null,
      });
      expect(user.id, 3);
      expect(user.isActive, isTrue);
      expect(user.mustChangePin, isFalse);
    });
  });

  group('PIN hashing', () {
    test('a known SHA-256 vector — proves the digest is correct', () {
      // If the SHA-256 implementation is wrong, this is the test that says so.
      // "abc" hashes to this value in every reference implementation.
      final digest = hashPinKnownVector('abc');
      expect(digest,
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });

    test('the empty string vector also holds', () {
      expect(
          hashPinKnownVector(''),
          'e3b0c44298fc1c149afbf4c8996fb924'
          '27ae41e4649b934ca495991b7852b855');
    });

    test('a hash verifies against its own PIN and salt', () {
      final salt = generateSalt();
      final hash = hashPin('1234', salt);
      expect(verifyPin('1234', hash, salt), isTrue);
      expect(verifyPin('1235', hash, salt), isFalse);
      expect(verifyPin('', hash, salt), isFalse);
    });

    test('the same PIN with different salts gives different hashes', () {
      final a = hashPin('1234', generateSalt());
      final b = hashPin('1234', generateSalt());
      expect(a, isNot(equals(b)));
    });

    test('the hash never contains the PIN', () {
      final salt = generateSalt();
      final hash = hashPin('1234', salt);
      expect(hash.contains('1234'), isFalse);
      expect(hash.length, 64, reason: 'SHA-256 hex is 64 chars');
    });

    test('salt is random and hex', () {
      final a = generateSalt();
      final b = generateSalt();
      expect(a, isNot(equals(b)));
      expect(a.length, 32);
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(a), isTrue);
    });

    test('PIN validation accepts 4-6 digits only', () {
      expect(isValidPin('1234'), isTrue);
      expect(isValidPin('123456'), isTrue);
      expect(isValidPin('123'), isFalse);
      expect(isValidPin('1234567'), isFalse);
      expect(isValidPin('12a4'), isFalse);
      expect(isValidPin(''), isFalse);
    });

    test('normalizePin strips anything that is not a digit', () {
      expect(normalizePin(' 1-2 3 4 '), '1234');
      expect(normalizePin('١٢٣٤'), '');
    });

    test('a generated PIN is the requested length and numeric', () {
      final pin = generatePin(4);
      expect(pin.length, 4);
      expect(RegExp(r'^\d{4}$').hasMatch(pin), isTrue);
    });
  });
}
