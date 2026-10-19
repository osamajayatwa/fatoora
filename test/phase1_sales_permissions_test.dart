import 'package:fatoora/features/customers/data/models/customer_model.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:fatoora/features/invoices/data/models/invoice_item_snapshot.dart';
import 'package:fatoora/features/invoices/data/services/invoice_totals_service.dart';
import 'package:fatoora/features/quotations/data/models/quotation_item_model.dart';
import 'package:fatoora/features/quotations/data/models/quotation_model.dart';
import 'package:fatoora/features/quotations/data/models/quotation_status.dart';
import 'package:fatoora/features/quotations/data/repositories/quotation_repository.dart';
import 'package:fatoora/features/rep_inventory/data/models/rep_inventory_enums.dart';
import 'package:fatoora/features/settings/data/models/document_settings_model.dart';
import 'package:fatoora/features/shared/business/business_user_context.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = InvoiceTotalsService();

  test('custom-only, catalog-only and mixed invoices use trusted precision', () {
    for (final lines in [
      [_line(custom: true, price: 10)],
      [_line(price: 10)],
      [_line(price: 0), _line(custom: true, price: 10)],
    ]) {
      expect(service.validateInvoice(lines).grandTotal, 10);
    }
    // Same rounding sequence as trusted/totals.ts, including amount boundaries.
    final totals = service.validateInvoice([
      _line(
        price: 1.23456,
      ).copyWith(quantity: 1.23456, discount: 0.1234, taxPercent: 16),
    ]);
    expect(totals.items.single.quantity, 1.235);
    expect(totals.items.single.unitPrice, 1.235);
    expect(totals.subtotal, 1.525);
    expect(totals.totalTax, 0.224);
    expect(totals.grandTotal, 1.626);
  });

  test(
    'valid discounts are unrestricted but final invoice must stay positive',
    () {
      expect(
        service.validateInvoice([
          _line(price: 10).copyWith(discount: 9.999),
        ]).grandTotal,
        0.001,
      );
      expect(
        service.validateInvoice([
          _line(price: 10).copyWith(discount: 10),
          _line(custom: true, price: 5),
        ]).grandTotal,
        5,
      );
      for (final lines in <List<InvoiceItemSnapshot>>[
        [],
        [_line(price: 0)],
        [_line(custom: true, price: 0)],
        [_line(price: 10).copyWith(discount: 10)],
        [_line().copyWith(quantity: 0)],
        [_line().copyWith(quantity: -1)],
        [_line().copyWith(quantity: 0.0001)],
        [_line().copyWith(unitPrice: -0.0001)],
        [_line().copyWith(discount: 11)],
        [_line().copyWith(discount: -1)],
        [_line().copyWith(taxPercent: 101)],
        [_line().copyWith(unitPrice: double.nan)],
        [_line(custom: true).copyWith(description: '')],
        [_line(), _line()],
      ]) {
        expect(() => service.validateInvoice(lines), throwsFormatException);
      }
    },
  );

  for (final role in ['sales_rep', 'admin']) {
    test(
      '$role quotation conversion preserves lines, recalculates and only drafts',
      () {
        final invoice = QuotationRepository.buildInvoiceDraft(
          quotation: _quotation(),
          customer: _customer(),
          user: _user(role),
          invoiceId: 'invoice',
          invoiceNumber: 'INV-2026-000001',
          documents: DocumentSettingsModel.defaults,
          now: DateTime(2026, 10, 19),
        );
        expect(invoice.invoiceStatus, InvoiceStatus.draft);
        expect(invoice.items.first.unitPrice, 0);
        expect(invoice.items.last.lineType, InvoiceLineType.custom);
        expect(invoice.items.last.itemId, isNull);
        expect(invoice.items.last.discount, 2);
        expect(invoice.items.last.quantity, 2);
        expect(
          invoice.grandTotal,
          18,
        ); // Stored quotation aggregates are forged.
        expect(invoice.remainingAmount, 18);
        expect(invoice.customerId, 'customer');
        expect(invoice.salesRepId, 'rep');
        expect(
          invoice.stockSourceType,
          role == 'sales_rep'
              ? InventorySourceType.salesRep
              : InventorySourceType.companyWarehouse,
        );
        expect(invoice.stockSourceSalesRepId, role == 'sales_rep' ? 'rep' : '');
        expect(
          invoice.stockSourceId,
          role == 'sales_rep' ? 'rep' : 'default_warehouse',
        );
        expect(invoice.financialPosted, isFalse);
        expect(invoice.inventoryPosted, isFalse);
        expect(invoice.customerTransactionIds, isEmpty);
        expect(invoice.cashMovementIds, isEmpty);
        expect(invoice.inventoryMovementIds, isEmpty);
        expect(invoice.canEdit, isTrue);
        expect(invoice.canDelete, isTrue);
        for (final posted in [
          invoice.copyWith(financialPosted: true),
          invoice.copyWith(inventoryPosted: true),
          invoice.copyWith(isLocked: true),
          invoice.copyWith(invoiceStatus: InvoiceStatus.confirmed),
          invoice.copyWith(invoiceStatus: InvoiceStatus.rejected),
        ]) {
          expect(posted.canEdit, isFalse);
          expect(posted.canDelete, isFalse);
        }
      },
    );
  }

  test(
    'rep conversion accepts custom-only and prevents cross-rep/customer/company access',
    () {
      final customOnly = QuotationRepository.buildInvoiceDraft(
        quotation: _quotation().copyWith(items: [_quotation().items.last]),
        customer: _customer(),
        user: _user('sales_rep'),
        invoiceId: 'invoice',
        invoiceNumber: 'INV-2026-000001',
        documents: DocumentSettingsModel.defaults,
        now: DateTime(2026, 10, 19),
      );
      expect(customOnly.grandTotal, 18);
      expect(customOnly.items.single.lineType, InvoiceLineType.custom);
      for (final quotation in [
        _quotation().copyWith(salesRepId: 'other-rep'),
        _quotation().copyWith(companyId: 'other-company'),
        _quotation().copyWith(customerId: 'other-customer'),
        _quotation().copyWith(status: QuotationStatus.converted),
      ]) {
        expect(
          () => QuotationRepository.buildInvoiceDraft(
            quotation: quotation,
            customer: _customer(),
            user: _user('sales_rep'),
            invoiceId: 'invoice',
            invoiceNumber: 'INV-2026-000001',
            documents: DocumentSettingsModel.defaults,
            now: DateTime(2026, 10, 19),
          ),
          throwsA(isA<QuotationRepositoryException>()),
        );
      }
      expect(
        () => QuotationRepository.buildInvoiceDraft(
          quotation: _quotation(),
          customer: _customer().copyWith(createdByUid: 'other-rep'),
          user: _user('sales_rep'),
          invoiceId: 'invoice',
          invoiceNumber: 'INV-2026-000001',
          documents: DocumentSettingsModel.defaults,
          now: DateTime(2026, 10, 19),
        ),
        throwsA(isA<QuotationRepositoryException>()),
      );
    },
  );
}

