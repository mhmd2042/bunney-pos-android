/// features/shared/pin_pad.dart — the numeric keypad.
///
/// Used by the activation gate, the login screen and the PIN-change dialog, so
/// there is one keypad and one place its sizing rules live.
///
/// The keys are built from a grid rather than a column of rows so the pad fills
/// whatever width it is given, and each key is at least Sizes.primaryTouchTarget
/// tall — a cashier types a PIN dozens of times a shift, and a 40dp key is the
/// difference between fast and irritating.
library;

import 'package:flutter/material.dart';

import '../../core/constants.dart';

/// The digits, in the order a phone keypad shows them (1-9 then 0).
const List<String> padDigits = ['1', '2', '3', '4', '5', '6', '7', '8', '9'];

class PinPad extends StatelessWidget {
  const PinPad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.onSubmit,
    this.enabled = true,
    this.submitLabel = 'دخول',
    this.maxWidth = 380,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  /// Called by the confirm key. Omitted when the pad is only for entry.
  final VoidCallback? onSubmit;
  final bool enabled;
  final String submitLabel;

  /// The pad is capped so the keys do not become absurdly wide on a tablet in
  /// landscape — a 200dp-wide "1" key is slower to hit than a 90dp one.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1-9 in a 3x3 grid.
            for (var row = 0; row < 3; row++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    for (var column = 0; column < 3; column++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: _Key(
                            label: padDigits[row * 3 + column],
                            onPressed: enabled
                                ? () => onDigit(padDigits[row * 3 + column])
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _Key(
                        label: '⌫',
                        onPressed: enabled ? onBackspace : null,
                        isAction: true,
                        semanticLabel: 'حذف',
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _Key(
                        label: '0',
                        onPressed: enabled ? () => onDigit('0') : null,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: onSubmit == null
                          ? const SizedBox.shrink()
                          : _Key(
                              label: submitLabel,
                              onPressed: enabled ? onSubmit : null,
                              isPrimary: true,
                              isAction: true,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.label,
    required this.onPressed,
    this.isPrimary = false,
    this.isAction = false,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final bool isAction;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      label: semanticLabel ?? label,
      button: true,
      child: SizedBox(
        // The accessibility floor, and tall enough that a hurried tap lands.
        height: Sizes.primaryTouchTarget + 8,
        child: Material(
          color: isPrimary
              ? scheme.primary
              : (isAction ? scheme.surfaceContainerHighest : scheme.surface),
          borderRadius: BorderRadius.circular(Sizes.radiusSmall),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(Sizes.radiusSmall),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Sizes.radiusSmall),
                border: Border.all(color: scheme.outline),
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: isAction ? 20 : 26,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                  color: isPrimary
                      ? scheme.onPrimary
                      : (onPressed == null
                          ? scheme.onSurface.withValues(alpha: 0.4)
                          : scheme.onSurface),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The dots that show how many digits have been entered.
///
/// A dot per position, never the digits themselves: a PIN typed on a counter
/// tablet is visible to whoever is standing in front of it.
class PinDots extends StatelessWidget {
  const PinDots({
    super.key,
    required this.length,
    required this.filled,
    this.error = false,
  });

  final int length;
  final int filled;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '$filled من $length',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < filled
                      ? (error ? scheme.error : scheme.primary)
                      : Colors.transparent,
                  border: Border.all(
                    color: error ? scheme.error : scheme.outline,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
