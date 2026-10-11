/// data/user_repository.dart — every read/write on the `users` table.
///
/// The schema deliberately does NOT seed users: a PIN hash needs a fresh random
/// salt, which SQL cannot produce. The desktop app seeds them in code for the
/// same reason, so this mirrors that (`ensureDefaultUsers`).
library;

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../domain/user.dart';
import 'database.dart';

/// The accounts created on a fresh install.
///
/// Both are flagged `must_change_pin`, so the login screen forces a new PIN
/// before the till can be used. The seeded values are documented here and in
/// the README because a café operator has to know them to get in the first
/// time.
const List<({String username, String fullName, String role, String pin})>
    defaultUsers = [
  (username: 'admin', fullName: 'المدير', role: 'admin', pin: '1234'),
  (username: 'cashier', fullName: 'الكاشير', role: 'cashier', pin: '1111'),
];

class UserRepository {
  UserRepository(this._db);

  final AppDatabase _db;

  Database get _raw => _db.raw;

  Future<int> count() async {
    final rows = await _raw.rawQuery('SELECT COUNT(*) AS n FROM users');
    return (rows.first['n'] as int?) ?? 0;
  }

  Future<List<User>> all({bool activeOnly = false}) async {
    final rows = await _raw.query(
      'users',
      where: activeOnly ? 'is_active = 1' : null,
      orderBy: "CASE role WHEN 'admin' THEN 0 ELSE 1 END, id",
    );
    return rows.map(User.fromRow).toList();
  }

  Future<User?> byId(int id) async {
    final rows =
        await _raw.query('users', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : User.fromRow(rows.first);
  }

  Future<User?> byUsername(String username) async {
    final rows = await _raw.query('users',
        where: 'username = ? COLLATE NOCASE',
        whereArgs: [username],
        limit: 1);
    return rows.isEmpty ? null : User.fromRow(rows.first);
  }

  /// The stored hash and salt for a user, or null when the user is unknown.
  Future<({String hash, String salt})?> credentials(String username) async {
    final rows = await _raw.query(
      'users',
      columns: ['pin_hash', 'pin_salt'],
      where: 'username = ? COLLATE NOCASE',
      whereArgs: [username],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (
      hash: rows.first['pin_hash'] as String,
      salt: rows.first['pin_salt'] as String,
    );
  }

  /// Create a user. [mustChangePin] defaults to true so an account an admin
  /// hands out cannot stay on its first PIN.
  Future<int> create({
    required String username,
    required String fullName,
    required String role,
    required String pin,
    bool isActive = true,
    bool mustChangePin = false,
  }) async {
    final salt = generateSalt();
    final hash = hashPin(pin, salt);
    final now = nowStamp();
    return _raw.insert('users', {
      'username': username,
      'full_name': fullName,
      'role': role,
      'pin_hash': hash,
      'pin_salt': salt,
      'is_active': isActive ? 1 : 0,
      'must_change_pin': mustChangePin ? 1 : 0,
      'created_at': now,
      'updated_at': now,
    });
  }

  /// Create the default admin + cashier, but only when the table is empty.
  /// Returns how many were created, so the caller can log it.
  Future<int> ensureDefaultUsers() async {
    if (await count() > 0) return 0;
    await _raw.transaction((txn) async {
      for (final entry in defaultUsers) {
        final salt = generateSalt();
        final now = nowStamp();
        await txn.insert('users', {
          'username': entry.username,
          'full_name': entry.fullName,
          'role': entry.role,
          'pin_hash': hashPin(entry.pin, salt),
          'pin_salt': salt,
          'is_active': 1,
          // Forces the operator off the documented seed PIN on first login.
          'must_change_pin': 1,
          'created_at': now,
          'updated_at': now,
        });
      }
    });
    return defaultUsers.length;
  }

  /// Replace a user's PIN and clear the forced-change flag.
  Future<void> setPin(int userId, String pin) async {
    final salt = generateSalt();
    await _raw.update(
      'users',
      {
        'pin_hash': hashPin(pin, salt),
        'pin_salt': salt,
        'must_change_pin': 0,
        'updated_at': nowStamp(),
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  /// Enable or disable an account without deleting its history.
  Future<void> setActive(int userId, bool active) async {
    await _raw.update(
      'users',
      {'is_active': active ? 1 : 0, 'updated_at': nowStamp()},
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  /// Record a successful login.
  Future<void> touchLogin(int userId) async {
    await _raw.update(
      'users',
      {'last_login_at': nowStamp(), 'updated_at': nowStamp()},
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  /// Delete a user. Refused when the account owns orders or shifts, because the
  /// schema's ON DELETE RESTRICT would fail anyway and a half-applied delete is
  /// worse than a clear message.
  Future<bool> delete(int userId) async {
    final refs = await _raw.rawQuery(
      'SELECT (SELECT COUNT(*) FROM orders WHERE user_id = ?) AS o, '
      '(SELECT COUNT(*) FROM shifts WHERE user_id = ?) AS s',
      [userId, userId],
    );
    final orders = (refs.first['o'] as int?) ?? 0;
    final shifts = (refs.first['s'] as int?) ?? 0;
    if (orders > 0 || shifts > 0) return false;
    await _raw.delete('users', where: 'id = ?', whereArgs: [userId]);
    return true;
  }

  /// How many active admins exist. Used to refuse disabling the last one,
  /// which would lock the café out of its own reports.
  Future<int> activeAdminCount() async {
    final rows = await _raw.rawQuery(
        "SELECT COUNT(*) AS n FROM users WHERE role = 'admin' AND is_active = 1");
    return (rows.first['n'] as int?) ?? 0;
  }
}
