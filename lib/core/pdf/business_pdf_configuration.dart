import 'package:fatoora/core/pdf/app_pdf_localization.dart';
import 'package:fatoora/features/settings/data/models/company_settings_model.dart';
import 'package:fatoora/features/settings/data/models/pdf_settings_model.dart';
import 'package:fatoora/features/settings/data/models/user_preferences_model.dart';

class BusinessPdfConfiguration {
  const BusinessPdfConfiguration({
    required this.companySettings,
    required this.pdfSettings,
    required this.userPreferences,
    required this.localization,
  });

  factory BusinessPdfConfiguration.defaults({String languageCode = 'en'}) {
    return BusinessPdfConfiguration(
      companySettings: CompanySettingsModel.defaults,
      pdfSettings: PdfSettingsModel.defaults,
      userPreferences: UserPreferencesModel.defaults,
      localization: AppPdfLocalization.forLanguage(languageCode),
    );
  }

  final CompanySettingsModel companySettings;
  final PdfSettingsModel pdfSettings;
  final UserPreferencesModel userPreferences;
  final AppPdfLocalization localization;

  bool get showLogo => companySettings.logoEnabled && pdfSettings.showLogo;
  bool get showCompanyInfo => pdfSettings.showCompanyInfo;

  String invoiceNotes(String documentNotes) => _combine([
    documentNotes,
    userPreferences.defaultInvoiceNote,
    pdfSettings.defaultNotes,
  ]);

  String receiptNotes(String documentNotes) => _combine([
    documentNotes,
    userPreferences.defaultReceiptNote,
    pdfSettings.defaultNotes,
  ]);

  String quotationTerms(String documentTerms) =>
      _combine([documentTerms, pdfSettings.quotationTerms]);

  String generalNotes(String documentNotes) =>
      _combine([documentNotes, pdfSettings.defaultNotes]);

  static String _combine(Iterable<String> values) {
    final unique = <String>[];
    for (final value in values) {
      final text = value.trim();
      if (text.isNotEmpty && !unique.contains(text)) unique.add(text);
    }
    return unique.join('\n\n');
  }
}
