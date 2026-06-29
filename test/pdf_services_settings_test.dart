import 'package:fatoora/core/pdf/app_pdf_localization.dart';
import 'package:fatoora/core/pdf/business_pdf_configuration.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';
import 'package:fatoora/features/customers/data/models/customer_transaction_model.dart';
import 'package:fatoora/features/customers/data/services/customer_statement_pdf_service.dart';
import 'package:fatoora/features/financial/data/models/cash_movement_model.dart';
import 'package:fatoora/features/financial/data/models/financial_dashboard_snapshot.dart';
import 'package:fatoora/features/financial/data/services/cash_report_pdf_service.dart';
import 'package:fatoora/features/invoices/data/models/invoice_customer_snapshot.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:fatoora/features/invoices/data/models/invoice_item_snapshot.dart';
import 'package:fatoora/features/invoices/data/models/invoice_model.dart';
import 'package:fatoora/features/invoices/data/services/invoice_pdf_service.dart';
import 'package:fatoora/features/quotations/data/models/quotation_item_model.dart';
import 'package:fatoora/features/quotations/data/models/quotation_model.dart';
import 'package:fatoora/features/quotations/data/models/quotation_status.dart';
import 'package:fatoora/features/quotations/data/services/quotation_pdf_service.dart';
import 'package:fatoora/features/receipts/data/models/receipt_model.dart';
import 'package:fatoora/features/receipts/data/services/receipt_pdf_service.dart';
import 'package:fatoora/features/sales_returns/data/models/sales_return_enums.dart';
import 'package:fatoora/features/sales_returns/data/models/sales_return_item_model.dart';
import 'package:fatoora/features/sales_returns/data/models/sales_return_model.dart';
import 'package:fatoora/features/sales_returns/data/services/sales_return_pdf_service.dart';
import 'package:fatoora/features/settings/data/models/company_settings_model.dart';
import 'package:fatoora/features/settings/data/models/pdf_settings_model.dart';
import 'package:fatoora/features/settings/data/models/user_preferences_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all six PDF services build with Settings configuration', () async {
    await initializeDateFormatting('en');
    final fixture = _PdfFixture();
    final outputs = await Future.wait([
      InvoicePdfService.build(
        fixture.invoice,
        configuration: fixture.configuration,
      ),
      ReceiptPdfService.build(
        fixture.receipt,
        configuration: fixture.configuration,
      ),
      SalesReturnPdfService.build(
        fixture.salesReturn,
        configuration: fixture.configuration,
      ),
      QuotationPdfService.build(
        fixture.quotation,
        configuration: fixture.configuration,
      ),
      CustomerStatementPdfService.build(
        customer: fixture.customer,
        transactions: [fixture.transaction],
        fromDate: fixture.now,
        toDate: fixture.now,
        openingBalance: 0,
        totalDebit: 22.04,
        totalCredit: 0,
        finalBalance: 22.04,
        configuration: fixture.configuration,
      ),
      CashReportPdfService.build(
        snapshot: fixture.cashSnapshot,
        fromDate: fixture.now,
        toDate: fixture.now,
        salesRepFilterLabel: 'All',
        configuration: fixture.configuration,
      ),
    ]);

    expect(outputs, hasLength(6));
    for (final bytes in outputs) {
      expect(bytes.length, greaterThan(1000));
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    }
  });
}

