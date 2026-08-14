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
