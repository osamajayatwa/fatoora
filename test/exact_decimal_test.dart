import 'dart:convert';
import 'dart:io';

import 'package:fatoora/core/finance/exact_decimal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixture =
      jsonDecode(
            File('test/fixtures/exact_decimal_cases.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  for (final raw in fixture['cases'] as List<dynamic>) {
    final vector = raw as Map<String, dynamic>;
    test('shared vector: ${vector['id']}', () {
      if (vector['error'] == true) {
        expect(() => _evaluate(vector), throwsFormatException);
      } else {
        final actual = _evaluate(vector);
        expect(
          actual,
          actual is num
              ? double.parse(vector['expected'] as String)
              : vector['expected'],
        );
      }
    });
  }
  test('shared contract pins scales, bounds and rounding', () {
    expect(fixture['schemaVersion'], 1);
    expect(fixture['rounding'], 'half_away_from_zero');
    expect(fixture['maxScale'], ExactDecimal.maxScale);
    expect(fixture['maxUnitDigits'], ExactDecimal.maxUnitDigits);
    expect(fixture['legacyScale'], 3);
  });
  test('seeded exact round trips, products, ratios, percentages and sums', () {
    final next = _generator(fixture['propertySeed'] as int);
    for (var i = 0; i < 2000; i++) {
      final sign = next() % 2 == 1 ? BigInt.one : -BigInt.one;
      final value =
          sign *
          (BigInt.from(next()) * BigInt.from(10).pow(next() % 20) +
              BigInt.from(next()));
      final scale = next() % 7;
      final right = BigInt.from(next() % 1000000 + 1);
      final rightScale = next() % 7;
      final outputScale = next() % 7;
      expect(
        ExactDecimal.parseUnits(ExactDecimal.formatUnits(value, scale), scale),
        value,
      );
      expect(ExactDecimal.sumUnits([value, right, -value]), right);
      final exponent = outputScale - scale - rightScale;
      final product = exponent >= 0
          ? value * right * BigInt.from(10).pow(exponent)
          : _rationalRound(value * right, BigInt.from(10).pow(-exponent));
      _expectBounded(
        () => ExactDecimal.multiplyUnits(
          value,
          scale,
          right,
          rightScale,
          outputScale,
        ),
        product,
      );
      final shift = rightScale + outputScale - scale;
      final ratio = _rationalRound(
        value * (shift >= 0 ? BigInt.from(10).pow(shift) : BigInt.one),
        right * (shift < 0 ? BigInt.from(10).pow(-shift) : BigInt.one),
      );
      _expectBounded(
        () => ExactDecimal.divideUnits(
          value,
          scale,
          right,
          rightScale,
          outputScale,
        ),
        ratio,
      );
      final percentage = _rationalRound(
        value * right,
        BigInt.from(100) * BigInt.from(10).pow(rightScale),
      );
      _expectBounded(
        () => ExactDecimal.percentageUnits(value, right, rightScale),
        percentage,
      );
    }
  });
  test(
    'seeded split payments/returns conserve totals and replay intervals',
    () {
      final next = _generator(fixture['propertySeed'] as int);
      for (var i = 0; i < 1000; i++) {
        final total =
            BigInt.from(next()) * (next() % 2 == 1 ? BigInt.one : -BigInt.one);
        final quantity = BigInt.from(next() % 1000000 + 1);
        final cuts = [BigInt.zero, quantity];
        for (var j = 0; j < 16; j++) {
          cuts.add(BigInt.from(next()) % quantity);
        }
        cuts.sort();
        var sum = BigInt.zero;
        for (var j = 1; j < cuts.length; j++) {
          final a = cuts[j - 1], b = cuts[j];
          final amount = ExactDecimal.allocateCumulativeUnits(
            total,
            a,
            b,
            quantity,
          );
          expect(
            amount,
            _rationalRound(total * b, quantity) -
                _rationalRound(total * a, quantity),
          );
          expect(
            ExactDecimal.allocateCumulativeUnits(total, a, b, quantity),
            amount,
          );
          expect(
            total >= BigInt.zero
                ? amount >= BigInt.zero
                : amount <= BigInt.zero,
            isTrue,
          );
          sum += amount;
        }
        expect(sum, total);
        expect(
          ExactDecimal.allocateCumulativeUnits(
                total,
                cuts[2],
                cuts[6],
                quantity,
              ) +
              ExactDecimal.allocateCumulativeUnits(
                total,
                cuts[6],
                cuts[12],
                quantity,
              ),
          ExactDecimal.allocateCumulativeUnits(
            total,
            cuts[2],
            cuts[12],
            quantity,
          ),
        );
      }
    },
  );
  test(
    'legacy prorating remains compatible; cumulative API carries residual',
    () {
      expect(
        ExactDecimal.sum(List.filled(3, ExactDecimal.prorate(0.998, 1, 3))),
        0.999,
      );
      expect(
        ExactDecimal.sumUnits([
          for (var q = 0; q < 3; q++)
            ExactDecimal.allocateCumulativeUnits(
              BigInt.from(998),
              BigInt.from(q),
              BigInt.from(q + 1),
              BigInt.from(3),
            ),
        ]),
        BigInt.from(998),
      );
    },
  );
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
  test('legacy numeric output rejects a lost thousandth within the bound', () {
    expect(
      () => ExactDecimal.fromUnits(BigInt.parse('9007199254740991')),
      throwsFormatException,
    );
    expect(
      () => ExactDecimal.fromUnits(BigInt.parse('-9007199254740991')),
      throwsFormatException,
    );
  });
}