class _PdfFixture {
  _PdfFixture() {
    invoice = InvoiceModel(
      id: 'invoice-1',
      companyId: companyId,
      invoiceNumber: 'INV-2026-000001',
      invoiceType: InvoiceType.regular,
      invoiceStatus: InvoiceStatus.confirmed,
      paymentType: PaymentType.partial,
      paymentStatus: PaymentStatus.partiallyPaid,
      hasReceivedPayment: true,
      invoiceDate: now,
      dueDate: now,
      createdAt: now,
      updatedAt: now,
      createdByUid: 'admin-1',
      createdByName: 'Admin',
      createdByRole: 'admin',
      salesRepId: 'rep-1',
      salesRepName: 'Sales Rep',
      customerId: customerSnapshot.id,
      customerSnapshot: customerSnapshot,
      items: const [invoiceItem],
      subtotal: 20,
      totalDiscount: 1,
      totalTax: 3.04,
      grandTotal: 22.04,
      paidAmount: 10,
      remainingAmount: 12.04,
      notes: 'Document note',
      paymentMethod: 'partial',
      isLocked: false,
      financialPosted: true,
      financialPostedByUid: 'admin-1',
      financialPostedByName: 'Admin',
      customerTransactionIds: const [],
      cashMovementIds: const [],
      inventoryPosted: true,
      inventoryPostedByUid: 'admin-1',
      inventoryPostedByName: 'Admin',
      inventoryMovementIds: const [],
      searchKeywords: const [],
      customerNameLower: '',
      itemNamesLower: const [],
      invoiceNumberLower: '',
      dateString: '2026-06-27',
    );
    receipt = ReceiptModel(
      id: 'receipt-1',
      companyId: companyId,
      receiptNumber: 'REC-2026-000001',
      receiptDate: now,
      customerId: customerSnapshot.id,
      customerSnapshot: customerSnapshot,
      amount: 10,
      paymentMethod: 'cash',
      notes: 'Receipt note',
      salesRepId: 'rep-1',
      salesRepName: 'Sales Rep',
      createdByUid: 'rep-1',
      createdByName: 'Sales Rep',
      createdByRole: 'sales_rep',
      customerTransactionIds: const [],
      cashMovementIds: const [],
      createdAt: now,
      updatedAt: now,
    );
    quotation = QuotationModel(
      id: 'quotation-1',
      companyId: companyId,
      quotationNumber: 'QUO-2026-000001',
      quotationDate: now,
      validUntil: now.add(const Duration(days: 14)),
      customerId: customerSnapshot.id,
      customerSnapshot: customerSnapshot,
      items: [QuotationItemModel.fromInvoiceItem(invoiceItem)],
      subtotal: 20,
      totalDiscount: 1,
      totalTax: 3.04,
      grandTotal: 22.04,
      notes: 'Quotation note',
      terms: 'Document terms',
      status: QuotationStatus.sent,
      salesRepId: 'rep-1',
      salesRepName: 'Sales Rep',
      createdByUid: 'rep-1',
      createdByName: 'Sales Rep',
      createdByRole: 'sales_rep',
      convertedInvoiceId: '',
      convertedInvoiceNumber: '',
      createdAt: now,
      updatedAt: now,
      searchKeywords: const [],
    );
    salesReturn = SalesReturnModel(
      id: 'return-1',
      companyId: companyId,
      returnNumber: 'RET-2026-000001',
      originalInvoiceId: invoice.id,
      originalInvoiceNumber: invoice.invoiceNumber,
      customerId: customerSnapshot.id,
      customerSnapshot: customerSnapshot,
      items: const [
        SalesReturnItemModel(
          itemId: 'item-1',
          itemName: 'Test item',
          itemCode: 'ITEM-1',
          unit: 'pcs',
          returnedQuantity: 1,
          unitPrice: 10,
          taxPercent: 16,
          subtotal: 10,
          taxAmount: 1.6,
          total: 11.6,
          originalInvoiceItemId: 'item-1',
        ),
      ],
      subtotal: 10,
      totalTax: 1.6,
      grandTotal: 11.6,
      refundType: RefundType.creditCustomerBalance,
      returnDate: now,
      reason: 'Returned item',
      status: SalesReturnStatus.confirmed,
      salesRepId: 'rep-1',
      salesRepName: 'Sales Rep',
      createdByUid: 'rep-1',
      createdByName: 'Sales Rep',
      createdByRole: 'sales_rep',
      financialPosted: true,
      inventoryPosted: true,
      stockMovementIds: const [],
      customerTransactionIds: const [],
      cashMovementIds: const [],
      createdAt: now,
      updatedAt: now,
    );
  }

