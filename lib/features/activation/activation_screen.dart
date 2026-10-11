/// features/activation/activation_screen.dart — the one-time activation gate.
///
/// Shown the first time the app is opened after installation, and never again
/// once the right code has been entered. Its job is to stop a copied APK from
/// being usable on someone else's tablet — see lib/domain/activation.dart for
/// what that protection honestly is and is not.
///
/// The code is typed on the same keypad the login screen uses, so an operator
/// learns one interaction. It is alphanumeric rather than digits only, so a
/// text field is offered as well for a code read off paper.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants.dart';
import '../../domain/activation.dart';

class ActivationScreen extends StatefulWidget {
  const ActivationScreen({
    super.key,
    required this.gate,
    required this.onActivated,
  });

  final ActivationGate gate;
  final VoidCallback onActivated;

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String _message = '';
  bool _busy = false;
  bool _error = false;
  int _delayLeft = 0;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _delayLeft > 0) return;
    final code = _controller.text;
    if (code.trim().isEmpty) {
      setState(() {
        _error = true;
        _message = 'أدخل رمز التفعيل';
      });
      return;
    }

    setState(() {
      _busy = true;
      _message = '';
      _error = false;
    });

    final result = await widget.gate.submit(code);

    if (!mounted) return;
    if (result.success) {
      // Stop the spinner before handing over. Leaving _busy true means the
      // progress indicator keeps animating if the caller is slow to swap the
      // screen, which reads as a hung app — and makes the widget untestable,
      // because the animation never settles.
      setState(() => _busy = false);
      widget.onActivated();
      return;
    }

    setState(() {
      _busy = false;
      _error = true;
      _message = result.message;
    });

    if (result.isDelayed) {
      _startDelay(result.delaySeconds);
    }
  }

  /// Count down a cooldown after repeated wrong codes.
  ///
  /// A timer rather than a blocking sleep: the screen stays responsive, the
  /// operator can read the message, and the button re-enables itself.
  void _startDelay(int seconds) {
    setState(() => _delayLeft = seconds);
    Future.doWhile(() async {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _delayLeft--);
      return _delayLeft > 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final blocked = _busy || _delayLeft > 0;

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
                  Icon(Icons.lock_outline, size: 56, color: scheme.primary),
                  const SizedBox(height: Sizes.gap),
                  Text(
                    'تفعيل التطبيق',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: Sizes.gapSmall),
                  Text(
                    'يُطلب رمز التفعيل مرة واحدة فقط بعد التثبيت. '
                    'بعد التفعيل تُفتح شاشة الدخول مباشرة في كل مرة.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurface.withValues(alpha: 0.7)),
                  ),
                  const SizedBox(height: Sizes.gap * 1.5),

                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(Sizes.pagePadding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            enabled: !blocked,
                            autofocus: false,
                            textAlign: TextAlign.center,
                            textDirection: TextDirection.ltr,
                            textCapitalization: TextCapitalization.characters,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 3,
                              height: 1.4,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[A-Za-z0-9\-]')),
                              LengthLimitingTextInputFormatter(24),
                            ],
                            decoration: const InputDecoration(
                              hintText: 'XXXX-XXXX',
                              prefixIcon: Icon(Icons.vpn_key_outlined),
                            ),
                            onSubmitted: (_) => _submit(),
                          ),
                          if (_message.isNotEmpty) ...[
                            const SizedBox(height: Sizes.gapSmall),
                            Row(
                              children: [
                                Icon(
                                  _error ? Icons.error_outline : Icons.info_outline,
                                  size: 18,
                                  color: _error ? scheme.error : scheme.onSurface,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _message,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: _error ? scheme.error : null,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: Sizes.gap),
                          SizedBox(
                            height: Sizes.primaryTouchTarget,
                            child: FilledButton.icon(
                              onPressed: blocked ? null : _submit,
                              icon: _busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.check),
                              label: Text(
                                _delayLeft > 0
                                    ? 'انتظر $_delayLeft ثانية'
                                    : (_busy ? 'جارٍ التحقق…' : 'تفعيل'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: Sizes.gap * 1.5),
                  Text(
                    'الرمز موجود في وثائق التسليم أو لدى مالك المقهى.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: Sizes.gapSmall),
                  Text(
                    'التطبيق يعمل بدون إنترنت — التحقق يتم على الجهاز.',
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
