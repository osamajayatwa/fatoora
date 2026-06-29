import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:fatoora/features/invoices/data/models/invoice_model.dart';
import 'package:fatoora/features/sales_returns/data/models/sales_return_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy invoices receive safe payment and return defaults', () {
    final invoice = InvoiceModel.fromMap({
      'id': 'invoice-1',
      'invoiceStatus': 'confirmed',
      'grandTotal': 500,
      'paidAmount': 200,
      'remainingAmount': 300,
    });

    expect(invoice.returnStatus, InvoiceReturnStatus.none);
    expect(invoice.returnedTotal, 0);
    expect(invoice.returnInvoiceIds, isEmpty);
    expect(invoice.receiptIds, isEmpty);
    expect(invoice.effectiveOutstandingAmount, 300);
  });

  test('legacy returns keep their document id as return invoice id', () {
    final salesReturn = SalesReturnModel.fromMap({
      'id': 'return-1',
      'returnNumber': 'RET-2026-000001',
      'grandTotal': 100,
    });

    expect(salesReturn.returnInvoiceId, 'return-1');
    expect(salesReturn.totalDiscount, 0);
    expect(salesReturn.receivableReduction, 0);
    expect(salesReturn.customerCreditAmount, 0);
    expect(salesReturn.cashRefundAmount, 0);
  });
}