  static const companyId = 'default_company';
  final DateTime now = DateTime(2026, 6, 27);
  static const customerSnapshot = InvoiceCustomerSnapshot(
    id: 'customer-1',
    name: 'Example Customer',
    phone: '0790000000',
    address: 'Amman, Jordan',
    taxNumber: '',
    nationalNumber: '',
    city: 'Amman',
  );
  static const invoiceItem = InvoiceItemSnapshot(
    itemId: 'item-1',
    itemName: 'Test item',
    itemCode: 'ITEM-1',
    unit: 'pcs',
    quantity: 2,
    unitPrice: 10,
    discount: 1,
    taxPercent: 16,
    subtotal: 20,
    taxAmount: 3.04,
    total: 22.04,
  );
  final BusinessPdfConfiguration configuration = BusinessPdfConfiguration(
    companySettings: CompanySettingsModel.defaults.copyWith(
      name: 'Configured Company',
    ),
    pdfSettings: PdfSettingsModel.defaults.copyWith(
      invoiceFooterText: 'Invoice footer',
      quotationTerms: 'Default terms',
      receiptFooterText: 'Receipt footer',
      statementFooterText: 'Statement footer',
      defaultNotes: 'Default note',
    ),
    userPreferences: UserPreferencesModel.defaults.copyWith(
      defaultInvoiceNote: 'Personal invoice note',
      defaultReceiptNote: 'Personal receipt note',
    ),
    localization: AppPdfLocalization.forLanguage('en'),
  );
  final CustomerModel customer = CustomerModel(
    id: 'customer-1',
    companyId: companyId,
    name: 'Example Customer',
    phone: '0790000000',
    addressText: 'Amman, Jordan',
    city: 'Amman',
    area: '',
    notes: '',
    active: true,
    createdByUid: 'admin-1',
    createdByName: 'Admin',
    createdByRole: 'admin',
    createdAt: DateTime(2026, 6, 27),
    updatedAt: DateTime(2026, 6, 27),
    currentBalance: 22.04,
    totalSales: 22.04,
    totalPaid: 0,
    searchKeywords: const [],
    nameLower: 'example customer',
    phoneNormalized: '0790000000',
    cityLower: 'amman',
    areaLower: '',
  );
  final CustomerTransactionModel transaction = CustomerTransactionModel(
    id: 'transaction-1',
    companyId: companyId,
    customerId: 'customer-1',
    customerName: 'Example Customer',
    transactionType: 'invoice',
    sourceCollection: 'invoices',
    sourceId: 'invoice-1',
    sourceNumber: 'INV-2026-000001',
    transactionDate: DateTime(2026, 6, 27),
    debitAmount: 22.04,
    creditAmount: 0,
    balanceAfter: 22.04,
    notes: 'Invoice sale',
    createdByUid: 'admin-1',
    createdByName: 'Admin',
    createdByRole: 'admin',
    salesRepId: 'rep-1',
    salesRepName: 'Sales Rep',
    createdAt: DateTime(2026, 6, 27),
  );
  final FinancialCashSnapshot cashSnapshot = FinancialCashSnapshot(
    movements: [
      CashMovementModel(
        id: 'cash-1',
        companyId: companyId,
        salesRepId: 'rep-1',
        salesRepName: 'Sales Rep',
        type: 'invoice_cash',
        movementType: 'invoice_payment',
        direction: 'in',
        amount: 10,
        referenceId: 'invoice-1',
        referenceNumber: 'INV-2026-000001',
        sourceCollection: 'invoices',
        sourceId: 'invoice-1',
        sourceNumber: 'INV-2026-000001',
        customerId: 'customer-1',
        customerName: 'Example Customer',
        date: DateTime(2026, 6, 27),
        notes: 'Cash sale',
        createdByUid: 'rep-1',
        createdByName: 'Sales Rep',
        createdByRole: 'sales_rep',
        createdAt: DateTime(2026, 6, 27),
      ),
    ],
    cashInHand: 10,
    totalIn: 10,
    totalOut: 0,
    cashBySalesRep: const [],
  );

  late final InvoiceModel invoice;
  late final ReceiptModel receipt;
  late final QuotationModel quotation;
  late final SalesReturnModel salesReturn;
}
