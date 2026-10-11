/// test/features/login_flow_test.dart — the activation gate and login screens
/// render and behave, at every screen size a café device offers.
///
/// The layout rule from the spec is absolute — no clipping, no overlap, no fixed
/// sizes — and the desktop project lost real time to exactly that fault. Flutter
/// reports an overflow as a render exception during a pump, so this catches it
/// without a device.
///
/// The flows themselves matter too: the gate must block until the right code is
/// entered, and the keypad must submit on the last digit rather than needing an
/// extra tap.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bunney_pos_android/core/constants.dart';
import 'package:bunney_pos_android/core/theme.dart';
import 'package:bunney_pos_android/domain/activation.dart';
import 'package:bunney_pos_android/domain/user.dart';
import 'package:bunney_pos_android/features/activation/activation_screen.dart';
import 'package:bunney_pos_android/features/login/login_screen.dart';
import 'package:bunney_pos_android/features/shared/pin_pad.dart';

/// Sizes a café device realistically offers, in logical pixels.
const Map<String, Size> screenSizes = {
  'phone 5.5" portrait': Size(360, 640),
  'phone small portrait': Size(320, 568),
  'phone landscape': Size(640, 360),
  'tablet 7" portrait': Size(600, 960),
  'tablet 10.5" landscape': Size(1280, 800),
};

const admin = User(
    id: 1, username: 'admin', fullName: 'محمد العقيلي', role: Roles.admin);
const cashier = User(
    id: 2, username: 'cashier', fullName: 'سالم', role: Roles.cashier);

