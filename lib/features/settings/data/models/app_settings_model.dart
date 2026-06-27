import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fatoora/features/settings/data/models/company_settings_model.dart';
import 'package:fatoora/features/settings/data/models/document_settings_model.dart';
import 'package:fatoora/features/settings/data/models/inventory_settings_model.dart';
import 'package:fatoora/features/settings/data/models/jofotara_status_settings_model.dart';
import 'package:fatoora/features/settings/data/models/pdf_settings_model.dart';
import 'package:fatoora/features/settings/data/models/permission_settings_model.dart';

class AppSettingsModel {
  const AppSettingsModel({
    required this.companySettings,
    required this.documentSettings,
    required this.inventorySettings,
    required this.pdfSettings,
    required this.permissionSettings,
    required this.jofotaraStatusSettings,
    required this.schemaVersion,
    required this.updatedAt,
    required this.updatedByUid,
    required this.updatedByName,
  });

  static final AppSettingsModel defaults = AppSettingsModel(
    companySettings: CompanySettingsModel.defaults,
    documentSettings: DocumentSettingsModel.defaults,
    inventorySettings: InventorySettingsModel.defaults,
    pdfSettings: PdfSettingsModel.defaults,
    permissionSettings: PermissionSettingsModel.defaults,
    jofotaraStatusSettings: JofotaraStatusSettingsModel.defaults,
    schemaVersion: 1,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    updatedByUid: '',
    updatedByName: '',
  );

  final CompanySettingsModel companySettings;
  final DocumentSettingsModel documentSettings;
  final InventorySettingsModel inventorySettings;
  final PdfSettingsModel pdfSettings;
  final PermissionSettingsModel permissionSettings;
  final JofotaraStatusSettingsModel jofotaraStatusSettings;
  final int schemaVersion;
  final DateTime updatedAt;
  final String updatedByUid;
  final String updatedByName;

  factory AppSettingsModel.fromMap(Map<String, dynamic>? data) {
    final map = data ?? const <String, dynamic>{};
    return AppSettingsModel(
      companySettings: CompanySettingsModel.fromMap(
        _map(map['companySettings']),
      ),
      documentSettings: DocumentSettingsModel.fromMap(
        _map(map['documentSettings']),
      ),
      inventorySettings: InventorySettingsModel.fromMap(
        _map(map['inventorySettings']),
      ),
      pdfSettings: PdfSettingsModel.fromMap(_map(map['pdfSettings'])),
      permissionSettings: PermissionSettingsModel.fromMap(
        _map(map['permissionSettings']),
      ),
      jofotaraStatusSettings: JofotaraStatusSettingsModel.fromMap(
        _map(map['jofotaraStatusSettings']),
      ),
      schemaVersion: _int(map['schemaVersion'], defaults.schemaVersion),
      updatedAt: _date(map['updatedAt'], defaults.updatedAt),
      updatedByUid: _string(map['updatedByUid']),
      updatedByName: _string(map['updatedByName']),
    );
  }

  Map<String, dynamic> toMap() => {
    'companySettings': companySettings.toMap(),
    'documentSettings': documentSettings.toMap(),
    'inventorySettings': inventorySettings.toMap(),
    'pdfSettings': pdfSettings.toMap(),
    'permissionSettings': permissionSettings.toMap(),
    'jofotaraStatusSettings': jofotaraStatusSettings.toMap(),
    'schemaVersion': schemaVersion,
    'updatedAt': Timestamp.fromDate(updatedAt),
    'updatedByUid': updatedByUid.trim(),
    'updatedByName': updatedByName.trim(),
  };

  AppSettingsModel copyWith({
    CompanySettingsModel? companySettings,
    DocumentSettingsModel? documentSettings,
    InventorySettingsModel? inventorySettings,
    PdfSettingsModel? pdfSettings,
    PermissionSettingsModel? permissionSettings,
    JofotaraStatusSettingsModel? jofotaraStatusSettings,
    int? schemaVersion,
    DateTime? updatedAt,
    String? updatedByUid,
    String? updatedByName,
  }) {
    return AppSettingsModel(
      companySettings: companySettings ?? this.companySettings,
      documentSettings: documentSettings ?? this.documentSettings,
      inventorySettings: inventorySettings ?? this.inventorySettings,
      pdfSettings: pdfSettings ?? this.pdfSettings,
      permissionSettings: permissionSettings ?? this.permissionSettings,
      jofotaraStatusSettings:
          jofotaraStatusSettings ?? this.jofotaraStatusSettings,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedByUid: updatedByUid ?? this.updatedByUid,
      updatedByName: updatedByName ?? this.updatedByName,
    );
  }

  static Map<String, dynamic>? _map(Object? value) {
    if (value is! Map) return null;
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  static String _string(Object? value) => value is String ? value.trim() : '';

  static int _int(Object? value, int fallback) {
    if (value is num && value.isFinite) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? fallback;
    return fallback;
  }

  static DateTime _date(Object? value, DateTime fallback) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value) ?? fallback;
    return fallback;
  }
}
