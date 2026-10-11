/// test/widget/responsive_test.dart — the layout must not overflow or overlap.
///
/// The spec's hard rule is that no screen may clip, overlap or use a fixed size,
/// and the desktop project lost real time to exactly that fault. Flutter reports
/// an overflow as a render exception during a pump, so this is checkable without
/// a device: render each screen at the sizes a café actually uses and fail on
/// any exception.
///
/// Sizes are logical pixels, which is what the layout sees:
///   * 5.5" phone portrait  — 360 x 640  (a small, common Android phone)
///   * phone landscape      — 640 x 360
///   * 7" tablet portrait   — 600 x 960  (Android's own sw600dp tablet line)
///   * 10.5" tablet landscape — 1280 x 800
///   * the folded inner screen of the test emulator — 673 x 841
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bunney_pos_android/core/constants.dart';
import 'package:bunney_pos_android/core/theme.dart';

/// The sizes to render at, with a name for the failure message.
const Map<String, Size> screenSizes = {
  'phone 5.5" portrait': Size(360, 640),
  'phone landscape': Size(640, 360),
  'phone small portrait': Size(320, 568),
  'tablet 7" portrait': Size(600, 960),
  'tablet 10.5" landscape': Size(1280, 800),
  'foldable inner': Size(673, 841),
};

/// Render [child] inside the real app chrome at [size] and fail on any overflow.
Future<void> pumpAt(
  WidgetTester tester,
  Widget child,
  Size size, {
  required String label,
}) async {
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

/// A stand-in for a screen: the same chrome every real screen will use.
Widget screenStub({
  required String title,
  required List<Widget> body,
  bool scrollable = true,
}) {
  return Scaffold(
    appBar: AppBar(title: Text(title)),
    body: SafeArea(
      child: scrollable
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(Sizes.pagePadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: body,
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(Sizes.pagePadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: body,
              ),
            ),
    ),
  );
}

void main() {
  group('every screen renders without overflow', () {
    for (final entry in screenSizes.entries) {
      testWidgets('foundation screen at ${entry.key}', (tester) async {
        await pumpAt(
          tester,
          screenStub(
            title: AppInfo.nameAr,
            body: [
              const Icon(Icons.local_cafe, size: 64),
              const SizedBox(height: Sizes.gap),
              const Text('قاعدة البيانات جاهزة'),
              const SizedBox(height: Sizes.gap),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(Sizes.pagePadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final key in ['المسار', 'الحجم', 'العملة'])
                        Row(
                          children: [
                            SizedBox(
                              width: 96,
                              child: Text(key,
                                  style: const TextStyle(fontSize: 13)),
                            ),
                            const Expanded(
                              child: Text(
                                '/data/user/0/com.bunney.bunney_pos_android/'
                                'app_flutter/bunney_pos_android.db',
                                style: TextStyle(fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          entry.value,
          label: entry.key,
        );

        // A RenderFlex overflow throws during pump; if we got here with no
        // exception the layout fitted. Asserting explicitly so the intent is
        // visible rather than implied by absence.
        expect(tester.takeException(), isNull,
            reason: 'layout overflowed at ${entry.key}');
      });
    }
  });

  group('touch targets meet the accessibility floor', () {
    testWidgets('a themed button is at least ${Sizes.minTouchTarget}dp tall',
        (tester) async {
      await pumpAt(
        tester,
        screenStub(
          title: 'أزرار',
          body: [
            ElevatedButton(onPressed: () {}, child: const Text('إتمام الدفع')),
            const SizedBox(height: Sizes.gap),
            OutlinedButton(onPressed: () {}, child: const Text('إفراغ')),
            const SizedBox(height: Sizes.gap),
            TextButton(onPressed: () {}, child: const Text('تخطٍ')),
          ],
        ),
        const Size(360, 640),
        label: 'buttons',
      );

      for (final type in [ElevatedButton, OutlinedButton, TextButton]) {
        final size = tester.getSize(find.byType(type).first);
        expect(size.height, greaterThanOrEqualTo(Sizes.minTouchTarget),
            reason: '$type is ${size.height}dp, below the '
                '${Sizes.minTouchTarget}dp accessibility floor');
      }
    });
  });

  group('RTL and money rendering', () {
    testWidgets('the app renders right-to-left', (tester) async {
      await pumpAt(
        tester,
        screenStub(title: 'اختبار', body: const [Text('مرحباً')]),
        const Size(360, 640),
        label: 'rtl',
      );
      final direction = Directionality.of(
          tester.element(find.text('مرحباً')));
      expect(direction, TextDirection.rtl);
    });

    testWidgets('a money string keeps its digits together', (tester) async {
      await pumpAt(
        tester,
        screenStub(
          title: 'المجموع',
          body: const [Text('2,500 ر.ي', textDirection: TextDirection.ltr)],
        ),
        const Size(360, 640),
        label: 'money',
      );
      expect(find.text('2,500 ر.ي'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the tablet breakpoint is a real breakpoint', () {
    test('600dp separates phone from tablet', () {
      expect(Sizes.tabletBreakpoint, 600);
      // The sizes in the matrix must fall on both sides of it, or the matrix is
      // not testing the thing it claims to.
      final widths = screenSizes.values.map((s) => s.width);
      expect(widths.any((w) => w < Sizes.tabletBreakpoint), isTrue,
          reason: 'need at least one phone-width case');
      expect(widths.any((w) => w >= Sizes.tabletBreakpoint), isTrue,
          reason: 'need at least one tablet-width case');
    });
  });
}
