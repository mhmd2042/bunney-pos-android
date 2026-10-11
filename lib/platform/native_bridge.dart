/// platform/native_bridge.dart — the one door to the Android host.
///
/// Everything Dart cannot do itself goes through here: holding the screen
/// awake, reading device facts, and (from phase 6) the thermal-printer
/// transports. Keeping it to one channel means one place to reason about
/// failures, and one place to stub in tests.
///
/// FAILURE POLICY: a platform call must never take the till down. Every method
/// catches, logs and returns a safe default, because a cashier mid-sale cannot
/// act on a MissingPluginException and should not see one. The caller gets a
/// boolean or a fallback map and carries on.
library;

import 'dart:developer' as developer;

import 'package:flutter/services.dart';

/// The channel name. Must match MainActivity.channelName on the Kotlin side.
const String _channelName = 'com.bunney/native';

/// Facts about the device the app is running on.
class DeviceInfo {
  const DeviceInfo({
    required this.manufacturer,
    required this.model,
    required this.androidRelease,
    required this.sdkInt,
    required this.widthPx,
    required this.heightPx,
    required this.densityDpi,
    required this.widthDp,
    required this.heightDp,
    required this.smallestWidthDp,
    required this.isTablet,
  });

  final String manufacturer;
  final String model;
  final String androidRelease;
  final int sdkInt;
  final int widthPx;
  final int heightPx;
  final int densityDpi;
  final int widthDp;
  final int heightDp;
  final int smallestWidthDp;
  final bool isTablet;

  /// A one-line summary for the about screen.
  String get summary =>
      '$manufacturer $model — Android $androidRelease (API $sdkInt)';

  /// The screen as it is reported to the layout.
  String get screenSummary =>
      '$widthPx×$heightPx px @ $densityDpi dpi → $widthDp×$heightDp dp'
      '${isTablet ? ' · tablet' : ' · phone'}';

  static const DeviceInfo unknown = DeviceInfo(
    manufacturer: '',
    model: '',
    androidRelease: '',
    sdkInt: 0,
    widthPx: 0,
    heightPx: 0,
    densityDpi: 0,
    widthDp: 0,
    heightDp: 0,
    smallestWidthDp: 0,
    isTablet: false,
  );

  factory DeviceInfo.fromMap(Map<Object?, Object?> map) => DeviceInfo(
        manufacturer: '${map['manufacturer'] ?? ''}',
        model: '${map['model'] ?? ''}',
        androidRelease: '${map['androidRelease'] ?? ''}',
        sdkInt: (map['sdkInt'] as num?)?.toInt() ?? 0,
        widthPx: (map['widthPx'] as num?)?.toInt() ?? 0,
        heightPx: (map['heightPx'] as num?)?.toInt() ?? 0,
        densityDpi: (map['densityDpi'] as num?)?.toInt() ?? 0,
        widthDp: (map['widthDp'] as num?)?.toInt() ?? 0,
        heightDp: (map['heightDp'] as num?)?.toInt() ?? 0,
        smallestWidthDp: (map['smallestWidthDp'] as num?)?.toInt() ?? 0,
        isTablet: map['isTablet'] == true,
      );
}

/// The bridge to the Android host.
///
/// A class rather than a set of free functions so a test can substitute it —
/// widget tests have no platform channel, and a screen that calls
/// `NativeBridge.instance.keepScreenOn()` should still render there.
class NativeBridge {
  NativeBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  final MethodChannel _channel;

  static NativeBridge _instance = NativeBridge();

  static NativeBridge get instance => _instance;

  /// Replace the bridge, for tests. Returns the previous one so a test can
  /// restore it.
  static NativeBridge setInstance(NativeBridge bridge) {
    final previous = _instance;
    _instance = bridge;
    return previous;
  }

  /// Hold the screen on, or release it.
  ///
  /// Returns true when the host confirmed it. A false return is not an error
  /// the cashier should see: on a device where the call is unavailable the
  /// screen simply behaves normally.
  Future<bool> keepScreenOn(bool on) async {
    try {
      final result = await _channel
          .invokeMethod<bool>('keepScreenOn', <String, Object?>{'on': on});
      return result ?? false;
    } on MissingPluginException {
      // A widget test, or a build where the host channel is absent.
      return false;
    } on PlatformException catch (e) {
      developer.log('keepScreenOn failed: ${e.message}', name: 'native_bridge');
      return false;
    }
  }

  /// Whether the host currently holds the screen on.
  Future<bool> isScreenOn() async {
    try {
      return await _channel.invokeMethod<bool>('isScreenOn') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Manufacturer, model, Android version and screen metrics.
  Future<DeviceInfo> deviceInfo() async {
    try {
      final map = await _channel.invokeMapMethod<Object?, Object?>('deviceInfo');
      if (map == null) return DeviceInfo.unknown;
      return DeviceInfo.fromMap(map);
    } on MissingPluginException {
      return DeviceInfo.unknown;
    } on PlatformException catch (e) {
      developer.log('deviceInfo failed: ${e.message}', name: 'native_bridge');
      return DeviceInfo.unknown;
    }
  }
}
