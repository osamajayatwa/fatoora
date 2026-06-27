enum QuotationStatus { draft, sent, accepted, rejected, expired, converted }

QuotationStatus quotationStatusFromValue(Object? value) {
  final normalized = value?.toString().trim().toLowerCase();
  return switch (normalized) {
    'sent' => QuotationStatus.sent,
    'accepted' => QuotationStatus.accepted,
    'rejected' => QuotationStatus.rejected,
    'expired' => QuotationStatus.expired,
    'converted' => QuotationStatus.converted,
    _ => QuotationStatus.draft,
  };
}

extension QuotationStatusValue on QuotationStatus {
  String get value => name;
}