/// Render [child] at [size] inside the real app chrome.
Future<void> pumpScreen(WidgetTester tester, Widget child, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      locale: const Locale('ar'),
      builder: (context, inner) => Directionality(
        textDirection: TextDirection.rtl,
        child: inner ?? const SizedBox.shrink(),
      ),
      home: child,
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

ActivationGate gateWith({required bool Function() read, void Function(bool)? write}) {
  return ActivationGate(
    readActivated: () async => read(),
    writeActivated: (value) async => write?.call(value),
    codeHash: activationHashFor('TESTCODE'),
  );
}

void main() {
  group('activation screen renders at every size', () {
    for (final entry in screenSizes.entries) {
      testWidgets('no overflow at ${entry.key}', (tester) async {
        await pumpScreen(
          tester,
          ActivationScreen(
            gate: gateWith(read: () => false),
            onActivated: () {},
          ),
          entry.value,
        );
        expect(tester.takeException(), isNull,
            reason: 'the activation screen overflowed at ${entry.key}');
      });
    }
  });

  group('activation screen behaviour', () {
    testWidgets('a wrong code shows an error and does not activate',
        (tester) async {
      var activated = false;
      await pumpScreen(
        tester,
        ActivationScreen(
          gate: gateWith(read: () => false, write: (v) => activated = v),
          onActivated: () => activated = true,
        ),
        const Size(600, 960),
      );

      await tester.enterText(find.byType(TextField), 'WRONG');
      await tester.tap(find.text('تفعيل'));
      await tester.pumpAndSettle();

      expect(activated, isFalse);
      expect(find.textContaining('غير صحيح'), findsOneWidget);
    });

    testWidgets('the right code activates and calls onActivated',
        (tester) async {
      var callbackFired = false;
      var persisted = false;
      await pumpScreen(
        tester,
        ActivationScreen(
          gate: gateWith(read: () => false, write: (v) => persisted = v),
          onActivated: () => callbackFired = true,
        ),
        const Size(600, 960),
      );

      await tester.enterText(find.byType(TextField), 'TESTCODE');
      await tester.tap(find.text('تفعيل'));
      await tester.pumpAndSettle();

      expect(persisted, isTrue, reason: 'the flag must be written');
      expect(callbackFired, isTrue, reason: 'the caller must be told');
    });

    testWidgets('an empty code is refused without counting as a guess',
        (tester) async {
      final gate = gateWith(read: () => false);
      await pumpScreen(
        tester,
        ActivationScreen(gate: gate, onActivated: () {}),
        const Size(600, 960),
      );

      await tester.tap(find.text('تفعيل'));
      await tester.pumpAndSettle();

      expect(find.text('أدخل رمز التفعيل'), findsOneWidget);
      expect(gate.failures, 0);
    });
  });

  group('login screen renders at every size', () {
    for (final entry in screenSizes.entries) {
      testWidgets('no overflow at ${entry.key}', (tester) async {
        await pumpScreen(
          tester,
          LoginScreen(
            users: const [admin, cashier],
            onAuthenticate: (user, pin) async =>
                const LoginResult(success: false),
            onLockoutChanged: (_) {},
          ),
          entry.value,
        );
        expect(tester.takeException(), isNull,
            reason: 'the login screen overflowed at ${entry.key}');
      });
    }

    testWidgets('no overflow with a user selected (keypad shown)',
        (tester) async {
      // The keypad only appears after a user is tapped, so the populated state
      // needs its own check — that is where a short screen breaks.
      for (final entry in screenSizes.entries) {
        await pumpScreen(
          tester,
          LoginScreen(
            users: const [admin, cashier],
            onAuthenticate: (user, pin) async =>
                const LoginResult(success: false),
            onLockoutChanged: (_) {},
          ),
          entry.value,
        );
        await tester.tap(find.text('محمد العقيلي'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: 'the keypad state overflowed at ${entry.key}');
      }
    });
  });

  group('login screen behaviour', () {
    testWidgets('the keypad appears only after a user is chosen',
        (tester) async {
      await pumpScreen(
        tester,
        LoginScreen(
          users: const [admin, cashier],
          onAuthenticate: (user, pin) async => const LoginResult(success: false),
          onLockoutChanged: (_) {},
        ),
        const Size(600, 960),
      );

      expect(find.byType(PinPad), findsNothing);
      await tester.tap(find.text('سالم'));
      await tester.pumpAndSettle();
      expect(find.byType(PinPad), findsOneWidget);
    });

    testWidgets('submits on the last digit, with no extra tap', (tester) async {
      String? submittedPin;
      await pumpScreen(
        tester,
        LoginScreen(
          users: const [cashier],
          onAuthenticate: (user, pin) async {
            submittedPin = pin;
            return const LoginResult(success: false);
          },
          onLockoutChanged: (_) {},
        ),
        const Size(600, 960),
      );

      await tester.tap(find.text('سالم'));
      await tester.pumpAndSettle();

      for (final digit in ['1', '2', '3', '4']) {
        await tester.tap(find.text(digit));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(submittedPin, '1234',
          reason: 'the fourth digit must submit without pressing a confirm key');
    });

    testWidgets('the dots track how many digits are entered', (tester) async {
      await pumpScreen(
        tester,
        LoginScreen(
          users: const [cashier],
          onAuthenticate: (user, pin) async => const LoginResult(success: false),
          onLockoutChanged: (_) {},
        ),
        const Size(600, 960),
      );

      await tester.tap(find.text('سالم'));
      await tester.pumpAndSettle();

      expect(find.byType(PinDots), findsOneWidget);
      final dots = tester.widget<PinDots>(find.byType(PinDots));
      expect(dots.length, loginPinLength);
      expect(dots.filled, 0);

      await tester.tap(find.text('7'));
      await tester.pump();
      expect(tester.widget<PinDots>(find.byType(PinDots)).filled, 1);
    });

    testWidgets('backspace removes a digit', (tester) async {
      await pumpScreen(
        tester,
        LoginScreen(
          users: const [cashier],
          onAuthenticate: (user, pin) async => const LoginResult(success: false),
          onLockoutChanged: (_) {},
        ),
        const Size(600, 960),
      );

      await tester.tap(find.text('سالم'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('5'));
      await tester.pump();
      expect(tester.widget<PinDots>(find.byType(PinDots)).filled, 1);

      await tester.tap(find.text('⌫'));
      await tester.pump();
      expect(tester.widget<PinDots>(find.byType(PinDots)).filled, 0);
    });

    testWidgets('a wrong PIN shows the remaining attempts', (tester) async {
      await pumpScreen(
        tester,
        LoginScreen(
          users: const [cashier],
          onAuthenticate: (user, pin) async =>
              const LoginResult(success: false, message: ''),
          onLockoutChanged: (_) {},
        ),
        const Size(600, 960),
      );

      await tester.tap(find.text('سالم'));
      await tester.pumpAndSettle();
      for (final digit in ['9', '9', '9', '9']) {
        await tester.tap(find.text(digit));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(find.textContaining('1/$maxLoginAttempts'), findsOneWidget);
    });

    testWidgets('locks out after the maximum wrong attempts', (tester) async {
      var lockoutStarted = false;
      await pumpScreen(
        tester,
        LoginScreen(
          users: const [cashier],
          onAuthenticate: (user, pin) async =>
              const LoginResult(success: false, message: ''),
          onLockoutChanged: (locked) {
            if (locked) lockoutStarted = true;
          },
        ),
        const Size(600, 960),
      );

      await tester.tap(find.text('سالم'));
      await tester.pumpAndSettle();

      for (var attempt = 0; attempt < maxLoginAttempts; attempt++) {
        for (final digit in ['9', '9', '9', '9']) {
          await tester.tap(find.text(digit));
          await tester.pump();
        }
        await tester.pumpAndSettle();
      }

      expect(lockoutStarted, isTrue);
      expect(find.textContaining('إيقاف الإدخال'), findsOneWidget);

      // Stop the periodic timer so the test does not complain about it.
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('touch targets meet the accessibility floor', () {
    testWidgets('every keypad key is at least ${Sizes.primaryTouchTarget}dp',
        (tester) async {
      await pumpScreen(
        tester,
        const Scaffold(
          body: Center(
            child: PinPad(
              onDigit: _noop,
              onBackspace: _noop2,
              onSubmit: _noop3,
            ),
          ),
        ),
        const Size(600, 960),
      );

      // 12 keys: 1-9, backspace, 0, submit.
      final keys = find.byType(InkWell);
      expect(keys, findsNWidgets(12));
      for (var i = 0; i < 12; i++) {
        final size = tester.getSize(keys.at(i));
        expect(size.height, greaterThanOrEqualTo(Sizes.primaryTouchTarget),
            reason: 'key $i is ${size.height}dp tall');
      }
    });
  });
}

void _noop(String _) {}
void _noop2() {}
void _noop3() {}
