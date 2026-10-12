/// app.dart — the root widget and the boot state machine.
///
/// The app moves through four states, and the order matters:
///
///   booting   → open the encrypted database, seed accounts, hold the screen on
///   activation→ the one-time gate (only on a device that has not been activated)
///   login     → choose a user and type a PIN
///   ready     → the till itself (phase 3 onwards)
///
/// A failure in `booting` is terminal and shown in Arabic: a till whose database
/// will not open cannot sell anything, and a stack trace on a cashier's screen
/// helps nobody.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/constants.dart';
import 'core/theme.dart';
import 'data/database.dart';
import 'data/secure_store.dart';
import 'data/user_repository.dart';
import 'domain/activation.dart';
import 'domain/user.dart';
import 'features/activation/activation_screen.dart';
import 'features/login/login_screen.dart';
import 'platform/native_bridge.dart';
import 'services/auth_service.dart';
import 'services/screen_service.dart';

/// Where the app is in its startup sequence.
enum AppStage { booting, activation, login, ready }

class BunneyApp extends StatefulWidget {
  const BunneyApp({
    super.key,
    this.secureStore,
    this.nativeBridge,
    this.databaseDirectory,
    this.gate,
    this.auth,
    this.screen,
    this.users,
  });

  /// Injected by tests; the real app uses the Keystore and the platform channel.
  final SecureStore? secureStore;
  final NativeBridge? nativeBridge;
  final String? databaseDirectory;

  /// Pre-built services for tests. When any is provided the boot sequence skips
  /// database opening entirely — a widget test has no path_provider channel,
  /// so `getApplicationDocumentsDirectory()` would throw. This keeps the state
  /// machine (booting → activation → login → ready) fully testable.
  final ActivationGate? gate;
  final AuthService? auth;
  final ScreenService? screen;
  final List<User>? users;

  @override
  State<BunneyApp> createState() => _BunneyAppState();
}

class _BunneyAppState extends State<BunneyApp> {
  AppStage _stage = AppStage.booting;
  String? _bootError;

  ActivationGate? _gate;
  AuthService? _auth;
  ScreenService? _screen;
  List<User> _users = const [];
  User? _signedIn;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      // Tests that inject every service skip the database entirely.
      if (widget.gate != null && widget.auth != null && widget.screen != null) {
        _gate = widget.gate;
        _auth = widget.auth;
        _screen = widget.screen;
        _users = widget.users ?? const [];
        // Apply the screen policy just like the real boot does.
        await _screen!.apply();
        if (!mounted) return;
        final activated = await widget.gate!.isActivated();
        if (!mounted) return;
        setState(() {
          _stage = activated ? AppStage.login : AppStage.activation;
        });
        return;
      }

      final store = widget.secureStore ?? await PrefsStore.create();

      final db = await AppDatabase.open(directory: widget.databaseDirectory);

      // Seed the documented accounts on a fresh install. Idempotent: a database
      // that already has users is left alone.
      final users = UserRepository(db);
      await users.ensureDefaultUsers();

      // Hold the till's screen on, per the admin's setting.
      final screen = ScreenService(
        db: db,
        bridge: widget.nativeBridge ?? NativeBridge.instance,
      );
      _screen = screen;
      await screen.apply();

      final gate = ActivationGate(
        readActivated: () async =>
            (await store.read(activationFlagKey)) == 'true',
        writeActivated: (value) =>
            store.write(activationFlagKey, value ? 'true' : 'false'),
      );
      _gate = gate;
      _auth = AuthService(db: db);
      _users = await users.all(activeOnly: true);

      final activated = await gate.isActivated();

