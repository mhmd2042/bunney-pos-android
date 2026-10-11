/// core/money.dart — money as integer minor units, and nothing else.
///
/// Ported from the desktop app's `config.py` helpers so both products compute
/// the same totals for the same basket. The rule is absolute: an amount is an
/// `int` in minor units everywhere — database, cart, receipt, report. A double
/// appears only when formatting for display, and never travels back into a
/// calculation.
///
/// Why it matters here specifically: Dart's `double` is IEEE-754 binary, so
/// 0.1 + 0.2 != 0.3 and a 2,500 rial drink summed 40 times can land on
/// 99,999.99999. With YER having no subunit in use, a rounding error of one
/// minor unit is a whole rial of someone's money.
library;

import 'constants.dart';

/// Convert a human-facing amount (int or double) to minor units.
///
/// With `minorUnitsPerMajor == 1` an int is already minor units. A currency
/// with cents would scale by 100 and round half-away-from-zero, which is what
/// a till expects.
int toMinor(num amount) {
  if (MoneyConfig.minorUnitsPerMajor == 1) {
    return amount is int ? amount : amount.round();
  }
  final scaled = amount * MoneyConfig.minorUnitsPerMajor;
  return scaled < 0 ? -((-scaled).round()) : scaled.round();
}

/// Convert minor units back to a major-unit double. DISPLAY ONLY.
double toMajor(int minor) => minor / MoneyConfig.minorUnitsPerMajor;

/// Format minor units for display, e.g. `2,500 ر.ي`.
///
/// The grouping separator is a comma and the digits are Western, matching the
/// desktop app: Arabic-Indic digits (٢٥٠٠) look right in prose but read badly
/// on a till where the cashier is counting notes.
String formatMoney(int minor, {bool symbol = true}) {
  final major = toMajor(minor);
  final text = major == major.roundToDouble()
      ? _groupDigits(major.round().abs().toString())
      : _groupDigits(major.abs().toStringAsFixed(2));
  final sign = minor < 0 ? '-' : '';
  return symbol ? '$sign$text ${MoneyConfig.currencySymbol}' : '$sign$text';
}

/// Group an integer digit string with commas: `2500` -> `2,500`.
String _groupDigits(String digits) {
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// The portion of a tax-inclusive total that is tax.
///
/// Prices are tax-inclusive, so tax is extracted for reporting and never added
/// at checkout. At the default 0% rate this is 0, but the maths is written for
/// any rate so raising the rate later needs no change here.
int extractTaxFromInclusive(int totalMinor, {double? taxRate}) {
  final rate = taxRate ?? MoneyConfig.defaultTaxRate;
  if (rate <= 0) return 0;
  // total = net * (1 + rate)  =>  tax = total - net
  final net = (totalMinor / (1 + rate)).round();
  return totalMinor - net;
}

/// The pre-tax portion of a tax-inclusive total.
int netFromInclusive(int totalMinor, {double? taxRate}) =>
    totalMinor - extractTaxFromInclusive(totalMinor, taxRate: taxRate);

/// Split cash tendered into change owed. Never negative: a short payment is a
/// validation error upstream, not a negative change.
int changeFor(int totalMinor, int paidMinor) {
  final change = paidMinor - totalMinor;
  return change < 0 ? 0 : change;
}

/// Gross margin in minor units for a line, clamped at zero.
///
/// Kept here rather than in a view so the admin report and the menu editor
/// cannot disagree about what "profit" means.
int marginMinor({required int priceMinor, required int costMinor}) {
  final margin = priceMinor - costMinor;
  return margin < 0 ? 0 : margin;
}

/// Margin as a percentage of price, 0 when price is 0.
double marginPercent({required int priceMinor, required int costMinor}) {
  if (priceMinor <= 0) return 0;
  return marginMinor(priceMinor: priceMinor, costMinor: costMinor) /
      priceMinor *
      100;
}
