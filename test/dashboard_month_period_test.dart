import 'package:fatoora/features/financial/data/models/dashboard_month_period.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes a selected date to its complete calendar month', () {
    final period = DashboardMonthPeriod.fromMonth(DateTime(2026, 7, 28));

    expect(period.month, DateTime(2026, 7));
    expect(period.start, DateTime(2026, 7));
    expect(period.end, DateTime(2026, 7, 31, 23, 59, 59, 999));
  });

  test('handles leap-year February boundaries', () {
    final period = DashboardMonthPeriod.fromMonth(DateTime(2024, 2, 15));

    expect(period.end, DateTime(2024, 2, 29, 23, 59, 59, 999));
    expect(period.contains(DateTime(2024, 2, 29, 12)), isTrue);
    expect(period.contains(DateTime(2024, 3)), isFalse);
  });

  test('identifies whether a date belongs to the selected month', () {
    final period = DashboardMonthPeriod.fromMonth(DateTime(2026, 7));

    expect(period.isSameMonth(DateTime(2026, 7, 31)), isTrue);
    expect(period.isSameMonth(DateTime(2026, 8)), isFalse);
  });
}
