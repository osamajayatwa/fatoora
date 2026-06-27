import 'package:cloud_firestore/cloud_firestore.dart';

class UserPreferencesModel {
  const UserPreferencesModel({
    required this.language,
    required this.themeMode,
    required this.defaultInvoiceNote,
    required this.defaultReceiptNote,
    required this.updatedAt,
  });

  static final UserPreferencesModel defaults = UserPreferencesModel(
    language: 'en',
    themeMode: 'system',
    defaultInvoiceNote: '',
    defaultReceiptNote: '',
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  static const supportedLanguages = {'en', 'ar'};
  static const supportedThemeModes = {'system', 'light', 'dark'};

  final String language;
  final String themeMode;
  final String defaultInvoiceNote;
  final String defaultReceiptNote;
  final DateTime updatedAt;

  factory UserPreferencesModel.fromMap(Map<String, dynamic>? data) {
    final map = data ?? const <String, dynamic>{};
    final language = _string(map['language'], defaults.language).toLowerCase();
    final themeMode = _string(
      map['themeMode'],
      defaults.themeMode,
    ).toLowerCase();
    return UserPreferencesModel(
      language: supportedLanguages.contains(language)
          ? language
          : defaults.language,
      themeMode: supportedThemeModes.contains(themeMode)
          ? themeMode
          : defaults.themeMode,
      defaultInvoiceNote: _string(map['defaultInvoiceNote'], ''),
      defaultReceiptNote: _string(map['defaultReceiptNote'], ''),
      updatedAt: _date(map['updatedAt'], defaults.updatedAt),
    );
  }

  Map<String, dynamic> toMap() => {
    'language': supportedLanguages.contains(language)
        ? language
        : defaults.language,
    'themeMode': supportedThemeModes.contains(themeMode)
        ? themeMode
        : defaults.themeMode,
    'defaultInvoiceNote': defaultInvoiceNote.trim(),
    'defaultReceiptNote': defaultReceiptNote.trim(),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  UserPreferencesModel copyWith({
    String? language,
    String? themeMode,
    String? defaultInvoiceNote,
    String? defaultReceiptNote,
    DateTime? updatedAt,
  }) {
    return UserPreferencesModel(
      language: language ?? this.language,
      themeMode: themeMode ?? this.themeMode,
      defaultInvoiceNote: defaultInvoiceNote ?? this.defaultInvoiceNote,
      defaultReceiptNote: defaultReceiptNote ?? this.defaultReceiptNote,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static String _string(Object? value, String fallback) =>
      value is String ? value.trim() : fallback;

  static DateTime _date(Object? value, DateTime fallback) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value) ?? fallback;
    return fallback;
  }
}
