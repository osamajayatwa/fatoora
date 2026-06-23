import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fatoora/features/invoices/data/models/invoice_customer_snapshot.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:fatoora/features/invoices/data/models/invoice_government_model.dart';
import 'package:fatoora/features/invoices/data/models/invoice_item_snapshot.dart';

class InvoiceModel {
  const InvoiceModel({
    required this.id,
    required this.companyId,
    required this.invoiceNumber,
    required this.invoiceType,
    required this.invoiceStatus,
    required this.invoiceDate,
    required this.createdAt,
    required this.updatedAt,
    required this.createdByUid,
    required this.createdByName,
    required this.customerId,
    this.customerSnapshot,
    required this.items,
    required this.subtotal,
    required this.totalDiscount,
    required this.totalTax,
    required this.grandTotal,
    required this.notes,
    required this.paymentMethod,
    required this.isLocked,
    required this.searchKeywords,
    required this.customerNameLower,
    required this.itemNamesLower,
    required this.invoiceNumberLower,
    required this.dateString,
    this.government,
  });

  final String id;
  final String companyId;
  final String invoiceNumber;
  final InvoiceType invoiceType;
  final InvoiceStatus invoiceStatus;
  final DateTime invoiceDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdByUid;
  final String createdByName;
  final String customerId;
  final InvoiceCustomerSnapshot? customerSnapshot;
  final List<InvoiceItemSnapshot> items;
  final double subtotal;
  final double totalDiscount;
  final double totalTax;
  final double grandTotal;
  final String notes;
  final String paymentMethod;
  final bool isLocked;
  final List<String> searchKeywords;
  final String customerNameLower;
  final List<String> itemNamesLower;
  final String invoiceNumberLower;
  final String dateString;
  final InvoiceGovernmentModel? government;

  bool get isElectronic => invoiceType == InvoiceType.electronic;
  bool get isDraft => invoiceStatus == InvoiceStatus.draft;
  bool get canDelete => invoiceStatus == InvoiceStatus.draft;
  bool get canEdit =>
      !isLocked &&
      !(invoiceType == InvoiceType.electronic &&
          invoiceStatus == InvoiceStatus.accepted) &&
      invoiceStatus != InvoiceStatus.pendingSubmit &&
      invoiceStatus != InvoiceStatus.cancelled;