Object _evaluate(Map<String, dynamic> vector) {
  final a = vector['args'] as List<dynamic>;
  BigInt units(int index) => BigInt.parse(a[index] as String);
  switch (vector['op']) {
    case 'parse':
      return ExactDecimal.parseUnits(a[0] as String, a[1] as int).toString();
    case 'format':
      return ExactDecimal.formatUnits(units(0), a[1] as int);
    case 'rescale':
      return ExactDecimal.rescaleUnits(
        units(0),
        a[1] as int,
        a[2] as int,
      ).toString();
    case 'multiply':
      return ExactDecimal.multiplyUnits(
        units(0),
        a[1] as int,
        units(2),
        a[3] as int,
        a[4] as int,
      ).toString();
    case 'divide':
      return ExactDecimal.divideUnits(
        units(0),
        a[1] as int,
        units(2),
        a[3] as int,
        a[4] as int,
      ).toString();
    case 'percentage':
      return ExactDecimal.percentageUnits(
        units(0),
        units(1),
        a[2] as int,
      ).toString();
    case 'sum':
      return ExactDecimal.sumUnits(
        a.map((v) => BigInt.parse(v as String)),
      ).toString();
    case 'allocate':
      return ExactDecimal.allocateCumulativeUnits(
        units(0),
        units(1),
        units(2),
        units(3),
      ).toString();
    case 'legacyRound':
      return ExactDecimal.round(double.parse(a[0] as String));
    case 'legacyNumber':
      return ExactDecimal.fromUnits(units(0));
    default:
      throw StateError('Unknown vector operation ${vector['op']}');
  }
}

int Function() _generator(int seed) {
  var state = seed;
  return () => state = (state * 48271) % 2147483647;
}

// Independent quotient/remainder oracle; remainder keeps the numerator's sign.
BigInt _rationalRound(BigInt numerator, BigInt denominator) {
  final quotient = numerator ~/ denominator;
  final remainder = numerator.remainder(denominator);
  return remainder.abs() * BigInt.two >= denominator
      ? quotient + (numerator.isNegative ? -BigInt.one : BigInt.one)
      : quotient;
}

void _expectBounded(BigInt Function() calculate, BigInt expected) {
  if (expected.abs() > ExactDecimal.maxUnits) {
    expect(calculate, throwsFormatException);
  } else {
    expect(calculate(), expected);
  }
}
