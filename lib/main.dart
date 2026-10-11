/// main.dart — application entry point.
///
/// Kept deliberately thin: the app's states, startup sequence and screens live
/// in app.dart, and everything testable sits behind an injected dependency so it
/// can be exercised without a device.
library;

import 'package:flutter/material.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BunneyApp());
}
