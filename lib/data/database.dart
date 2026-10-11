/// data/database.dart — the encrypted SQLite database and its lifecycle.
///
/// Same 16-table schema as the desktop app, applied verbatim from
/// `assets/schema/schema.sql`, so a café's data model is identical on both.
///
/// ENCRYPTION: the file is opened with SQLCipher. The key is 32 random bytes
/// generated on first run and kept in the Android Keystore through
/// flutter_secure_storage — never in the database, never in the source, never
/// in a log. Losing the Keystore entry (an app reinstall, a "clear data") means
/// the database cannot be opened; that is the intended trade for a device that
/// might be stolen, and it is why the backup export is offered as the way to
/// move data between devices.
///
/// The schema is applied in one transaction so a crash mid-seed cannot leave a
/// half-built database behind.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../core/constants.dart';

/// Where the encryption key lives inside the Keystore.
const String _keyStorageKey = 'bunney_db_key_v1';

/// The current schema version. Must match `PRAGMA user_version` expectations in
/// the migration ladder below.
const int schemaVersion = 4;

/// A database that could not be opened or built.
class DatabaseException implements Exception {
  DatabaseException(this.message);
  final String message;
  @override
  String toString() => 'DatabaseException: $message';
}

/// Owns the one open connection and the schema bootstrap.
class AppDatabase {
  AppDatabase._(this._db, this.path);

  /// A database handle with no connection, for tests that need the type but
  /// never touch the data. Any real call fails with a clear message rather than
  /// a null dereference.
  AppDatabase.forTesting()
      : _db = null,
        path = '';

  final Database? _db;
  final String path;

  Database get raw {
    final value = _db;
    if (value == null) {
      throw DatabaseException('this handle has no connection (forTesting)');
    }
    return value;
  }

  static AppDatabase? _instance;

  /// The open database. Throws if [open] has not run.
  static AppDatabase get instance {
    final value = _instance;
    if (value == null) {
      throw DatabaseException('the database has not been opened yet');
    }
    return value;
  }

  static bool get isOpen => _instance != null;

  /// Close and forget the connection. Used by tests and by a full app reset.
  static Future<void> close() async {
    final value = _instance;
    _instance = null;
    final connection = value?._db;
    if (connection != null) await connection.close();
  }

  /// Open (creating if needed) the encrypted database.
  ///
  /// [directory] and [keyOverride] exist for tests, which must not touch the
  /// real app directory or the Keystore.
  static Future<AppDatabase> open({
    String? directory,
    String? keyOverride,
    bool applySchema = true,
  }) async {
    if (_instance != null) return _instance!;

    final dir = directory ?? (await getApplicationDocumentsDirectory()).path;
    final file = p.join(dir, '${AppInfo.appId}.db');

    final key = keyOverride ?? await _loadOrCreateKey();
    if (key.isEmpty) {
      throw DatabaseException('the database key is empty');
    }

    final Database db;
    try {
      db = await openDatabase(
        file,
        password: key,
        version: schemaVersion,
        onConfigure: (d) async {
          // Foreign keys are OFF by default in SQLite; the schema depends on
          // them for every REFERENCES clause.
          await d.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (d, version) async {
          if (applySchema) await _applySchema(d);
        },
        onUpgrade: (d, from, to) async {
          await _migrate(d, from, to);
        },
      );
    } on DatabaseException catch (e) {
      // A wrong key and a corrupt file both surface here. The message has to be
      // actionable for a café operator, not a stack trace.
      throw DatabaseException(
        'تعذّر فتح قاعدة البيانات. قد يكون الملف تالفاً أو مفتاح التشفير غير مطابق. ($e)',
      );
    }

    final result = AppDatabase._(db, file);
    _instance = result;
    return result;
  }

  /// Read the encryption key, generating and storing one on first run.
  static Future<String> _loadOrCreateKey() async {
    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    );
    final existing = await storage.read(key: _keyStorageKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final key = _randomKey();
    await storage.write(key: _keyStorageKey, value: key);
    return key;
  }

  /// 32 random bytes as hex — a 256-bit SQLCipher key.
  static String _randomKey() {
    final rng = _secureRandom();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static _Rng _secureRandom() => _Rng();

  /// Apply the bundled schema in one transaction.
  static Future<void> _applySchema(Database db) async {
    final sql = await rootBundle.loadString('assets/schema/schema.sql');
    await db.transaction((txn) async {
      for (final statement in _splitStatements(sql)) {
        await txn.execute(statement);
      }
    });
  }

  /// Split a SQL script into executable statements.
  ///
  /// `sqflite` executes one statement per call, so the script has to be split
  /// on semicolons — but NOT on a semicolon inside a string literal, which the
  /// seed rows contain (the receipt footer has none, but a café name might).
  /// Comments are stripped first so a `--` line cannot hide a terminator.
  static List<String> _splitStatements(String script) {
    final withoutBlockComments =
        script.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
    final lines = withoutBlockComments
        .split('\n')
        .map((line) {
          // Strip a trailing line comment, but keep a `--` inside quotes.
          var inSingle = false;
          for (var i = 0; i < line.length - 1; i++) {
            final ch = line[i];
            if (ch == "'") inSingle = !inSingle;
            if (!inSingle && ch == '-' && line[i + 1] == '-') {
              return line.substring(0, i);
            }
          }
          return line;
        })
        .join('\n');

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

  /// Migration ladder. v1 is the initial schema; later versions add columns or
  /// indexes here, mirroring the desktop app's migrations.
  static Future<void> _migrate(Database db, int from, int to) async {
    // The schema is created at `schemaVersion`, so an upgrade path is only
    // needed once a release ships a higher version. Kept explicit rather than
    // silent so a future change has an obvious home.
    if (from < to) {
      throw DatabaseException(
        'لا يوجد مسار ترقية من الإصدار $from إلى $to',
      );
    }
  }

  // -- settings ----------------------------------------------------------- //

  /// Read one setting, or [fallback] when it is absent.
  Future<String> setting(String key, {String fallback = ''}) async {
    final rows = await raw.query('settings',
        columns: ['value'], where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return fallback;
    return (rows.first['value'] as String?) ?? fallback;
  }

  /// Read every setting as a map — the shape the printer and reports want.
  Future<Map<String, String>> allSettings() async {
    final rows = await raw.query('settings');
    return {
      for (final row in rows)
        row['key'] as String: (row['value'] as String?) ?? '',
    };
  }

  /// Write one setting, creating it when absent.
  Future<void> setSetting(String key, String value) async {
    await raw.insert(
      'settings',
      {
        'key': key,
        'value': value,
        'updated_at': _nowStamp(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// True when the file exists on disk (used by the backup screen).
  bool get fileExists => File(path).existsSync();

  int get sizeBytes {
    final file = File(path);
    return file.existsSync() ? file.lengthSync() : 0;
  }
}

/// Local-time stamp in the same format the schema's defaults use, so a value
/// written by Dart sorts against one written by SQLite's `datetime('now')`.
String nowStamp() => _nowStamp();

String _nowStamp() {
  final now = DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)} '
      '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
}

/// A tiny wrapper so the key generator does not pull `dart:math` into the
/// public API of this file.
class _Rng {
  final _random = Random.secure();
  int nextInt(int max) => _random.nextInt(max);
}
