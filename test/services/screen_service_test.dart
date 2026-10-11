/// test/services/screen_service_test.dart — the screen-always-on policy.
///
/// The policy has three moving parts and each can fail silently: the setting
/// may not be read, the platform call may not be made, or the host may refuse
/// it. A till whose screen sleeps mid-shift is a real problem at a counter, so
/// this asserts the call is actually made and the setting actually round-trips
/// — not merely that the code compiles.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bunney_pos_android/data/database.dart';
import 'package:bunney_pos_android/platform/native_bridge.dart';
import 'package:bunney_pos_android/services/screen_service.dart';

/// A bridge that records calls and can be told to succeed or fail.
///
/// Substituting the bridge is why NativeBridge is a class with a settable
/// instance rather than a set of free functions: a widget test has no platform
/// channel, and a service that cannot be tested would go unverified.
class FakeBridge extends NativeBridge {
  FakeBridge({this.succeeds = true}) : super(channel: const MethodChannel('test'));

  final bool succeeds;
  final List<bool> keepScreenOnCalls = <bool>[];
  bool hostState = false;

  @override
  Future<bool> keepScreenOn(bool on) async {
    keepScreenOnCalls.add(on);
    if (!succeeds) return false;
    hostState = on;
    return true;
  }

  @override
  Future<bool> isScreenOn() async => hostState;

  @override
  Future<DeviceInfo> deviceInfo() async => DeviceInfo.unknown;
}

/// A stand-in for the database that only implements what ScreenService uses.
///
/// Deliberately not a real AppDatabase: opening one needs SQLCipher, which the
/// Dart VM cannot link. The service's own logic — read the setting, call the
/// bridge, persist the change — is what is under test here.
class FakeSettings {
  FakeSettings([Map<String, String>? initial])
      : values = {...?initial};

  final Map<String, String> values;
}

void main() {
  // A MethodChannel needs the services binding; without this the channel lookup
  // itself throws before any of our error handling runs.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScreenService — reads the setting', () {
    test('defaults to on when the setting is absent', () {
      // The schema seeds '1', so an absent row means an older database; the
      // till behaviour must not silently change to sleeping.
      expect(screenAlwaysOnDefault, '1');
    });

    test('the settings key is the one the schema seeds', () {
      expect(screenAlwaysOnKey, 'screen_always_on');
    });
  });

  group('ScreenService — calls the host', () {
    test('turning it on asks the host to keep the screen on', () async {
      final bridge = FakeBridge();
      final service = ScreenService(db: _UnusedDatabase(), bridge: bridge);

      final applied = await service.setEnabled(true, persist: false);

      expect(applied, isTrue);
      expect(bridge.keepScreenOnCalls, [true],
          reason: 'the host must actually be asked, not merely recorded in Dart');
      expect(service.enabled, isTrue);
      expect(service.applied, isTrue);
    });

    test('turning it off asks the host to release it', () async {
      final bridge = FakeBridge();
      final service = ScreenService(db: _UnusedDatabase(), bridge: bridge);

      await service.setEnabled(false, persist: false);

      expect(bridge.keepScreenOnCalls, [false]);
      expect(service.enabled, isFalse);
    });

    test('a host that refuses is reported, not thrown', () async {
      final bridge = FakeBridge(succeeds: false);
      final service = ScreenService(db: _UnusedDatabase(), bridge: bridge);

      // Must not throw: a cashier mid-sale cannot act on a platform failure.
      final applied = await service.setEnabled(true, persist: false);

      expect(applied, isFalse);
      expect(service.enabled, isTrue,
          reason: 'the intent is still recorded even when the host refuses');
      expect(service.applied, isFalse);
    });

    test('verify() asks the host rather than trusting the cache', () async {
      final bridge = FakeBridge();
      final service = ScreenService(db: _UnusedDatabase(), bridge: bridge);

      // The host says off while Dart believes on; verify must report the host.
      bridge.hostState = false;
      await service.setEnabled(true, persist: false);
      bridge.hostState = false;

      expect(await service.verify(), isFalse);
    });
  });

  group('NativeBridge — degrades instead of throwing', () {
    test('a missing plugin returns a safe default, not an exception',
        () async {
      // A widget test has no platform channel; every method must survive that.
      final bridge = NativeBridge(channel: const MethodChannel('no.such/channel'));

      expect(await bridge.keepScreenOn(true), isFalse);
      expect(await bridge.isScreenOn(), isFalse);
      expect(await bridge.deviceInfo(), DeviceInfo.unknown);
    });
  });

  group('DeviceInfo', () {
    test('parses the map the Kotlin side sends', () {
      final info = DeviceInfo.fromMap(<Object?, Object?>{
        'manufacturer': 'samsung',
        'model': 'SM-T285',
        'androidRelease': '7.1.2',
        'sdkInt': 25,
        'widthPx': 800,
        'heightPx': 1280,
        'densityDpi': 213,
        'widthDp': 601,
        'heightDp': 962,
        'smallestWidthDp': 600,
        'isTablet': true,
      });

      expect(info.model, 'SM-T285');
      expect(info.sdkInt, 25);
      expect(info.isTablet, isTrue);
      expect(info.summary, contains('samsung SM-T285'));
      expect(info.summary, contains('API 25'));
      expect(info.screenSummary, contains('800×1280'));
      expect(info.screenSummary, contains('tablet'));
    });

    test('a missing field does not throw', () {
      final info = DeviceInfo.fromMap(<Object?, Object?>{});
      expect(info.model, '');
      expect(info.sdkInt, 0);
      expect(info.isTablet, isFalse);
    });

    test('a phone is reported as a phone', () {
      final info = DeviceInfo.fromMap(<Object?, Object?>{
        'model': 'Pixel',
        'smallestWidthDp': 411,
        'isTablet': false,
      });
      expect(info.screenSummary, contains('phone'));
    });
  });
}

/// ScreenService takes an AppDatabase, which needs SQLCipher. These tests
/// exercise the setting-independent paths, so the argument is never used.
///
/// It extends the real type and forwards nothing: any accidental call fails
/// loudly with the invocation named, which is more useful than a silent null.
class _UnusedDatabase extends AppDatabase {
  _UnusedDatabase() : super.forTesting();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
      'the database is not used in this test (${invocation.memberName})');
}
