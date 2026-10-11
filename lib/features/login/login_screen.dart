/// features/login/login_screen.dart — choose a user, enter a PIN.
///
/// The spec's flow: the cashier taps their card, types four digits, and is in.
/// No username to type, no password to remember — a till is used with one hand
/// while the other is holding a cup.
///
/// The lockout after repeated wrong PINs is the desktop app's rule (5 attempts,
/// 30 seconds) so a café running both behaves the same. The countdown is shown,
/// because a silent disabled keypad reads as a broken app.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../domain/user.dart';
import '../shared/pin_pad.dart';

/// The PIN length for login. The schema allows 4-6; the seed uses 4, and a
/// fixed length lets the dots show how many digits remain.
const int loginPinLength = 4;

/// Wrong PINs before the lockout, matching the desktop app.
const int maxLoginAttempts = 5;

/// How long the lockout lasts.
const int loginLockoutSeconds = 30;

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.users,
    required this.onAuthenticate,
    required this.onLockoutChanged,
  });

  /// The till users, in the order they are shown.
  final List<User> users;

  /// Verify a PIN for a user. Returns the outcome; the screen does not know how
  /// PINs are stored.
  final Future<LoginResult> Function(User user, String pin) onAuthenticate;

  /// Called when the lockout starts or ends, so a caller can react (the desktop
  /// app logs it).
  final void Function(bool locked)? onLockoutChanged;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  User? _selected;
  String _pin = '';
  String _message = '';
  bool _error = false;
  bool _busy = false;
  int _failures = 0;
  int _lockoutLeft = 0;
  Timer? _lockoutTimer;

  bool get _locked => _lockoutLeft > 0;
  bool get _canType => !_locked && !_busy && _selected != null;

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    super.dispose();
  }

  void _select(User user) {
    if (_busy) return;
    setState(() {
      _selected = user;
      _pin = '';
      _message = '';
      _error = false;
    });
  }

  void _digit(String value) {
    if (!_canType || _pin.length >= loginPinLength) return;
    setState(() {
      _pin += value;
      _error = false;
      _message = '';
    });
    // Submit as soon as the last digit lands: one less tap per sale.
    if (_pin.length == loginPinLength) {
      unawaited(_submit());
    }
  }

  void _backspace() {
    if (!_canType || _pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _error = false;
      _message = '';
    });
  }

  Future<void> _submit() async {
    final user = _selected;
    if (user == null || _pin.length != loginPinLength || _busy) return;

    setState(() => _busy = true);
    final result = await widget.onAuthenticate(user, _pin);

    if (!mounted) return;

    if (result.success) {
      setState(() {
        _busy = false;
        _pin = '';
        _message = '';
        _failures = 0;
      });
      // The caller swaps the screen; nothing to do here.
      return;
    }

    setState(() {
      _busy = false;
      _pin = '';
      _error = true;
      _failures++;
      _message = result.message.isNotEmpty
          ? result.message
          : 'الرمز غير صحيح ($_failures/$maxLoginAttempts)';
    });

    if (_failures >= maxLoginAttempts) {
      _startLockout();
    }
  }

  void _startLockout() {
    _lockoutTimer?.cancel();
    setState(() => _lockoutLeft = loginLockoutSeconds);
    widget.onLockoutChanged?.call(true);
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _lockoutLeft--);
      if (_lockoutLeft <= 0) {
        timer.cancel();
        setState(() {
          _failures = 0;
          _message = '';
          _error = false;
        });
        widget.onLockoutChanged?.call(false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = _selected;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Sizes.maxContentWidth),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Sizes.pagePadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: Sizes.gap),
                  Text(
                    AppInfo.nameAr,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: Sizes.gapSmall),
                  Text(
                    selected == null
                        ? 'اختر المستخدم للبدء'
                        : 'أدخل رمز ${selected.fullName}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurface.withValues(alpha: 0.7)),
                  ),
                  const SizedBox(height: Sizes.gap),

                  // The user cards. Wrapped in a scroll area with a bounded
                  // height so a café with many staff does not push the keypad
                  // off the bottom of a phone screen.
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (final user in widget.users)
                            Padding(
                              padding: const EdgeInsets.only(bottom: Sizes.gapSmall),
                              child: _UserCard(
                                user: user,
                                selected: user.id == selected?.id,
                                onTap: () => _select(user),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: Sizes.gap),

                  if (selected != null) ...[
                    PinDots(
                      length: loginPinLength,
                      filled: _pin.length,
                      error: _error,
                    ),
                    if (_locked)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          'تم إيقاف الإدخال مؤقتاً — $_lockoutLeft ثانية',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: scheme.error),
                        ),
                      )
                    else if (_message.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          _message,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: _error ? scheme.error : null),
                        ),
                      )
                    else
                      const SizedBox(height: 6),
                    const SizedBox(height: Sizes.gapSmall),
                    PinPad(
                      onDigit: _digit,
                      onBackspace: _backspace,
                      onSubmit: _submit,
                      enabled: _canType,
                      maxWidth: 340,
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: Sizes.gap * 2),
                      child: Icon(Icons.touch_app_outlined,
                          size: 48, color: scheme.outline),
                    ),

                  const SizedBox(height: Sizes.gap),
                  Text(
                    'يعمل بدون إنترنت',
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

/// One selectable user card: avatar, name, role.
class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.selected,
    required this.onTap,
  });

  final User user;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      label: '${user.fullName} — ${user.roleLabelAr}',
      button: true,
      selected: selected,
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surface,
        borderRadius: BorderRadius.circular(Sizes.radius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Sizes.radius),
          child: Container(
            constraints: const BoxConstraints(minHeight: Sizes.primaryTouchTarget + 16),
            padding: const EdgeInsets.symmetric(
                horizontal: Sizes.pagePadding, vertical: Sizes.gap),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Sizes.radius),
              border: Border.all(
                color: selected ? scheme.primary : scheme.outline,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor:
                      selected ? scheme.primary : scheme.surfaceContainerHighest,
                  child: Text(
                    user.initials,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: selected ? scheme.onPrimary : scheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: Sizes.gap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(user.fullName, style: theme.textTheme.titleMedium),
                      Text(
                        user.roleLabelAr,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle, color: scheme.primary, size: 26),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