InvoiceItemSnapshot _line({bool custom = false, double price = 10}) =>
    InvoiceItemSnapshot(
      lineId: custom ? 'custom' : 'catalog',
      lineType: custom ? InvoiceLineType.custom : InvoiceLineType.catalog,
      itemId: custom ? null : 'item',
      itemName: custom ? 'Installation' : 'Pump',
      description: 'Description',
      itemCode: '',
      unit: 'pcs',
      quantity: 1,
      unitPrice: price,
      discount: 0,
      taxPercent: 0,
      subtotal: price,
      taxAmount: 0,
      total: price,
    );

BusinessUserContext _user(String role) => BusinessUserContext(
  uid: role == 'admin' ? 'admin' : 'rep',
  name: 'User',
  email: 'user@example.com',
  phone: '',
  role: role,
  companyId: 'default_company',
  active: true,
  approvalStatus: 'approved',
);

CustomerModel _customer() => CustomerModel.fromMap({
  'id': 'customer',
  'companyId': 'default_company',
  'name': 'Customer',
  'active': true,
  'createdByUid': 'rep',
});

QuotationModel _quotation() =>
    QuotationModel.empty(
      companyId: 'default_company',
      createdByUid: 'rep',
      createdByName: 'Rep',
      createdByRole: 'sales_rep',
    ).copyWith(
      id: 'quotation',
      status: QuotationStatus.sent,
      customerId: 'customer',
      items: [
        QuotationItemModel.fromInvoiceItem(_line(price: 0)),
        QuotationItemModel.fromInvoiceItem(
          _line(custom: true).copyWith(quantity: 2, discount: 2),
        ),
      ],
      subtotal: 999,
      grandTotal: 999,
    );
