/// test/app_boot_test.dart — the app must reach a usable screen.
///
/// The device showed Flutter's red error page on first launch, which means an
/// exception was thrown while building the widget tree — and a widget test
/// catches exactly that, without a device or a 10-minute Gradle build.
///
/// This drives the real BunneyApp through its boot with a fake secure store and
/// a fake bridge, then asserts a real screen appears rather than an error.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bunney_pos_android/app.dart';
import 'package:bunney_pos_android/core/constants.dart';
import 'package:bunney_pos_android/data/database.dart';
import 'package:bunney_pos_android/data/secure_store.dart';
import 'package:bunney_pos_android/domain/activation.dart';
import 'package:bunney_pos_android/domain/user.dart';
import 'package:bunney_pos_android/features/activation/activation_screen.dart';
import 'package:bunney_pos_android/platform/native_bridge.dart';
import 'package:bunney_pos_android/services/auth_service.dart';
import 'package:bunney_pos_android/services/screen_service.dart';

/// A bridge that answers without a platform channel.
class FakeBridge extends NativeBridge {
  FakeBridge() : super(channel: const MethodChannel('test'));

  final List<bool> screenCalls = [];

  @override
  Future<bool> keepScreenOn(bool on) async {
    screenCalls.add(on);
    return true;
  }

  @override
  Future<bool> isScreenOn() async => screenCalls.isNotEmpty && screenCalls.last;

  @override
  Future<DeviceInfo> deviceInfo() async => const DeviceInfo(
        manufacturer: 'samsung',
        model: 'SM-T285',
        androidRelease: '7.1.2',
        sdkInt: 25,
        widthPx: 800,
        heightPx: 1280,
        densityDpi: 213,
        widthDp: 601,
        heightDp: 962,
        smallestWidthDp: 600,
        isTablet: true,
      );
}

const admin = User(
    id: 1, username: 'admin', fullName: 'محمد العقيلي', role: Roles.admin);
const cashier = User(
    id: 2, username: 'cashier', fullName: 'سالم', role: Roles.cashier);

/// Pump the app with a pre-built set of services, then pump enough frames for
/// the async boot to settle.
Future<void> pumpApp(
  WidgetTester tester, {
  required SecureStore store,
  required FakeBridge bridge,
  required bool activated,
}) async {
  await tester.pumpWidget(
    BunneyApp(
      secureStore: store,
      nativeBridge: bridge,
      gate: ActivationGate(
        readActivated: () async => activated,
        writeActivated: (_) async {},
      ),
      auth: AuthService(db: AppDatabase.forTesting()),
      screen: ScreenService(db: AppDatabase.forTesting(), bridge: bridge),
      users: const [admin, cashier],
    ),
  );

  // The boot is async: pump until the tree settles.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('the app reaches a real screen', () {
    testWidgets('a fresh install shows the activation gate, not an error',
        (tester) async {
      final bridge = FakeBridge();
      await pumpApp(tester,
          store: MemoryStore(), bridge: bridge, activated: false);

      expect(tester.takeException(), isNull,
          reason: 'the boot threw while building the tree');
      expect(find.byType(ActivationScreen), findsOneWidget,
          reason: 'a fresh install must show the activation gate');
    });

    testWidgets('the screen-always-on policy is applied at boot',
        (tester) async {
      final bridge = FakeBridge();
      await pumpApp(tester,
          store: MemoryStore(), bridge: bridge, activated: false);

      expect(bridge.screenCalls, [true],
          reason: 'the till must hold its screen on from the first frame');
    });

    testWidgets('an already-activated device goes straight to login',
        (tester) async {
      final bridge = FakeBridge();
      await pumpApp(tester,
          store: MemoryStore({activationFlagKey: 'true'}),
          bridge: bridge,
          activated: true);

      expect(tester.takeException(), isNull);
      expect(find.byType(ActivationScreen), findsNothing,
          reason: 'an activated device must not see the gate again');
    });
  });

  group('the boot survives a hostile environment', () {
    testWidgets('a secure store that throws does not crash the tree',
        (tester) async {
      final bridge = FakeBridge();
      await pumpApp(tester,
          store: ThrowingStore(), bridge: bridge, activated: false);

      expect(tester.takeException(), isNull,
          reason: 'a failing store must not produce a red error page');
    });
  });
}

/// A store whose reads always fail, standing in for a Keystore that was
/// invalidated by an OS upgrade or a device restore.
class ThrowingStore implements SecureStore {
  @override
  Future<String?> read(String key) async => throw StateError('keystore gone');

  @override
  Future<void> write(String key, String value) async =>
      throw StateError('keystore gone');

  @override
  Future<void> delete(String key) async =>
      throw StateError('keystore gone');

  @override
  Future<bool> contains(String key) async => false;
}
