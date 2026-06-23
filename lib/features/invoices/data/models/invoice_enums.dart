enum InvoiceType { regular, electronic }

enum InvoiceStatus { draft, pendingSubmit, accepted, rejected, cancelled }

InvoiceType invoiceTypeFromValue(Object? value) {
  final normalized = value?.toString().trim().toLowerCase();
  return switch (normalized) {
    'electronic' || 'tax' || 'jofotara' => InvoiceType.electronic,
    _ => InvoiceType.regular,
  };
}

InvoiceStatus invoiceStatusFromValue(Object? value) {
  final normalized = value?.toString().trim().toLowerCase();
  return switch (normalized) {
    'pendingsubmit' ||
    'pending_submit' ||
    'pending-submit' => InvoiceStatus.pendingSubmit,
    'accepted' => InvoiceStatus.accepted,
    'rejected' => InvoiceStatus.rejected,
    'cancelled' || 'canceled' => InvoiceStatus.cancelled,
    _ => InvoiceStatus.draft,
  };
}

extension InvoiceTypeValue on InvoiceType {
  String get value => name;
}

extension InvoiceStatusValue on InvoiceStatus {
  String get value => name;
}
