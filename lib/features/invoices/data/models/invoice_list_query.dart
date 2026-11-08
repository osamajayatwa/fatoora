import 'package:cloud_firestore/cloud_firestore.dart';

/// Own sales stay the default scope. An explicit customer filter also exposes
/// posted history; Rules authorize the customer's current assignment on every read.
Filter? invoiceReadScopeFilter({
  String representativeUid = '',
  String salesRepId = '',
  String customerId = '',
}) {
  final customer = customerId.trim();
  final rep = representativeUid.trim();
  Filter? scope;
  if (rep.isNotEmpty) {
    scope = Filter('salesRepId', isEqualTo: rep);
    if (customer.isNotEmpty) {
      scope = Filter.or(scope, Filter('financialPosted', isEqualTo: true));
    }
  } else if (salesRepId.trim().isNotEmpty) {
    scope = Filter('salesRepId', isEqualTo: salesRepId.trim());
  }
  if (customer.isNotEmpty) {
    final filter = Filter('customerId', isEqualTo: customer);
    scope = scope == null ? filter : Filter.and(scope, filter);
  }
  return scope;
}

enum InvoiceSortField {
  invoiceNumber,
  invoiceDate,
  customerName,
  salesRepresentativeName,
  invoiceTotal,
  remainingBalance,
  invoiceStatus,
  createdDate,
}

enum InvoiceSortDirection { ascending, descending }

extension InvoiceSortFieldQuery on InvoiceSortField {
  String get firestoreField => switch (this) {
    InvoiceSortField.invoiceNumber => 'invoiceNumberLower',
    InvoiceSortField.invoiceDate => 'invoiceDate',
    InvoiceSortField.customerName => 'customerNameLower',
    InvoiceSortField.salesRepresentativeName => 'salesRepName',
    InvoiceSortField.invoiceTotal => 'grandTotal',
    InvoiceSortField.remainingBalance => 'remainingAmount',
    InvoiceSortField.invoiceStatus => 'invoiceStatus',
    InvoiceSortField.createdDate => 'createdAt',
  };
}

extension InvoiceSortDirectionQuery on InvoiceSortDirection {
  bool get descending => this == InvoiceSortDirection.descending;
}

class InvoiceFilterOption {
  const InvoiceFilterOption({
    required this.id,
    required this.label,
    this.subtitle = '',
  });

  final String id;
  final String label;
  final String subtitle;
}
