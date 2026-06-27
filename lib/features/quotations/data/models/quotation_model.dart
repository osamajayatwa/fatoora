import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';
import 'package:fatoora/features/invoices/data/models/invoice_customer_snapshot.dart';
import 'package:fatoora/features/quotations/data/models/quotation_item_model.dart';
import 'package:fatoora/features/quotations/data/models/quotation_status.dart';

class QuotationModel {
  const QuotationModel({
    required this.id,
    required this.companyId,
    required this.quotationNumber,
    required this.quotationDate,
    required this.validUntil,
    required this.customerId,
    required this.customerSnapshot,
    required this.items,
    required this.subtotal,
    required this.totalDiscount,
    required this.totalTax,
    required this.grandTotal,
    required this.notes,
    required this.terms,
    required this.status,
    required this.salesRepId,
    required this.salesRepName,
    required this.createdByUid,
    required this.createdByName,
    required this.createdByRole,
    required this.convertedInvoiceId,
    required this.convertedInvoiceNumber,
    required this.createdAt,
    required this.updatedAt,
    required this.searchKeywords,
  });

  final String id;
  final String companyId;
  final String quotationNumber;
  final DateTime quotationDate;
  final DateTime validUntil;
  final String customerId;
  final InvoiceCustomerSnapshot? customerSnapshot;
  final List<QuotationItemModel> items;
  final double subtotal;
  final double totalDiscount;
  final double totalTax;
  final double grandTotal;
  final String notes;
  final String terms;
  final QuotationStatus status;
  final String salesRepId;
  final String salesRepName;
  final String createdByUid;
  final String createdByName;
  final String createdByRole;
  final String convertedInvoiceId;
  final String convertedInvoiceNumber;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> searchKeywords;

  bool get isDraft => status == QuotationStatus.draft;
  bool get canEdit => isDraft;
  bool get canConvert =>
      status == QuotationStatus.sent || status == QuotationStatus.accepted;

  factory QuotationModel.empty({
    required String companyId,
    required String createdByUid,
    required String createdByName,
    required String createdByRole,
  }) {
    final now = DateTime.now();
    return QuotationModel(
      id: '',
      companyId: companyId,
      quotationNumber: '',
      quotationDate: now,
      validUntil: now.add(const Duration(days: 14)),
      customerId: '',
      customerSnapshot: null,
      items: const [],
      subtotal: 0,
      totalDiscount: 0,
      totalTax: 0,
      grandTotal: 0,
      notes: '',
      terms: '',
      status: QuotationStatus.draft,
      salesRepId: createdByUid,
      salesRepName: createdByName,
      createdByUid: createdByUid,
      createdByName: createdByName,
      createdByRole: createdByRole,
      convertedInvoiceId: '',
      convertedInvoiceNumber: '',
      createdAt: now,
      updatedAt: now,
      searchKeywords: const [],
    );
  }

