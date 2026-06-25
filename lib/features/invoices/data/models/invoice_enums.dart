enum InvoiceType { regular, electronic }

enum InvoiceStatus {
  draft,
  confirmed,
  pendingSubmit,
  accepted,
  rejected,
  cancelled,
}

enum PaymentType { cash, credit, partial }

enum PaymentStatus { paid, unpaid, partiallyPaid, overdue }

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
    'confirmed' => InvoiceStatus.confirmed,
    'pendingsubmit' ||
    'pending_submit' ||
    'pending-submit' => InvoiceStatus.pendingSubmit,
    'accepted' => InvoiceStatus.accepted,
    'rejected' => InvoiceStatus.rejected,
    'cancelled' || 'canceled' => InvoiceStatus.cancelled,
    _ => InvoiceStatus.draft,
  };
}

PaymentType paymentTypeFromValue(Object? value) {
  final normalized = value?.toString().trim().toLowerCase();
  return switch (normalized) {
    'credit' || 'deferred' => PaymentType.credit,
    'partial' || 'partially_paid' || 'partiallypaid' => PaymentType.partial,
    _ => PaymentType.cash,
  };
}

PaymentStatus paymentStatusFromValue(Object? value) {
  final normalized = value?.toString().trim().toLowerCase();
  return switch (normalized) {
    'unpaid' => PaymentStatus.unpaid,
    'partially_paid' ||
    'partiallypaid' ||
    'partial' => PaymentStatus.partiallyPaid,
    'overdue' => PaymentStatus.overdue,
    _ => PaymentStatus.paid,
  };
}

extension InvoiceTypeValue on InvoiceType {
  String get value => name;
}

extension InvoiceStatusValue on InvoiceStatus {
  String get value => name;
}

extension PaymentTypeValue on PaymentType {
  String get value => name;
}

extension PaymentStatusValue on PaymentStatus {
  String get value => name;
}