  factory InvoiceModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    return InvoiceModel.fromMap(document.data() ?? const {}, id: document.id);
  }

  factory InvoiceModel.fromMap(Map<String, dynamic> data, {String? id}) {
    final items = _readList(
      data['items'],
    ).map(InvoiceItemSnapshot.fromMap).toList(growable: false);
    return InvoiceModel(
      id: id ?? _readString(data, 'id'),
      companyId: _readString(data, 'companyId'),
      invoiceNumber: _readString(data, 'invoiceNumber'),
      invoiceType: invoiceTypeFromValue(data['invoiceType']),
      invoiceStatus: invoiceStatusFromValue(data['invoiceStatus']),
      invoiceDate: _readDate(data, 'invoiceDate') ?? DateTime.now(),
      createdAt: _readDate(data, 'createdAt') ?? DateTime.now(),
      updatedAt: _readDate(data, 'updatedAt') ?? DateTime.now(),
      createdByUid: _readString(data, 'createdByUid'),
      createdByName: _readString(data, 'createdByName'),
      customerId: _readString(data, 'customerId'),
      customerSnapshot: data['customerSnapshot'] == null
          ? null
          : InvoiceCustomerSnapshot.fromMap(data['customerSnapshot']),
      items: items,
      subtotal: _readDouble(data, 'subtotal'),
      totalDiscount: _readDouble(data, 'totalDiscount'),
      totalTax: _readDouble(data, 'totalTax'),
      grandTotal: _readDouble(data, 'grandTotal'),
      notes: _readString(data, 'notes'),
      paymentMethod: _readString(data, 'paymentMethod'),
      isLocked: _readBool(data, 'isLocked'),
      searchKeywords: _readStringList(data['searchKeywords']),
      customerNameLower: _readString(data, 'customerNameLower'),
      itemNamesLower: _readStringList(data['itemNamesLower']),
      invoiceNumberLower: _readString(data, 'invoiceNumberLower'),
      dateString: _readString(data, 'dateString'),
      government: data['government'] == null
          ? null
          : InvoiceGovernmentModel.fromMap(data['government']),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'companyId': companyId,
    'invoiceNumber': invoiceNumber,
    'invoiceType': invoiceType.value,
    'invoiceStatus': invoiceStatus.value,
    'invoiceDate': Timestamp.fromDate(invoiceDate),
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
    'createdByUid': createdByUid,
    'createdByName': createdByName,
    'customerId': customerId,
    'customerSnapshot': customerSnapshot?.toMap(),
    'items': items.map((item) => item.toMap()).toList(),
    'subtotal': subtotal,
    'totalDiscount': totalDiscount,
    'totalTax': totalTax,
    'grandTotal': grandTotal,
    'notes': notes,
    'paymentMethod': paymentMethod,
    'isLocked': isLocked,
    'searchKeywords': searchKeywords,
    'customerNameLower': customerNameLower,
    'itemNamesLower': itemNamesLower,
    'invoiceNumberLower': invoiceNumberLower,
    'dateString': dateString,
    'government': government?.toMap(),
  };

  InvoiceModel copyWith({
    String? id,
    String? companyId,
    String? invoiceNumber,
    InvoiceType? invoiceType,
    InvoiceStatus? invoiceStatus,
    DateTime? invoiceDate,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdByUid,
    String? createdByName,
    String? customerId,
    InvoiceCustomerSnapshot? customerSnapshot,
    List<InvoiceItemSnapshot>? items,
    double? subtotal,
    double? totalDiscount,
    double? totalTax,
    double? grandTotal,
    String? notes,
    String? paymentMethod,
    bool? isLocked,
    List<String>? searchKeywords,
    String? customerNameLower,
    List<String>? itemNamesLower,
    String? invoiceNumberLower,
    String? dateString,
    InvoiceGovernmentModel? government,
  }) {
    return InvoiceModel(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      invoiceType: invoiceType ?? this.invoiceType,
      invoiceStatus: invoiceStatus ?? this.invoiceStatus,
      invoiceDate: invoiceDate ?? this.invoiceDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdByUid: createdByUid ?? this.createdByUid,
      createdByName: createdByName ?? this.createdByName,
      customerId: customerId ?? this.customerId,
      customerSnapshot: customerSnapshot ?? this.customerSnapshot,
      items: items ?? this.items,
      subtotal: subtotal ?? this.subtotal,
      totalDiscount: totalDiscount ?? this.totalDiscount,
      totalTax: totalTax ?? this.totalTax,
      grandTotal: grandTotal ?? this.grandTotal,
      notes: notes ?? this.notes,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      isLocked: isLocked ?? this.isLocked,
      searchKeywords: searchKeywords ?? this.searchKeywords,
      customerNameLower: customerNameLower ?? this.customerNameLower,
      itemNamesLower: itemNamesLower ?? this.itemNamesLower,
      invoiceNumberLower: invoiceNumberLower ?? this.invoiceNumberLower,
      dateString: dateString ?? this.dateString,
      government: government ?? this.government,
    );
  }

  InvoiceModel withSearchFields() {
    final customerLower = _normalize(customerSnapshot?.name ?? '');
    final itemNames = items
        .map((item) => _normalize(item.itemName))
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final numberLower = _normalize(invoiceNumber);
    final date = _formatDate(invoiceDate);
    return copyWith(
      customerNameLower: customerLower,
      itemNamesLower: itemNames,
      invoiceNumberLower: numberLower,
      dateString: date,
      searchKeywords: buildSearchKeywords(
        invoiceNumber: numberLower,
        customerName: customerLower,
        itemNames: itemNames,
        dateString: date,
      ),
    );
  }

  static List<String> buildSearchKeywords({
    required String invoiceNumber,
    required String customerName,
    required List<String> itemNames,
    required String dateString,
  }) {
    final keywords = <String>{};
    for (final value in [
      invoiceNumber,
      customerName,
      dateString,
      ...itemNames,
    ]) {
      final normalized = _normalize(value);
      if (normalized.isEmpty) continue;
      keywords.add(normalized);
      for (final token in normalized.split(RegExp(r'[\s\-_/]+'))) {
        if (token.isEmpty) continue;
        keywords.add(token);
        for (var i = 1; i <= token.length && i <= 20; i++) {
          keywords.add(token.substring(0, i));
        }
      }
    }
    return keywords.toList(growable: false)..sort();
  }

  static String formatDateForSearch(DateTime date) => _formatDate(date);

  static String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static String _normalize(String value) => value.trim().toLowerCase();

  static String _readString(Map<String, dynamic> data, String key) {
    final value = data[key];
    return value is String ? value.trim() : '';
  }

  static bool _readBool(Map<String, dynamic> data, String key) {
    final value = data[key];
    return value is bool ? value : false;
  }

  static double _readDouble(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is num && value.isFinite) return value.toDouble();
    if (value is String) return double.tryParse(value.trim()) ?? 0;
    return 0;
  }

  static DateTime? _readDate(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static List<Object?> _readList(Object? value) {
    if (value is List) return value;
    return const [];
  }

  static List<String> _readStringList(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Object>()
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
}
