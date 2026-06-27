class PdfSettingsModel {
  const PdfSettingsModel({
    required this.showLogo,
    required this.showCompanyInfo,
    required this.pdfLanguageMode,
    required this.invoiceFooterText,
    required this.quotationTerms,
    required this.receiptFooterText,
    required this.statementFooterText,
    required this.defaultNotes,
  });

  static const PdfSettingsModel defaults = PdfSettingsModel(
    showLogo: true,
    showCompanyInfo: true,
    pdfLanguageMode: 'app_language',
    invoiceFooterText: '',
    quotationTerms: '',
    receiptFooterText: '',
    statementFooterText: '',
    defaultNotes: '',
  );

  static const supportedLanguageModes = {'app_language', 'ar', 'en'};

  final bool showLogo;
  final bool showCompanyInfo;
  final String pdfLanguageMode;
  final String invoiceFooterText;
  final String quotationTerms;
  final String receiptFooterText;
  final String statementFooterText;
  final String defaultNotes;

  factory PdfSettingsModel.fromMap(Map<String, dynamic>? data) {
    final map = data ?? const <String, dynamic>{};
    final languageMode = _string(
      map['pdfLanguageMode'],
      defaults.pdfLanguageMode,
    ).toLowerCase();
    return PdfSettingsModel(
      showLogo: _bool(map['showLogo'], defaults.showLogo),
      showCompanyInfo: _bool(map['showCompanyInfo'], defaults.showCompanyInfo),
      pdfLanguageMode: supportedLanguageModes.contains(languageMode)
          ? languageMode
          : defaults.pdfLanguageMode,
      invoiceFooterText: _string(map['invoiceFooterText'], ''),
      quotationTerms: _string(map['quotationTerms'], ''),
      receiptFooterText: _string(map['receiptFooterText'], ''),
      statementFooterText: _string(map['statementFooterText'], ''),
      defaultNotes: _string(map['defaultNotes'], ''),
    );
  }

  Map<String, dynamic> toMap() => {
    'showLogo': showLogo,
    'showCompanyInfo': showCompanyInfo,
    'pdfLanguageMode': supportedLanguageModes.contains(pdfLanguageMode)
        ? pdfLanguageMode
        : defaults.pdfLanguageMode,
    'invoiceFooterText': invoiceFooterText.trim(),
    'quotationTerms': quotationTerms.trim(),
    'receiptFooterText': receiptFooterText.trim(),
    'statementFooterText': statementFooterText.trim(),
    'defaultNotes': defaultNotes.trim(),
  };

  PdfSettingsModel copyWith({
    bool? showLogo,
    bool? showCompanyInfo,
    String? pdfLanguageMode,
    String? invoiceFooterText,
    String? quotationTerms,
    String? receiptFooterText,
    String? statementFooterText,
    String? defaultNotes,
  }) {
    return PdfSettingsModel(
      showLogo: showLogo ?? this.showLogo,
      showCompanyInfo: showCompanyInfo ?? this.showCompanyInfo,
      pdfLanguageMode: pdfLanguageMode ?? this.pdfLanguageMode,
      invoiceFooterText: invoiceFooterText ?? this.invoiceFooterText,
      quotationTerms: quotationTerms ?? this.quotationTerms,
      receiptFooterText: receiptFooterText ?? this.receiptFooterText,
      statementFooterText: statementFooterText ?? this.statementFooterText,
      defaultNotes: defaultNotes ?? this.defaultNotes,
    );
  }

  static String _string(Object? value, String fallback) =>
      value is String ? value.trim() : fallback;

  static bool _bool(Object? value, bool fallback) =>
      value is bool ? value : fallback;
}