      if (!mounted) return;
      setState(() {
        _stage = activated ? AppStage.login : AppStage.activation;
      });
    } on DatabaseException catch (e) {
      if (!mounted) return;
      setState(() {
        _bootError = e.message;
        _stage = AppStage.booting;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bootError = '$e';
        _stage = AppStage.booting;
      });
    }
  }

  Future<LoginResult> _authenticate(User user, String pin) async {
    final result = await _auth!.login(user, pin);
    if (result.success && mounted) {
      setState(() {
        _signedIn = result.user;
        _stage = AppStage.ready;
      });
    }
    return result;
  }

  Future<void> _logout() async {
    await _auth?.logout();
    if (!mounted) return;
    setState(() {
      _signedIn = null;
      _stage = AppStage.login;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppInfo.nameAr,
      debugShowCheckedModeBanner: false,
      theme: buildDarkTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: ThemeMode.dark,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      // Without these the framework's own chrome has no Arabic: it logs
      // "locale ar is not supported by all of its localization delegates" and
      // falls back, which on a device shows Flutter's red error page. The app's
      // own text is Arabic literals; this covers Material's.
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Arabic is the product's language, not a translation of one: the whole
      // tree is mirrored, not just the strings.
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: _buildStage(),
    );
  }

  Widget _buildStage() {
    if (_bootError != null) {
      return _BootErrorScreen(message: _bootError!, onRetry: _boot);
    }

    switch (_stage) {
      case AppStage.booting:
        return const _BootingScreen();
      case AppStage.activation:
        return ActivationScreen(
          gate: _gate!,
          onActivated: () => setState(() => _stage = AppStage.login),
        );
      case AppStage.login:
        return LoginScreen(
          users: _users,
          onAuthenticate: _authenticate,
          onLockoutChanged: (_) {},
        );
      case AppStage.ready:
        return _ReadyScreen(
          user: _signedIn!,
          screen: _screen!,
          onLogout: _logout,
        );
    }
  }
}

class _BootingScreen extends StatelessWidget {
  const _BootingScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_cafe, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: Sizes.gap),
            Text(AppInfo.nameAr, style: theme.textTheme.headlineSmall),
            const SizedBox(height: Sizes.gap),
            const CircularProgressIndicator(),
            const SizedBox(height: Sizes.gap),
            Text('جارٍ تهيئة قاعدة البيانات…', style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _BootErrorScreen extends StatelessWidget {
  const _BootErrorScreen({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Sizes.maxContentWidth),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Sizes.pagePadding),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.error_outline,
                      size: 56, color: theme.colorScheme.error),
                  const SizedBox(height: Sizes.gap),
                  Text('تعذّر تشغيل التطبيق',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall),
                  const SizedBox(height: Sizes.gap),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(Sizes.pagePadding),
                      child: Text(message, style: theme.textTheme.bodyMedium),
                    ),
                  ),
                  const SizedBox(height: Sizes.gap),
                  SizedBox(
                    height: Sizes.primaryTouchTarget,
                    child: FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('إعادة المحاولة'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The signed-in placeholder. The POS replaces this in phase 3.
class _ReadyScreen extends StatelessWidget {
  const _ReadyScreen({
    required this.user,
    required this.screen,
    required this.onLogout,
  });

  final User user;
  final ScreenService screen;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('مرحباً، ${user.fullName}'),
        actions: [
          IconButton(
            onPressed: onLogout,
            icon: const Icon(Icons.logout),
            tooltip: 'خروج',
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Sizes.maxContentWidth),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Sizes.pagePadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(Sizes.pagePadding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 26,
                                backgroundColor: scheme.primary,
                                child: Text(
                                  user.initials,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: scheme.onPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: Sizes.gap),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(user.fullName,
                                        style: theme.textTheme.titleLarge),
                                    Text(user.roleLabelAr,
                                        style: theme.textTheme.bodySmall),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: Sizes.gap),
                          const Divider(),
                          const SizedBox(height: Sizes.gapSmall),
                          _Fact(
                            label: 'الشاشة دائماً',
                            value: screen.enabled ? 'مفعّل' : 'متوقف',
                            icon: Icons.screen_lock_portrait,
                          ),
                          _Fact(
                            label: 'الصلاحيات',
                            value: user.isAdmin
                                ? 'كاملة (مدير)'
                                : 'بيع ووردية (كاشير)',
                            icon: Icons.verified_user_outlined,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: Sizes.gap * 2),
                  Text(
                    'المرحلة ٢ مكتملة — شاشة نقطة البيع في المرحلة ٣',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: theme.textTheme.labelMedium)),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
