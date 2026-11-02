import 'package:fatoora/features/expenses/data/models/expense_model.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:fatoora/features/invoices/data/models/invoice_item_snapshot.dart';
import 'package:fatoora/features/invoices/data/models/invoice_model.dart';
import 'package:fatoora/features/receipts/data/models/receipt_model.dart';
import 'package:fatoora/features/sales_returns/data/models/sales_return_item_model.dart';
import 'package:fatoora/features/sales_returns/data/models/sales_return_model.dart';

class OperationalReportData {
  OperationalReportData({
    required this.companyId,
    required List<InvoiceModel> invoices,
    required List<ExpenseModel> expenses,
    required List<ReceiptModel> receipts,
    List<SalesReturnModel> salesReturns = const [],
    Map<String, String> legacyInvoiceNumbers = const {},
    List<String> warnings = const [],
  }) : invoices = List.unmodifiable(invoices),
       expenses = List.unmodifiable(expenses),
       receipts = List.unmodifiable(receipts),
       salesReturns = List.unmodifiable(salesReturns),
       legacyInvoiceNumbers = Map.unmodifiable(legacyInvoiceNumbers),
       warnings = List.unmodifiable(warnings);

  final String companyId;
  final List<InvoiceModel> invoices;
  final List<ExpenseModel> expenses;
  final List<ReceiptModel> receipts;
  final List<SalesReturnModel> salesReturns;
  final Map<String, String> legacyInvoiceNumbers;
  final List<String> warnings;
}

class OperationalSalesRow {
  const OperationalSalesRow({
    required this.invoice,
    required this.item,
    required this.lineNumber,
  });

  final InvoiceModel invoice;
  final InvoiceItemSnapshot item;
  final int lineNumber;
}

class OperationalReceiptRow {
  const OperationalReceiptRow({
    required this.receipt,
    required this.relatedInvoiceNumbers,
    required this.totalAllocatedAmount,
    required this.unallocatedAmount,
  });

  final ReceiptModel receipt;
  final String relatedInvoiceNumbers;
  final double totalAllocatedAmount;
  final double unallocatedAmount;
}

class OperationalSalesReturnRow {
  const OperationalSalesReturnRow({
    required this.salesReturn,
    required this.item,
    required this.lineNumber,
  });

  final SalesReturnModel salesReturn;
  final SalesReturnItemModel item;
  final int lineNumber;
}

bool isOperationalSale(InvoiceModel invoice) =>
    invoice.invoiceStatus == InvoiceStatus.confirmed ||
    invoice.invoiceStatus == InvoiceStatus.accepted;

List<OperationalSalesRow> buildOperationalSalesRows(
  Iterable<InvoiceModel> invoices,
) {
  final rows = <OperationalSalesRow>[];
  for (final invoice in invoices.where(isOperationalSale)) {
    for (var index = 0; index < invoice.items.length; index += 1) {
      rows.add(
        OperationalSalesRow(
          invoice: invoice,
          item: invoice.items[index],
          lineNumber: index + 1,
        ),
      );
    }
  }
  return List.unmodifiable(rows);
}

List<OperationalSalesReturnRow> buildOperationalSalesReturnRows(
  Iterable<SalesReturnModel> salesReturns,
) {
  final rows = <OperationalSalesReturnRow>[];
  for (final salesReturn in salesReturns.where((item) => item.isConfirmed)) {
    for (var index = 0; index < salesReturn.items.length; index += 1) {
      rows.add(
        OperationalSalesReturnRow(
          salesReturn: salesReturn,
          item: salesReturn.items[index],
          lineNumber: index + 1,
        ),
      );
    }
  }
  return List.unmodifiable(rows);
}

List<ReceiptInvoiceAllocation> operationalReceiptAllocations(
  ReceiptModel receipt,
) {
  if (receipt.invoiceAllocationDetails.isEmpty) {
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

  final allocations = <ReceiptInvoiceAllocation>[
    ...receipt.invoiceAllocationDetails,
  ];
  final detailedIds = allocations.map((item) => item.invoiceId).toSet();
  for (final entry in receipt.invoiceAllocations.entries) {
    if (detailedIds.add(entry.key)) {
      allocations.add(
        ReceiptInvoiceAllocation(
          invoiceId: entry.key,
          invoiceNumber: '',
          amount: entry.value,
        ),
      );
    }
  }
  return List.unmodifiable(allocations);
}

Set<String> legacyReceiptInvoiceIds(Iterable<ReceiptModel> receipts) {
  return {
    for (final receipt in receipts)
      for (final allocation in operationalReceiptAllocations(receipt))
        if (allocation.invoiceId.isNotEmpty &&
            allocation.invoiceNumber.trim().isEmpty)
          allocation.invoiceId,
  };
}

String operationalReceiptInvoiceNumbers(
  ReceiptModel receipt,
  Map<String, String> legacyInvoiceNumbers,
) {
  final numbers = <String>[];
  final seen = <String>{};
  for (final allocation in operationalReceiptAllocations(receipt)) {
    final number = allocation.invoiceNumber.trim().isNotEmpty
        ? allocation.invoiceNumber.trim()
        : (legacyInvoiceNumbers[allocation.invoiceId] ?? '').trim();
    if (number.isNotEmpty && seen.add(number)) numbers.add(number);
  }
  return numbers.join(', ');
}

double operationalReceiptAllocatedAmount(ReceiptModel receipt) =>
    receipt.isCancelled
    ? 0
    : operationalReceiptAllocations(
        receipt,
      ).fold(0, (sum, allocation) => sum + allocation.amount);

double operationalReceiptUnallocatedAmount(ReceiptModel receipt) =>
    (receipt.effectiveAmount - operationalReceiptAllocatedAmount(receipt))
        .clamp(0, double.infinity)
        .toDouble();

List<OperationalReceiptRow> buildOperationalReceiptRows(
  Iterable<ReceiptModel> receipts,
  Map<String, String> legacyInvoiceNumbers,
) => List.unmodifiable(
  receipts.map((receipt) {
    final allocated = operationalReceiptAllocatedAmount(receipt);
    return OperationalReceiptRow(
      receipt: receipt,
      relatedInvoiceNumbers: operationalReceiptInvoiceNumbers(
        receipt,
        legacyInvoiceNumbers,
      ),
      totalAllocatedAmount: allocated,
      unallocatedAmount: (receipt.effectiveAmount - allocated)
          .clamp(0, double.infinity)
          .toDouble(),
    );
  }),
);

List<List<String>> chunkOperationalIds(
  Iterable<String> ids, {
  int batchSize = 30,
}) {
  if (batchSize <= 0) throw ArgumentError.value(batchSize, 'batchSize');
  final values = ids.where((id) => id.trim().isNotEmpty).toSet().toList();
  return [
    for (var start = 0; start < values.length; start += batchSize)
      values.sublist(
        start,
        (start + batchSize).clamp(0, values.length).toInt(),
      ),
  ];
}
