/// Three-decimal arithmetic shared by client previews; the backend recalculates
/// authoritative postings. Integer intermediates preserve decimal midpoint rules.
class ExactDecimal {
  const ExactDecimal._();

  static BigInt divideRounded(BigInt numerator, BigInt denominator) {
    if (denominator <= BigInt.zero) {
      throw const FormatException('Invalid decimal denominator.');
    }
    final sign = numerator.isNegative ? -BigInt.one : BigInt.one;
    return sign *
        ((numerator.abs() + denominator ~/ BigInt.two) ~/ denominator);
  }

  static BigInt units(double value) {
    if (!value.isFinite) throw const FormatException('Invalid decimal value.');
    final parts = value.abs().toString().toLowerCase().split('e');
    final decimal = parts.first.split('.');
    final fractional = decimal.length == 2 ? decimal[1] : '';
    final digits = BigInt.parse(decimal.first + fractional);
    final power =
        (parts.length == 2 ? int.parse(parts[1]) : 0) - fractional.length + 3;
    final scaled = power >= 0
        ? digits * BigInt.from(10).pow(power)
        : divideRounded(digits, BigInt.from(10).pow(-power));
    return value < 0 ? -scaled : scaled;
  }

  static double fromUnits(BigInt value) {
    final maximum = BigInt.from(9007199254740991);
    if (value.abs() > maximum) {
      throw const FormatException('Decimal exceeds the supported exact range.');
    }
    return value.toDouble() / 1000;
  }

  static double round(double value) => fromUnits(units(value));

  static double multiply(double left, double right) =>
      fromUnits(divideRounded(units(left) * units(right), BigInt.from(1000)));

  static double percentage(double amount, double percent) => fromUnits(
    divideRounded(units(amount) * units(percent), BigInt.from(100000)),
  );

  static double prorate(double amount, double quantity, double totalQuantity) =>
      fromUnits(
        divideRounded(units(amount) * units(quantity), units(totalQuantity)),
      );

  static double sum(Iterable<double> values) =>
      fromUnits(values.fold(BigInt.zero, (sum, value) => sum + units(value)));
}
