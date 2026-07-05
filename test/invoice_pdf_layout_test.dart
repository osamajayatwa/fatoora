import 'dart:convert';
import 'dart:typed_data';

import 'package:fatoora/core/pdf/app_pdf_localization.dart';
import 'package:fatoora/core/pdf/business_pdf_configuration.dart';
import 'package:fatoora/features/invoices/data/models/invoice_customer_snapshot.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:fatoora/features/invoices/data/models/invoice_government_model.dart';
import 'package:fatoora/features/invoices/data/models/invoice_item_snapshot.dart';
import 'package:fatoora/features/invoices/data/models/invoice_model.dart';
import 'package:fatoora/features/invoices/data/services/invoice_pdf_service.dart';
import 'package:fatoora/features/settings/data/models/company_settings_model.dart';
import 'package:fatoora/features/settings/data/models/pdf_settings_model.dart';
import 'package:fatoora/features/settings/data/models/user_preferences_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ar');
  });

  test('English one-item invoice fits on one page without QR', () async {
    final invoice = _invoice(itemCount: 1);
    final financialSnapshot = _financialSnapshot(invoice);

    final bytes = await InvoicePdfService.build(
      invoice,
      configuration: _configuration('en'),
    );

    _expectPdf(bytes);
    expect(_pageCount(bytes), 1);
    expect(_financialSnapshot(invoice), financialSnapshot);
  });

  test('Arabic one-item electronic invoice fits on one page with QR', () async {
    final invoice = _invoice(itemCount: 1, electronic: true);

    final bytes = await InvoicePdfService.build(
      invoice,
      configuration: _configuration('ar'),
    );

    _expectPdf(bytes);
    expect(_pageCount(bytes), 1);
  });

  test('ten-item invoice remains a single compact page', () async {
    final bytes = await InvoicePdfService.build(
      _invoice(itemCount: 10),
      configuration: _configuration('en'),
    );

    _expectPdf(bytes);
    expect(_pageCount(bytes), 1);
  });

  test('twenty-five long items and long notes stay within two pages', () async {
    final invoice = _invoice(itemCount: 25, longNames: true, notes: _longNotes);

    final bytes = await InvoicePdfService.build(
      invoice,
      configuration: _configuration('en'),
    );

    _expectPdf(bytes);
    expect(_pageCount(bytes), lessThanOrEqualTo(2));
  });

  test('fifty-item Arabic invoice with long content still generates', () async {
    final invoice = _invoice(
      itemCount: 50,
      longNames: true,
      notes: _longNotes,
      electronic: true,
    );

    final bytes = await InvoicePdfService.build(
      invoice,
      configuration: _configuration('ar'),
    );

    _expectPdf(bytes);
    expect(_pageCount(bytes), inInclusiveRange(1, 10));
  });

  test(
    'English-primary invoice supports Arabic customer and mixed model codes',
    () async {
      final invoice = _mixedInvoice(
        customer: const InvoiceCustomerSnapshot(
          id: 'customer-mixed-ar',
          name: 'شركة حلول المياه المتقدمة Advanced Water Solutions',
          phone: '+962 79 123 4567',
          address: 'King Abdullah II Industrial Estate - مبنى 24',
          taxNumber: 'TAX-AR-100200',
          nationalNumber: 'NAT-200300',
          city: 'Amman - عمان',
        ),
        notes:
            'Please verify model FDSS 4SP-10 before delivery. '
            'يرجى مطابقة رقم الموديل والكمية قبل الاستلام.',
      );
      final financialSnapshot = _financialSnapshot(invoice);

      final bytes = await InvoicePdfService.build(
        invoice,
        configuration: _mixedConfiguration('en'),
      );

      _expectPdf(bytes);
      expect(_pageCount(bytes), 1);
      expect(_financialSnapshot(invoice), financialSnapshot);
    },
  );

  test(
    'Arabic-primary invoice supports English customer and Arabic notes',
    () async {
      final invoice = _mixedInvoice(
        customer: const InvoiceCustomerSnapshot(
          id: 'customer-mixed-en',
          name: 'Global Pump Systems LLC',
          phone: '+962 6 555 0199',
          address: 'المنطقة الصناعية - Warehouse B12',
          taxNumber: 'TAX-GLB-500600',
          nationalNumber: 'NAT-700800',
          city: 'Aqaba - العقبة',
        ),
        notes:
            'شروط الضمان حسب العرض المعتمد. Use reference INV-2026-000321 '
            'and model 50FCL16-75 when contacting support.',
        electronic: true,
      );

      final bytes = await InvoicePdfService.build(
        invoice,
        configuration: _mixedConfiguration('ar'),
      );

      _expectPdf(bytes);
      expect(_pageCount(bytes), 1);
    },
  );
}

