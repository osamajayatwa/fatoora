import 'package:fatoora/core/settings/business_settings_defaults.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:fatoora/features/invoices/data/services/invoice_number_service.dart';
import 'package:fatoora/features/settings/data/models/document_settings_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('document numbering defaults', () {
    test(
      'falls back to legacy prefixes when settings are missing or invalid',
      () {
        expect(BusinessSettingsDefaults.prefix('', 'INV'), 'INV');
        expect(BusinessSettingsDefaults.prefix('bad-prefix', 'REC'), 'REC');
        expect(BusinessSettingsDefaults.prefix('quo', 'QUO'), 'QUO');
      },
    );

    test(
      'formats configured prefixes without changing the counter sequence',
      () {
        expect(
          BusinessSettingsDefaults.documentNumber(
            prefix: 'JTI',
            year: 2026,
            sequence: 42,
          ),
          'JTI-2026-000042',
        );
      },
    );

    test('invoice number preview uses the configured invoice prefix', () async {
      final number = await const InvoiceNumberService().generate(
        companyId: 'default_company',
        invoiceType: InvoiceType.regular,
        settings: DocumentSettingsModel.defaults.copyWith(invoicePrefix: 'JTI'),
        now: DateTime(2026, 6, 28, 12),
      );

      expect(number, matches(RegExp(r'^JTI-2026-[0-9]{6}$')));
    });
  });

  group('new document defaults', () {
    test('applies invoice due days only when positive', () {
      final invoiceDate = DateTime(2026, 6, 28);

      expect(
        BusinessSettingsDefaults.invoiceDueDate(invoiceDate, 7),
        DateTime(2026, 7, 5),
      );
      expect(
        BusinessSettingsDefaults.invoiceDueDate(invoiceDate, 0),
        invoiceDate,
      );
    });

    test(
      'default tax fills a missing value but preserves existing item tax',
      () {
        expect(
          BusinessSettingsDefaults.taxPercent(
            existingTaxPercent: null,
            defaultTaxPercent: 16,
          ),
          16,
        );
        expect(
          BusinessSettingsDefaults.taxPercent(
            existingTaxPercent: 5,
            defaultTaxPercent: 16,
          ),
          5,
        );
        expect(
          BusinessSettingsDefaults.taxPercent(
            existingTaxPercent: 0,
            defaultTaxPercent: 16,
          ),
          0,
        );
      },
    );

    test('personal note prefills only an empty new form', () {
      expect(
        BusinessSettingsDefaults.prefilledNote(
          currentNote: '',
          defaultNote: 'Thank you',
        ),
        'Thank you',
      );
      expect(
        BusinessSettingsDefaults.prefilledNote(
          currentNote: 'Custom note',
          defaultNote: 'Thank you',
        ),
        'Custom note',
      );
    });

    test('inventory defaults retain safe non-negative fallbacks', () {
      expect(BusinessSettingsDefaults.minimumStock(4), 4);
      expect(BusinessSettingsDefaults.minimumStock(-1), 0);
      expect(BusinessSettingsDefaults.warehouseId(''), 'default_warehouse');
      expect(BusinessSettingsDefaults.warehouseId('main'), 'main');
    });
  });
}
