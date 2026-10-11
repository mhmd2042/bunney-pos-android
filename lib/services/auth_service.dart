/// services/auth_service.dart — login, the session, and the attempt lockout.
///
/// The rule this mirrors from the desktop app: a cashier may sell and manage
/// their own shift; an admin may do everything. The check is `user.can(...)`,
/// never a role-string comparison, so a third role later needs one entry in the
/// capability table and nothing else.
///
/// The lockout is per-user, not global: a cashier mistyping must not stop the
/// admin signing in behind them.
library;

import 'dart:developer' as developer;

import '../data/database.dart';
import '../data/user_repository.dart';
import '../domain/user.dart';

/// Wrong PINs before a user is temporarily locked, matching the desktop app.
const int maxFailedAttempts = 5;
/// How long the lockout lasts.
const int lockoutSeconds = 30;

/// Tracks failures per username and answers how long a lockout has left.
class AttemptTracker {
  AttemptTracker({this.maxAttempts = maxFailedAttempts, this.lockout = lockoutSeconds});

  final int maxAttempts;
  final int lockout;

  final Map<String, int> _failures = {};
  final Map<String, DateTime> _lockedAt = {};

  /// Seconds remaining for [username], or 0 when not locked.
  int lockedFor(String username) {
    final locked = _lockedAt[username];
    if (locked == null) return 0;
    final elapsed = DateTime.now().difference(locked).inSeconds;
    final remaining = lockout - elapsed;
    if (remaining <= 0) {
      _lockedAt.remove(username);
      _failures.remove(username);
      return 0;
    }
    return remaining;
  }

  /// Record a failure; returns the remaining lockout in seconds (0 if free).
  int registerFailure(String username) {
    final count = (_failures[username] ?? 0) + 1;
    _failures[username] = count;
    if (count >= maxAttempts) {
      _lockedAt[username] = DateTime.now();
      return lockout;
    }
    return 0;
  }

  /// Clear a user's history after a successful login.
  void reset(String username) {
    _failures.remove(username);
    _lockedAt.remove(username);
  }

  /// Clear everything — used when the screen is left.
  void clear() {
    _failures.clear();
    _lockedAt.clear();
  }

  /// Failures so far for [username].
  int failures(String username) => _failures[username] ?? 0;
}

/// Authentication and the current session.
class AuthService {
  AuthService({required AppDatabase db, UserRepository? users, AttemptTracker? tracker})
      : _users = users ?? UserRepository(db),
        _tracker = tracker ?? AttemptTracker();

  final UserRepository _users;
  final AttemptTracker _tracker;

  User? _current;

  User? get currentUser => _current;
  bool get isAuthenticated => _current != null;
  AttemptTracker get tracker => _tracker;

  /// Verify a PIN for a known user.
  ///
  /// A disabled account is refused before the PIN is even checked, so a
  /// dismissed employee cannot sign in with a PIN they still remember.
  Future<LoginResult> login(User user, String pin) async {
    if (!user.isActive) {
      return const LoginResult(
          success: false, message: 'هذا الحساب موقوف — راجع المدير');
    }

    final locked = _tracker.lockedFor(user.username);
    if (locked > 0) {
      return LoginResult(
        success: false,
        message: 'محاولات كثيرة خاطئة — انتظر $locked ثانية',
        lockedForSeconds: locked,
      );
    }

    final credentials = await _users.credentials(user.username);
    if (credentials == null) {
      return const LoginResult(success: false, message: 'المستخدم غير موجود');
    }

    if (!verifyPin(pin, credentials.hash, credentials.salt)) {
      final lock = _tracker.registerFailure(user.username);
      final remaining = _tracker.maxAttempts - _tracker.failures(user.username);
      if (lock > 0) {
        return LoginResult(
          success: false,
          message: 'محاولات كثيرة خاطئة — انتظر $lock ثانية',
          lockedForSeconds: lock,
        );
      }
      return LoginResult(
        success: false,
        message: 'الرمز غير صحيح — تبقّى $remaining محاولة',
      );
    }

    _tracker.reset(user.username);
    await _users.touchLogin(user.id);
    // Re-read so must_change_pin reflects what was just written.
    final fresh = await _users.byId(user.id) ?? user;
    _current = fresh;
    developer.log('signed in: ${fresh.username} (${fresh.role})',
        name: 'auth_service');

    return LoginResult(
      success: true,
      user: fresh,
      mustChangePin: fresh.mustChangePin,
    );
  }

  Future<void> logout() async {
    _current = null;
    _tracker.clear();
  }

  /// Throw unless the signed-in user holds [capability].
  ///
  /// The UI hides what a role cannot do, but a hidden button is not a
  /// permission check — anything that changes data calls this too.
  void require(String capability) {
    final user = _current;
    if (user == null) {
      throw StateError('no user is signed in');
    }
    if (!user.can(capability)) {
      throw StateError('${user.role} is not allowed to $capability');
    }
  }

  /// Whether the signed-in user holds [capability].
  bool can(String capability) => _current?.can(capability) ?? false;
}
