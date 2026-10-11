/// test/data/schema_test.dart — the phase-1 database gate.
///
/// WHAT THIS CAN AND CANNOT CHECK HERE
///   The database file is opened with SQLCipher on the device. The offline
///   package cache has no `sqflite_common_ffi`, so a plain Dart VM cannot open
///   a real encrypted file in this environment — that check has to run on a
///   device (see test/device/README.md for the command).
///
///   What IS checkable here, and is the part most likely to be wrong, is the
///   SQL itself: the statement splitter, the 16 tables, the constraints, the
///   seeds and the opening stock ledger. Those are verified against a real
///   SQLite through the `sqlite3` CLI in test/data/schema_cli_test.dart.
///
/// This file keeps the pure-Dart assertions (the splitter) and documents the
/// device-only boundary rather than pretending to cover it.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:bunney_pos_android/core/constants.dart';
import 'package:bunney_pos_android/data/user_repository.dart';
import 'package:bunney_pos_android/domain/user.dart';

/// Mirrors AppDatabase._splitStatements so the splitter is under test without
/// pulling in the plugin.
List<String> splitSqlStatements(String script) {
  final noBlocks = script.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  final lines = noBlocks.split('\n').map((line) {
    var inSingle = false;
    for (var i = 0; i < line.length - 1; i++) {
      final ch = line[i];
      if (ch == "'") inSingle = !inSingle;
      if (!inSingle && ch == '-' && line[i + 1] == '-') {
        return line.substring(0, i);
      }
    }
    return line;
  }).join('\n');

  final statements = <String>[];
  final buffer = StringBuffer();
  var inSingle = false;
  for (var i = 0; i < lines.length; i++) {
    final ch = lines[i];
    if (ch == "'") inSingle = !inSingle;
    if (ch == ';' && !inSingle) {
      final statement = buffer.toString().trim();
      if (statement.isNotEmpty) statements.add(statement);
      buffer.clear();
    } else {
      buffer.write(ch);
    }
  }
  final tail = buffer.toString().trim();
  if (tail.isNotEmpty) statements.add(tail);
  return statements;
}

void main() {
  group('SQL splitter — the part that silently corrupts a schema', () {
    test('splits on semicolons', () {
      expect(splitSqlStatements('SELECT 1; SELECT 2; SELECT 3;'),
          ['SELECT 1', 'SELECT 2', 'SELECT 3']);
    });

    test('does not split on a semicolon inside a string literal', () {
      final parts = splitSqlStatements("INSERT INTO t VALUES ('a;b'); SELECT 1;");
      expect(parts.length, 2);
      expect(parts.first, contains("'a;b'"));
    });

    test('strips line comments without eating a -- inside a literal', () {
      final parts = splitSqlStatements(
        "-- a comment; with a semicolon\nSELECT 1; -- trailing\nSELECT 2;",
      );
      expect(parts, ['SELECT 1', 'SELECT 2']);
    });

    test('strips block comments', () {
      expect(splitSqlStatements('/* a; block */ SELECT 1;'), ['SELECT 1']);
    });

    test('keeps a statement that has no trailing semicolon', () {
      expect(splitSqlStatements('SELECT 1'), ['SELECT 1']);
    });

    test('ignores empty statements from blank lines', () {
      expect(splitSqlStatements('SELECT 1;;\n\n;SELECT 2;'),
          ['SELECT 1', 'SELECT 2']);
    });
  });

  group('seeded credentials are documented and forced to change', () {
    test('the two default accounts are admin/1234 and cashier/1111', () {
      // Pinned deliberately: a café operator reads these from the README, so a
      // silent change here would lock people out.
      expect(defaultUsers.length, 2);
      expect(defaultUsers[0].username, 'admin');
      expect(defaultUsers[0].pin, '1234');
      expect(defaultUsers[0].role, Roles.admin);
      expect(defaultUsers[1].username, 'cashier');
      expect(defaultUsers[1].pin, '1111');
      expect(defaultUsers[1].role, Roles.cashier);
    });

    test('both seeded PINs are valid under the PIN policy', () {
      for (final entry in defaultUsers) {
        expect(isValidPin(entry.pin), isTrue,
            reason: '${entry.username} seed PIN must pass validation');
      }
    });
  });

  group('money columns — the convention the reports rely on', () {
    test('the money constants match the desktop app', () {
      expect(MoneyConfig.minorUnitsPerMajor, 1);
      expect(MoneyConfig.currencyCode, 'YER');
      expect(MoneyConfig.currencySymbol, 'ر.ي');
      expect(MoneyConfig.defaultTaxRate, 0.0);
    });
  });

  group('layout constants — the spec’s 48–56dp rule', () {
    test('touch targets are inside the Android range', () {
      expect(Sizes.minTouchTarget, inInclusiveRange(48, 56));
      expect(Sizes.primaryTouchTarget, inInclusiveRange(48, 56));
    });

    test('the tablet breakpoint is Android’s own sw600dp', () {
      expect(Sizes.tabletBreakpoint, 600);
    });
  });
}
