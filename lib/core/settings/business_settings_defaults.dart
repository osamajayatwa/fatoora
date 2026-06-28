class BusinessSettingsDefaults {
  const BusinessSettingsDefaults._();

  static final RegExp _prefixPattern = RegExp(r'^[A-Z0-9]{1,10}$');

  static String prefix(String value, String fallback) {
    final normalized = value.trim().toUpperCase();
    return _prefixPattern.hasMatch(normalized) ? normalized : fallback;
  }

  static String documentNumber({
    required String prefix,
    required int year,
    required int sequence,
  }) {
    return '$prefix-$year-${sequence.toString().padLeft(6, '0')}';
  }

  static DateTime invoiceDueDate(DateTime invoiceDate, int defaultDueDays) {
    if (defaultDueDays <= 0) return invoiceDate;
    return invoiceDate.add(Duration(days: defaultDueDays));
  }

  static double taxPercent({
    required double? existingTaxPercent,
    required double defaultTaxPercent,
  }) {
    if (existingTaxPercent != null && existingTaxPercent.isFinite) {
      return existingTaxPercent;
    }
    if (!defaultTaxPercent.isFinite) return 0;
    return defaultTaxPercent.clamp(0, 100).toDouble();
  }

  static double minimumStock(double value) {
    if (!value.isFinite || value < 0) return 0;
    return value;
  }

  static String warehouseId(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? 'default_warehouse' : normalized;
  }

  static String prefilledNote({
    required String currentNote,
    required String defaultNote,
  }) {
    return currentNote.trim().isEmpty ? defaultNote.trim() : currentNote;
  }

  static String inputNumber(double value) {
    if (!value.isFinite) return '0';
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }
}
