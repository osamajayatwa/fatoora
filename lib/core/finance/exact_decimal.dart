/// Exact explicit-scale units plus compatible three-decimal numeric adapters.
/// New unit APIs never pass amounts through double. Backend posting remains
/// authoritative; the legacy adapters retain their existing input rounding.
class ExactDecimal {
  const ExactDecimal._();

  static const int maxScale = 6;
  static const int maxUnitDigits = 30;
  static final BigInt maxUnits =
      BigInt.from(10).pow(maxUnitDigits) - BigInt.one;
  static final RegExp _decimalPattern = RegExp(r'^-?[0-9]+(?:\.[0-9]+)?$');

  static void _validateScale(int scale) {
    if (scale < 0 || scale > maxScale) {
      throw const FormatException('Unsupported decimal scale.');
    }
  }

  static BigInt _checkedUnits(BigInt value) {
    if (value.abs() > maxUnits) {
      throw const FormatException(
        'Decimal units exceed the supported exact range.',
      );
    }
    return value;
  }

  // Called only with validated scales/operands; powers are bounded by 12.
  static BigInt _shiftUnits(BigInt value, int exponent) {
    final factor = BigInt.from(10).pow(exponent.abs());
    return _checkedUnits(
      exponent >= 0 ? value * factor : divideRounded(value, factor),
    );
  }

  /// Strict ASCII decimal, no rounding. Reject whitespace, exponent notation
  /// and excess fractional digits, including zeros. Leading zeros normalize.
  /// Serialize returned units with toString(), keeping the scale separately.
  static BigInt parseUnits(String value, int scale) {
    _validateScale(scale);
    if (value.length > 64) {
      throw const FormatException('Invalid exact decimal string.');
    }
    final match = _decimalPattern.firstMatch(value);
    if (match == null || match.end != value.length) {
      throw const FormatException('Invalid exact decimal string.');
    }
    final negative = value.startsWith('-');
    final parts = (negative ? value.substring(1) : value).split('.');
    final fractional = parts.length == 2 ? parts[1] : '';
    if (fractional.length > scale) {
      throw const FormatException('Decimal input exceeds the declared scale.');
    }
    final units = BigInt.parse(parts[0] + fractional.padRight(scale, '0'));
    return _checkedUnits(negative ? -units : units);
  }

  /// Fixed-scale output with a separate bound on unit magnitude.
  static String formatUnits(BigInt value, int scale) {
    _validateScale(scale);
    _checkedUnits(value);
    final digits = value.abs().toString().padLeft(scale + 1, '0');
    final magnitude = scale == 0
        ? digits
        : '${digits.substring(0, digits.length - scale)}.'
              '${digits.substring(digits.length - scale)}';
    return value.isNegative ? '-$magnitude' : magnitude;
  }

  /// Explicit conversion; reducing scale rounds half away from zero.
  static BigInt rescaleUnits(BigInt value, int fromScale, int toScale) {
    _validateScale(fromScale);
    _validateScale(toScale);
    return _shiftUnits(_checkedUnits(value), toScale - fromScale);
  }

  /// Independent quantity/price scales; round the final product once.
  static BigInt multiplyUnits(
    BigInt left,
    int leftScale,
    BigInt right,
    int rightScale,
    int resultScale,
  ) {
    _validateScale(leftScale);
    _validateScale(rightScale);
    _validateScale(resultScale);
    return _shiftUnits(
      _checkedUnits(left) * _checkedUnits(right),
      resultScale - leftScale - rightScale,
    );
  }

  /// Exact ratio at an explicit result scale; denominator must be positive.
  static BigInt divideUnits(
    BigInt numerator,
    int numeratorScale,
    BigInt denominator,
    int denominatorScale,
    int resultScale,
  ) {
    _validateScale(numeratorScale);
    _validateScale(denominatorScale);
    _validateScale(resultScale);
    _checkedUnits(numerator);
    _checkedUnits(denominator);
    if (denominator <= BigInt.zero) {
      throw const FormatException('Decimal denominator must be positive.');
    }
    final exponent = denominatorScale + resultScale - numeratorScale;
    final factor = BigInt.from(10).pow(exponent.abs());
    return _checkedUnits(
      divideRounded(
        exponent >= 0 ? numerator * factor : numerator,
        exponent >= 0 ? denominator : denominator * factor,
      ),
    );
  }

  /// 16 at percentScale 0 means 16%; output keeps the amount's scale.
  /// Business callers still validate eligible tax/discount rates and signs.
  static BigInt percentageUnits(
    BigInt amount,
    BigInt percent,
    int percentScale,
  ) {
    _validateScale(percentScale);
    return _checkedUnits(
      divideRounded(
        _checkedUnits(amount) * _checkedUnits(percent),
        BigInt.from(100) * BigInt.from(10).pow(percentScale),
      ),
    );
  }

  /// Same-scale/currency sum; the caller validates shared unit metadata.
  /// Cancelling intermediates may be wider; the final result must fit.
  static BigInt sumUnits(Iterable<BigInt> values) => _checkedUnits(
    values.fold(BigInt.zero, (sum, value) => sum + _checkedUnits(value)),
  );

  /// Increment for a cumulative [previousQuantity, nextQuantity] interval.
  /// Quantities share one scale. Original-total rounded endpoints conserve
  /// the last residual; callers persist/authorize consumed ranges atomically.
  static BigInt allocateCumulativeUnits(
    BigInt total,
    BigInt previousQuantity,
    BigInt nextQuantity,
    BigInt totalQuantity,
  ) {
    _checkedUnits(total);
    _checkedUnits(previousQuantity);
    _checkedUnits(nextQuantity);
    _checkedUnits(totalQuantity);
    if (totalQuantity <= BigInt.zero ||
        previousQuantity < BigInt.zero ||
        nextQuantity < previousQuantity ||
        nextQuantity > totalQuantity) {
      throw const FormatException('Invalid cumulative allocation range.');
    }
    return _checkedUnits(
      divideRounded(total * nextQuantity, totalQuantity) -
          divideRounded(total * previousQuantity, totalQuantity),
    );
  }

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
    final result = value.toDouble() / 1000;
    if (units(result) != value) {
      throw const FormatException(
        'Numeric decimal conversion would lose units.',
      );
    }
    return result;
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
