class DashboardMonthPeriod {
  DashboardMonthPeriod._(this.month, this.start, this.end);

  factory DashboardMonthPeriod.fromMonth(DateTime value) {
    final month = DateTime(value.year, value.month);
    return DashboardMonthPeriod._(
      month,
      month,
      DateTime(
        value.year,
        value.month + 1,
      ).subtract(const Duration(milliseconds: 1)),
    );
  }

  factory DashboardMonthPeriod.current([DateTime? now]) {
    return DashboardMonthPeriod.fromMonth(now ?? DateTime.now());
  }

  final DateTime month;
  final DateTime start;
  final DateTime end;

  bool contains(DateTime value) =>
      !value.isBefore(start) && !value.isAfter(end);

  bool isSameMonth(DateTime value) =>
      month.year == value.year && month.month == value.month;
}
