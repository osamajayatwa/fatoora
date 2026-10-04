class OperationalReportFilters {
  const OperationalReportFilters({this.fromDate, this.toDate});

  final DateTime? fromDate;
  final DateTime? toDate;

  DateTime? get fromInclusive => fromDate == null
      ? null
      : DateTime(fromDate!.year, fromDate!.month, fromDate!.day);

  DateTime? get toExclusive => toDate == null
      ? null
      : DateTime(
          toDate!.year,
          toDate!.month,
          toDate!.day,
        ).add(const Duration(days: 1));

  bool get isValid =>
      fromInclusive == null ||
      toExclusive == null ||
      fromInclusive!.isBefore(toExclusive!);
}
