import 'package:fatoora/core/settings/business_settings_defaults.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:fatoora/features/settings/data/models/document_settings_model.dart';

class InvoiceNumberService {
  const InvoiceNumberService();

  Future<String> generate({
    required String companyId,
    required InvoiceType invoiceType,
    DocumentSettingsModel settings = DocumentSettingsModel.defaults,
    DateTime? now,
  }) async {
    final generatedAt = now ?? DateTime.now();
    final prefix = BusinessSettingsDefaults.prefix(
      settings.invoicePrefix,
      DocumentSettingsModel.defaults.invoicePrefix,
    );
    final previewSequence = generatedAt.microsecondsSinceEpoch % 1000000;
    return BusinessSettingsDefaults.documentNumber(
      prefix: prefix,
      year: generatedAt.year,
      sequence: previewSequence,
    );
  }
}
