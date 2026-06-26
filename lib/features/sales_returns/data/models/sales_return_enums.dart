enum SalesReturnStatus { draft, confirmed, cancelled }

enum RefundType { creditCustomerBalance, cashRefund }

SalesReturnStatus salesReturnStatusFromValue(Object? value) {
  return switch (value?.toString().trim().toLowerCase()) {
    'confirmed' => SalesReturnStatus.confirmed,
    'cancelled' || 'canceled' => SalesReturnStatus.cancelled,
    _ => SalesReturnStatus.draft,
  };
}

RefundType refundTypeFromValue(Object? value) {
  return switch (value?.toString().trim().toLowerCase()) {
    'cash_refund' || 'cashrefund' => RefundType.cashRefund,
    _ => RefundType.creditCustomerBalance,
  };
}

extension SalesReturnStatusValue on SalesReturnStatus {
  String get value => name;
}

extension RefundTypeValue on RefundType {
  String get value => switch (this) {
    RefundType.creditCustomerBalance => 'credit_customer_balance',
    RefundType.cashRefund => 'cash_refund',
  };
}
