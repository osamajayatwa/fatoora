import 'package:fatoora/core/pdf/app_pdf_localization.dart';
import 'package:fatoora/core/pdf/business_pdf_configuration.dart';
import 'package:fatoora/features/settings/data/models/company_settings_model.dart';
import 'package:fatoora/features/settings/data/models/pdf_settings_model.dart';
import 'package:fatoora/features/settings/data/models/user_preferences_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'PDF defaults preserve the existing company identity and visibility',
    () {
      final configuration = BusinessPdfConfiguration.defaults();

      expect(
        configuration.companySettings.name,
        'Jayatwa Trading Establishment',
      );
      expect(configuration.companySettings.country, 'Jordan');
      expect(configuration.companySettings.email, 'jtrdest@gmail.com');
      expect(configuration.showLogo, isTrue);
      expect(configuration.showCompanyInfo, isTrue);
    },
  );

  test('PDF visibility combines company and PDF settings safely', () {
    final configuration = BusinessPdfConfiguration(
      companySettings: CompanySettingsModel.defaults.copyWith(
        logoEnabled: false,
      ),
      pdfSettings: PdfSettingsModel.defaults.copyWith(
        showLogo: true,
        showCompanyInfo: false,
      ),
      userPreferences: UserPreferencesModel.defaults,
      localization: AppPdfLocalization.forLanguage('en'),
    );

    expect(configuration.showLogo, isFalse);
    expect(configuration.showCompanyInfo, isFalse);
  });

  test('PDF notes preserve document, personal, and company defaults', () {
    final configuration = BusinessPdfConfiguration(
      companySettings: CompanySettingsModel.defaults,
      pdfSettings: PdfSettingsModel.defaults.copyWith(
        defaultNotes: 'Company default',
      ),
      userPreferences: UserPreferencesModel.defaults.copyWith(
        defaultInvoiceNote: 'Personal default',
      ),
      localization: AppPdfLocalization.forLanguage('en'),
    );

    expect(
      configuration.invoiceNotes('Document note'),
      'Document note\n\nPersonal default\n\nCompany default',
    );
  });

  test('PDF localization can force Arabic or English', () {
    expect(AppPdfLocalization.forLanguage('ar').isArabic, isTrue);
    expect(AppPdfLocalization.forLanguage('arabic').isArabic, isFalse);
    expect(AppPdfLocalization.forLanguage('en').isArabic, isFalse);
  });
}
