import 'package:fatoora/features/receipts/data/models/receipt_model.dart';

/// Read-only presentation of the allocation snapshot stored with a receipt.
List<ReceiptInvoiceAllocation> receiptAllocationRows(ReceiptModel receipt) {
  if (receipt.invoiceAllocationDetails.isNotEmpty) {
    return receipt.invoiceAllocationDetails;
  }
  return receipt.invoiceAllocations.entries
      .map(
        (entry) => ReceiptInvoiceAllocation(
          invoiceId: entry.key,
          invoiceNumber: '',
          amount: entry.value,
        ),
      )
      .toList(growable: false);
}

/// Only label a cash destination when the stored receipt records a cash move.
String? receiptCashDestinationKey(ReceiptModel receipt) {
  if (receipt.paymentMethod != 'cash' || receipt.cashMovementIds.isEmpty) {
    return null;
  }
  return switch (receipt.createdByRole) {
    'admin' => 'financial_company_cash',
    'sales_rep' => 'ledger_rep_cash',
    _ => null,
  };
}
