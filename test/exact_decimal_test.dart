import 'package:fatoora/core/finance/exact_decimal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decimal midpoint product uses the same result as trusted posting', () {
    expect(ExactDecimal.multiply(0.41, 4.35), 1.784);
    expect(ExactDecimal.multiply(0.41, -4.35), -1.784);
  });
  test('decimal rounding is symmetric and handles scientific notation', () {
    expect(ExactDecimal.round(1.0005), 1.001);
    expect(ExactDecimal.round(-1.0005), -1.001);
    expect(ExactDecimal.round(1e-7), 0);
    expect(ExactDecimal.round(0.0005), 0.001);
  });
  test('taxes and repeated small amounts retain exact thousandths', () {
    expect(ExactDecimal.percentage(1.784, 16), 0.285);
    expect(ExactDecimal.sum(List.filled(1000, 0.001)), 1);
    expect(ExactDecimal.sum([1.784, -1.784]), 0);
  });
  test('nonfinite and unsupported magnitudes fail closed', () {
    expect(() => ExactDecimal.round(double.nan), throwsFormatException);
    expect(() => ExactDecimal.round(1e20), throwsFormatException);
  });
}