const _longNotes =
    'Payment is due according to the agreed commercial terms. '
    'Please reference the invoice number with every payment. '
    'Goods were inspected and accepted in good condition. '
    'Warranty and installation conditions remain subject to the signed offer. '
    'For account questions, contact the sales representative shown above. '
    'This note intentionally contains enough text to verify safe wrapping.';

BusinessPdfConfiguration _configuration(String languageCode) {
  return BusinessPdfConfiguration(
    companySettings: CompanySettingsModel.defaults.copyWith(
      name: 'Jayatwa Trading Establishment',
      phone: '+962 6 000 0000',
      address: 'Amman Industrial Area, Building 15',
    ),
    pdfSettings: PdfSettingsModel.defaults.copyWith(
      invoiceFooterText: languageCode == 'ar'
          ? 'شكرا لتعاملكم معنا'
          : 'Thank you for your business',
    ),
    userPreferences: UserPreferencesModel.defaults,
    localization: AppPdfLocalization.forLanguage(languageCode),
  );
}

BusinessPdfConfiguration _mixedConfiguration(String languageCode) {
  return BusinessPdfConfiguration(
    companySettings: CompanySettingsModel.defaults.copyWith(
      name: 'مؤسسة الجياطوة التجارية | Jayatwa Trading Establishment',
      country: 'Jordan - الأردن',
      phone: '+962 6 000 0000',
      address: 'Amman Industrial Area - المنطقة الصناعية، عمان',
    ),
    pdfSettings: PdfSettingsModel.defaults.copyWith(
      invoiceFooterText: 'Thank you for your business | شكرا لتعاملكم معنا',
    ),
    userPreferences: UserPreferencesModel.defaults,
    localization: AppPdfLocalization.forLanguage(languageCode),
  );
}

InvoiceModel _mixedInvoice({
  required InvoiceCustomerSnapshot customer,
  required String notes,
  bool electronic = false,
}) {
  const mixedNames = [
    'مضخة غاطسة FDSS 4SP-10 - Stainless Steel 4 inch',
    '50FCL16-75 مضخة طرد مركزي / 3-Phase Motor',
    'Control Panel لوحة تحكم 380V + IP65',
    'Heavy-duty vertical multistage pump مضخة متعددة المراحل - Model '
        'FDSS 4SP-10 / 50Hz + accessories وملحقات التركيب كاملة',
  ];
  final source = _invoice(itemCount: mixedNames.length, electronic: electronic);
  return source.copyWith(
    customerId: customer.id,
    customerSnapshot: customer,
    salesRepName: 'Ahmad Al-Jayatweh - أحمد الجياطوة',
    items: [
      for (var index = 0; index < mixedNames.length; index++)
        source.items[index].copyWith(
          itemName: mixedNames[index],
          itemCode: index.isEven ? 'FDSS 4SP-10' : '50FCL16-75',
          unit: index.isEven ? 'pcs - قطعة' : 'set - طقم',
        ),
    ],
    notes: notes,
  );
}

