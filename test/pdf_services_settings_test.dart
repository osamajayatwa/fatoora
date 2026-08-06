import 'dart:convert';

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

  test('receipt PDF supports mixed Arabic and English dynamic content', () async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ar');
    final now = DateTime(2026, 7, 12);
    final customer = const InvoiceCustomerSnapshot(
      id: 'customer-mixed',
      name: 'شركة حلول المياه Advanced Water Solutions',
      phone: '+962 79 123 4567',
      address: 'Amman Industrial Area - المنطقة الصناعية',
      taxNumber: 'TAX-FDSS-100',
      nationalNumber: 'NAT-50FCL16-75',
      city: 'Amman - عمان',
    );
    final receipt = ReceiptModel(
      id: 'receipt-mixed',
      companyId: _PdfFixture.companyId,
      receiptNumber: 'REC-2026-FDSS-001',
      receiptDate: now,
      customerId: customer.id,
      customerSnapshot: customer,
      amount: 40,
      paymentMethod: 'cash',
      notes:
          'Payment for مضخة غاطسة FDSS 4SP-10 and model 50FCL16-75 - دفعة نقدية.',
      salesRepId: 'rep-1',
      salesRepName: 'Ahmad Sales - أحمد المبيعات',
      createdByUid: 'rep-1',
      createdByName: 'Ahmad Sales - أحمد المبيعات',
      createdByRole: 'sales_rep',
      customerTransactionIds: const [],
      cashMovementIds: const [],
      createdAt: now,
      updatedAt: now,
    );
    final configuration = BusinessPdfConfiguration(
      companySettings: CompanySettingsModel.defaults.copyWith(
        name: 'مؤسسة الجياطوة التجارية | Jayatwa Trading Establishment',
        phone: '+962 6 000 0000',
        address: 'Amman - عمان',
      ),
      pdfSettings: PdfSettingsModel.defaults.copyWith(
        receiptFooterText: 'Thank you | شكرا لتعاملكم معنا',
      ),
      userPreferences: UserPreferencesModel.defaults,
      localization: AppPdfLocalization.forLanguage('ar'),
    );

    final bytes = await ReceiptPdfService.build(
      receipt,
      configuration: configuration,
    );

    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test(
    'long bilingual business documents paginate without truncation',
    () async {
      await initializeDateFormatting('en');
      await initializeDateFormatting('ar');
      final fixture = _PdfFixture();
      final longQuotation = fixture.quotation.copyWith(
        items: List.generate(
          140,
          (index) => fixture.quotation.items.single.copyWith(
            itemId: 'quotation-item-$index',
            itemName:
                'مضخة صناعية عالية الكفاءة / Industrial pump model $index',
            itemCode: 'PUMP-$index',
          ),
        ),
      );
      final longReturn = fixture.salesReturn.copyWith(
        items: List.generate(
          140,
          (index) => fixture.salesReturn.items.single.copyWith(
            itemId: 'return-item-$index',
            itemName: 'مرتجع مضخة / Returned pump model $index',
            originalInvoiceItemId: 'invoice-line-$index',
          ),
        ),
      );
      final longTransactions = List.generate(
        560,
        (index) => CustomerTransactionModel(
          id: 'transaction-$index',
          companyId: _PdfFixture.companyId,
          customerId: fixture.customer.id,
          customerName: fixture.customer.name,
          transactionType: index.isEven ? 'invoice' : 'receipt',
          sourceCollection: index.isEven ? 'invoices' : 'receipts',
          sourceId: 'source-$index',
          sourceNumber: 'REF-$index',
          transactionDate: fixture.now.add(Duration(minutes: index)),
          debitAmount: index.isEven ? 1.001 : 0,
          creditAmount: index.isOdd ? 0.501 : 0,
          balanceAfter: 10 + (index * 0.5),
          notes: 'حركة حساب تجريبية / Account movement $index',
          createdByUid: 'admin-1',
          createdByName: 'Admin',
          createdByRole: 'admin',
          salesRepId: 'rep-1',
          salesRepName: 'مندوب المبيعات / Sales representative',
          createdAt: fixture.now.add(Duration(minutes: index)),
        ),
      );
      final longMovements = List.generate(
        520,
        (index) => CashMovementModel(
          id: 'cash-$index',
          companyId: _PdfFixture.companyId,
          salesRepId: 'rep-1',
          salesRepName: 'مندوب المبيعات / Sales representative',
          type: index.isEven ? 'receipt_cash' : 'expense',
          movementType: index.isEven ? 'receipt' : 'expense',
          direction: index.isEven ? 'in' : 'out',
          amount: index.isEven ? 1.001 : 0.501,
          referenceId: 'source-$index',
          referenceNumber: 'CASH-$index',
          sourceCollection: index.isEven ? 'receipts' : 'expenses',
          sourceId: 'source-$index',
          sourceNumber: 'CASH-$index',
          customerId: fixture.customer.id,
          customerName: fixture.customer.name,
          date: fixture.now.add(Duration(minutes: index)),
          notes: 'حركة نقدية / Cash movement $index',
          createdByUid: 'admin-1',
          createdByName: 'Admin',
          createdByRole: 'admin',
          createdAt: fixture.now.add(Duration(minutes: index)),
        ),
      );
      final longReceipt = ReceiptModel(
        id: fixture.receipt.id,
        companyId: fixture.receipt.companyId,
        receiptNumber: fixture.receipt.receiptNumber,
        receiptDate: fixture.receipt.receiptDate,
        customerId: fixture.receipt.customerId,
        customerSnapshot: fixture.receipt.customerSnapshot,
        amount: 90,
        paymentMethod: fixture.receipt.paymentMethod,
        notes: 'توزيع دفعة طويلة / Long allocation receipt',
        salesRepId: fixture.receipt.salesRepId,
        salesRepName: fixture.receipt.salesRepName,
        createdByUid: fixture.receipt.createdByUid,
        createdByName: fixture.receipt.createdByName,
        createdByRole: fixture.receipt.createdByRole,
        customerTransactionIds: fixture.receipt.customerTransactionIds,
        cashMovementIds: fixture.receipt.cashMovementIds,
        invoiceAllocationDetails: List.generate(
          90,
          (index) => ReceiptInvoiceAllocation(
            invoiceId: 'invoice-$index',
            invoiceNumber: 'INV-2026-${index.toString().padLeft(6, '0')}',
            amount: 1,
          ),
        ),
        resultingCustomerBalance: 12.345,
        createdAt: fixture.receipt.createdAt,
        updatedAt: fixture.receipt.updatedAt,
      );

      final outputs = <List<int>>[];
      outputs.add(
        await QuotationPdfService.build(
          longQuotation,
          configuration: fixture.configuration,
        ),
      );
      outputs.add(
        await SalesReturnPdfService.build(
          longReturn,
          configuration: fixture.configuration,
        ),
      );
      outputs.add(
        await CustomerStatementPdfService.build(
          customer: fixture.customer,
          transactions: longTransactions,
          fromDate: fixture.now,
          toDate: fixture.now.add(const Duration(days: 1)),
          openingBalance: 10,
          totalDebit: 280.28,
          totalCredit: 140.28,
          finalBalance: 150,
          configuration: fixture.configuration,
        ),
      );
      outputs.add(
        await CashReportPdfService.build(
          snapshot: FinancialCashSnapshot(
            movements: longMovements,
            openingBalance: 10,
            closingBalance: 140,
            cashInHand: 140,
            companyCash: 140,
            totalIn: 260.26,
            totalOut: 130.26,
            cashBySalesRep: const [],
          ),
          fromDate: fixture.now,
          toDate: fixture.now.add(const Duration(days: 1)),
          salesRepFilterLabel: 'الكل / All',
          configuration: fixture.configuration,
        ),
      );
      outputs.add(
        await ReceiptPdfService.build(
          longReceipt,
          configuration: fixture.configuration,
        ),
      );

      for (final bytes in outputs) {
        expect(String.fromCharCodes(bytes.take(4)), '%PDF');
        expect(_pageCount(bytes), greaterThan(1));
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

int _pageCount(List<int> bytes) {
  return RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(bytes)).length;
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
