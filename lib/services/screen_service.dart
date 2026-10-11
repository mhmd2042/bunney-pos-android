/// services/screen_service.dart — the till's screen policy.
///
/// A point-of-sale screen must not sleep. The cashier looks away to make a
/// drink and the next customer is faced with a lock screen and a PIN prompt —
/// which is both slow and a reason to disable the lock entirely, making the
/// device less safe overall.
///
/// The policy is a setting (`screen_always_on`, default on) rather than a
/// constant, because a café running the app on a personal phone may want the
/// normal behaviour back.
///
/// The flag is applied to the app's window, so Android releases it when the app
/// leaves the foreground: no wakelock permission, and no battery drain while
/// the till is not on screen.
library;

import 'dart:developer' as developer;

import '../data/database.dart';
import '../platform/native_bridge.dart';

/// The settings key. Lives in the `settings` table with every other preference.
const String screenAlwaysOnKey = 'screen_always_on';

/// The seeded default: a till is always-on unless an admin says otherwise.
const String screenAlwaysOnDefault = '1';

class ScreenService {
  /// `db` is public because it is what the caller has; the field keeps the same
  /// name so an initializing formal can be used.
  ScreenService({required this.db, NativeBridge? bridge})
      : bridge = bridge ?? NativeBridge.instance;

  final AppDatabase db;
  final NativeBridge bridge;

  bool _applied = false;
  bool _enabled = true;

  /// Whether the policy currently holds the screen on.
  bool get enabled => _enabled;

  /// Whether the host confirmed the flag.
  bool get applied => _applied;

  /// Read the setting and apply it. Call once, after the database is open and
  /// the first frame is on screen.
  Future<bool> apply() async {
    final raw = await db.setting(screenAlwaysOnKey,
        fallback: screenAlwaysOnDefault);
    return setEnabled(raw == '1', persist: false);
  }

  /// Turn the policy on or off, optionally persisting the choice.
  Future<bool> setEnabled(bool on, {bool persist = true}) async {
    _enabled = on;
    if (persist) {
      await db.setSetting(screenAlwaysOnKey, on ? '1' : '0');
    }
    _applied = await bridge.keepScreenOn(on);
    if (!_applied) {
      // Expected in a widget test and on a desktop build; worth a line in the
      // log because on a real till it means the setting is not taking effect.
      developer.log(
        'screen-always-on was not applied by the host (on=$on)',
        name: 'screen_service',
      );
    }
    return _applied;
  }

  /// Read the current state back from the host, rather than trusting the
  /// cached value. Used by the settings screen to show the truth.
  Future<bool> verify() async => bridge.isScreenOn();
}