InvoiceModel _invoice({
  required int itemCount,
  bool electronic = false,
  bool longNames = false,
  String notes = '',
}) {
  final now = DateTime(2026, 7, 4);
  return InvoiceModel(
    id: 'invoice-layout-$itemCount',
    companyId: 'default_company',
    invoiceNumber: 'INV-2026-000321',
    invoiceType: electronic ? InvoiceType.electronic : InvoiceType.regular,
    invoiceStatus: InvoiceStatus.confirmed,
    paymentType: PaymentType.partial,
    paymentStatus: PaymentStatus.partiallyPaid,
    hasReceivedPayment: true,
    invoiceDate: now,
    dueDate: now.add(const Duration(days: 14)),
    createdAt: now,
    updatedAt: now,
    createdByUid: 'admin-1',
    createdByName: 'Administration User',
    createdByRole: 'admin',
    salesRepId: 'rep-1',
    salesRepName: 'International Sales Representative',
    customerId: 'customer-1',
    customerSnapshot: const InvoiceCustomerSnapshot(
      id: 'customer-1',
      name: 'International Water and Pumping Solutions Company',
      phone: '+962 79 000 0000',
      address: 'King Abdullah II Industrial Estate, Building 120',
      taxNumber: 'TAX-100200300',
      nationalNumber: '200300400',
      city: 'Amman, Jordan',
    ),
    items: List.generate(itemCount, (index) {
      final sequence = index + 1;
      final name = longNames
          ? 'High-efficiency multistage centrifugal water pump with '
                'stainless-steel housing and control panel - Model $sequence'
          : 'Water pump model $sequence';
      return InvoiceItemSnapshot(
        itemId: 'item-$sequence',
        itemName: name,
        itemCode: 'PUMP-$sequence',
        unit: 'pcs',
        quantity: 2,
        unitPrice: 10.125,
        discount: 1.250,
        taxPercent: 16,
        subtotal: 20.250,
        taxAmount: 3.040,
        total: 22.040,
      );
    }),
    subtotal: 1234.567,
    totalDiscount: 98.765,
    totalTax: 181.728,
    grandTotal: 1317.530,
    paidAmount: 317.125,
    remainingAmount: 1000.405,
    notes: notes,
    paymentMethod: PaymentType.partial.value,
    isLocked: true,
    financialPosted: true,
    financialPostedByUid: 'admin-1',
    financialPostedByName: 'Administration User',
    customerTransactionIds: const ['transaction-1'],
    cashMovementIds: const ['cash-1'],
    inventoryPosted: true,
    inventoryPostedByUid: 'admin-1',
    inventoryPostedByName: 'Administration User',
    inventoryMovementIds: const ['stock-1'],
    searchKeywords: const [],
    customerNameLower: '',
    itemNamesLower: const [],
    invoiceNumberLower: '',
    dateString: '2026-07-04',
    government: electronic
        ? const InvoiceGovernmentModel(
            governmentInvoiceId: 'GOV-10001',
            uuid: '8f0f67a8-cc73-4b31-ae88-901c917bc001',
            qrCode: 'https://invoice.example/verify/GOV-10001',
            joFotaraStatus: 'accepted',
            joFotaraErrorCode: '',
            joFotaraErrorMessage: '',
            rawResponse: {},
          )
        : null,
  );
}

Map<String, Object> _financialSnapshot(InvoiceModel invoice) => {
  'subtotal': invoice.subtotal,
  'totalDiscount': invoice.totalDiscount,
  'totalTax': invoice.totalTax,
  'grandTotal': invoice.grandTotal,
  'paidAmount': invoice.paidAmount,
  'remainingAmount': invoice.remainingAmount,
  'invoiceStatus': invoice.invoiceStatus,
  'paymentStatus': invoice.paymentStatus,
};

int _pageCount(Uint8List bytes) {
  final source = latin1.decode(bytes);
  return RegExp(r'/Type\s*/Page\b').allMatches(source).length;
}

void _expectPdf(Uint8List bytes) {
  expect(bytes.length, greaterThan(1000));
  expect(ascii.decode(bytes.take(4).toList()), '%PDF');
  expect(_pageCount(bytes), greaterThan(0));
}