  factory QuotationModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    return QuotationModel.fromMap(document.data() ?? const {}, id: document.id);
  }

  factory QuotationModel.fromMap(Map<String, dynamic> data, {String? id}) {
    final quotationDate = _readDate(data, 'quotationDate') ?? DateTime.now();
    return QuotationModel(
      id: id ?? _readString(data, 'id'),
      companyId: _readString(data, 'companyId'),
      quotationNumber: _readString(data, 'quotationNumber'),
      quotationDate: quotationDate,
      validUntil: _readDate(data, 'validUntil') ?? quotationDate,
      customerId: _readString(data, 'customerId'),
      customerSnapshot: data['customerSnapshot'] == null
          ? null
          : InvoiceCustomerSnapshot.fromMap(data['customerSnapshot']),
      items: _readList(
        data['items'],
      ).map(QuotationItemModel.fromMap).toList(growable: false),
      subtotal: _readDouble(data, 'subtotal'),
      totalDiscount: _readDouble(data, 'totalDiscount'),
      totalTax: _readDouble(data, 'totalTax'),
      grandTotal: _readDouble(data, 'grandTotal'),
      notes: _readString(data, 'notes'),
      terms: _readString(data, 'terms'),
      status: quotationStatusFromValue(data['status']),
      salesRepId: _readString(data, 'salesRepId'),
      salesRepName: _readString(data, 'salesRepName'),
      createdByUid: _readString(data, 'createdByUid'),
      createdByName: _readString(data, 'createdByName'),
      createdByRole: _readString(data, 'createdByRole'),
      convertedInvoiceId: _readString(data, 'convertedInvoiceId'),
      convertedInvoiceNumber: _readString(data, 'convertedInvoiceNumber'),
      createdAt: _readDate(data, 'createdAt') ?? DateTime.now(),
      updatedAt: _readDate(data, 'updatedAt') ?? DateTime.now(),
      searchKeywords: _readStringList(data['searchKeywords']),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'companyId': companyId,
    'quotationNumber': quotationNumber,
    'quotationDate': Timestamp.fromDate(quotationDate),
    'validUntil': Timestamp.fromDate(validUntil),
    'customerId': customerId,
    'customerSnapshot': customerSnapshot?.toMap(),
    'items': items.map((item) => item.toMap()).toList(growable: false),
    'subtotal': subtotal,
    'totalDiscount': totalDiscount,
    'totalTax': totalTax,
    'grandTotal': grandTotal,
    'notes': notes,
    'terms': terms,
    'status': status.value,
    'salesRepId': salesRepId,
    'salesRepName': salesRepName,
    'createdByUid': createdByUid,
    'createdByName': createdByName,
    'createdByRole': createdByRole,
    'convertedInvoiceId': convertedInvoiceId,
    'convertedInvoiceNumber': convertedInvoiceNumber,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
    'searchKeywords': searchKeywords,
  };

  QuotationModel copyWith({
    String? id,
    String? companyId,
    String? quotationNumber,
    DateTime? quotationDate,
    DateTime? validUntil,
    String? customerId,
    InvoiceCustomerSnapshot? customerSnapshot,
    List<QuotationItemModel>? items,
    double? subtotal,
    double? totalDiscount,
    double? totalTax,
    double? grandTotal,
    String? notes,
    String? terms,
    QuotationStatus? status,
    String? salesRepId,
    String? salesRepName,
    String? createdByUid,
    String? createdByName,
    String? createdByRole,
    String? convertedInvoiceId,
    String? convertedInvoiceNumber,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? searchKeywords,
  }) {
    return QuotationModel(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      quotationNumber: quotationNumber ?? this.quotationNumber,
      quotationDate: quotationDate ?? this.quotationDate,
      validUntil: validUntil ?? this.validUntil,
      customerId: customerId ?? this.customerId,
      customerSnapshot: customerSnapshot ?? this.customerSnapshot,
      items: items ?? this.items,
      subtotal: subtotal ?? this.subtotal,
      totalDiscount: totalDiscount ?? this.totalDiscount,
      totalTax: totalTax ?? this.totalTax,
      grandTotal: grandTotal ?? this.grandTotal,
      notes: notes ?? this.notes,
      terms: terms ?? this.terms,
      status: status ?? this.status,
      salesRepId: salesRepId ?? this.salesRepId,
      salesRepName: salesRepName ?? this.salesRepName,
      createdByUid: createdByUid ?? this.createdByUid,
      createdByName: createdByName ?? this.createdByName,
      createdByRole: createdByRole ?? this.createdByRole,
      convertedInvoiceId: convertedInvoiceId ?? this.convertedInvoiceId,
      convertedInvoiceNumber:
          convertedInvoiceNumber ?? this.convertedInvoiceNumber,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      searchKeywords: searchKeywords ?? this.searchKeywords,
    );
  }

  QuotationModel withSearchFields() {
    final number = _normalize(quotationNumber);
    final customerName = _normalize(customerSnapshot?.name ?? '');
    final customerPhone = _normalize(customerSnapshot?.phone ?? '');
    final repName = _normalize(salesRepName);
    final itemNames = items
        .map((item) => _normalize(item.itemName))
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final dateString = formatDateForSearch(quotationDate);
    return copyWith(
      searchKeywords: CustomerModel.buildSearchKeywords([
        number,
        customerName,
        customerPhone,
        repName,
        dateString,
        ...itemNames,
      ]),
    );
  }

  static String formatDateForSearch(DateTime date) {
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
