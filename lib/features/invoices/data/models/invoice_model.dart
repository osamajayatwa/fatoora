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
    required this.paymentType,
    required this.paymentStatus,
    required this.hasReceivedPayment,
    required this.invoiceDate,
    required this.dueDate,
    required this.createdAt,
    required this.updatedAt,
    required this.createdByUid,
    required this.createdByName,
    required this.createdByRole,
    required this.salesRepId,
    required this.salesRepName,
    required this.customerId,
    this.customerSnapshot,
    required this.items,
    required this.subtotal,
    required this.totalDiscount,
    required this.totalTax,
    required this.grandTotal,
    required this.paidAmount,
    required this.remainingAmount,
    required this.notes,
    required this.paymentMethod,
    required this.isLocked,
    required this.financialPosted,
    this.financialPostedAt,
    required this.financialPostedByUid,
    required this.financialPostedByName,
    required this.customerTransactionIds,
    required this.cashMovementIds,
    required this.inventoryPosted,
    this.inventoryPostedAt,
    required this.inventoryPostedByUid,
    required this.inventoryPostedByName,
    required this.inventoryMovementIds,
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
  final PaymentType paymentType;
  final PaymentStatus paymentStatus;
  final bool hasReceivedPayment;
  final DateTime invoiceDate;
  final DateTime dueDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdByUid;
  final String createdByName;
  final String createdByRole;
  final String salesRepId;
  final String salesRepName;
  final String customerId;
  final InvoiceCustomerSnapshot? customerSnapshot;
  final List<InvoiceItemSnapshot> items;
  final double subtotal;
  final double totalDiscount;
  final double totalTax;
  final double grandTotal;
  final double paidAmount;
  final double remainingAmount;
  final String notes;
  final String paymentMethod;
  final bool isLocked;
  final bool financialPosted;
  final DateTime? financialPostedAt;
  final String financialPostedByUid;
  final String financialPostedByName;
  final List<String> customerTransactionIds;
  final List<String> cashMovementIds;
  final bool inventoryPosted;
  final DateTime? inventoryPostedAt;
  final String inventoryPostedByUid;
  final String inventoryPostedByName;
  final List<String> inventoryMovementIds;
  final List<String> searchKeywords;
  final String customerNameLower;
  final List<String> itemNamesLower;
  final String invoiceNumberLower;
  final String dateString;
  final InvoiceGovernmentModel? government;

  bool get isElectronic => invoiceType == InvoiceType.electronic;
  bool get isDraft => invoiceStatus == InvoiceStatus.draft;
  bool get isFinancial =>
      invoiceStatus == InvoiceStatus.confirmed ||
      invoiceStatus == InvoiceStatus.accepted;
  bool get canDelete => invoiceStatus == InvoiceStatus.draft;
  bool get canEdit =>
      !isLocked &&
      (invoiceStatus == InvoiceStatus.draft ||
          invoiceStatus == InvoiceStatus.rejected);

  factory InvoiceModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    return InvoiceModel.fromMap(document.data() ?? const {}, id: document.id);
  }

  factory InvoiceModel.fromMap(Map<String, dynamic> data, {String? id}) {
    final items = _readList(
      data['items'],
    ).map(InvoiceItemSnapshot.fromMap).toList(growable: false);
    final invoiceDate = _readDate(data, 'invoiceDate') ?? DateTime.now();
    final paymentType = paymentTypeFromValue(
      data['paymentType'] ?? data['paymentMethod'],
    );
    final grandTotal = _readDouble(data, 'grandTotal');
    final paidAmount = _readDouble(data, 'paidAmount');
    final remainingAmount = _readDouble(data, 'remainingAmount');
    return InvoiceModel(
      id: id ?? _readString(data, 'id'),
      companyId: _readString(data, 'companyId'),
      invoiceNumber: _readString(data, 'invoiceNumber'),
      invoiceType: invoiceTypeFromValue(data['invoiceType']),
      invoiceStatus: invoiceStatusFromValue(data['invoiceStatus']),
      paymentType: paymentType,
      paymentStatus: paymentStatusFromValue(
        data['paymentStatus'] ??
            _paymentStatusValue(paymentType, grandTotal, paidAmount),
      ),
      hasReceivedPayment: _readBool(
        data,
        'hasReceivedPayment',
        fallback: paidAmount > 0,
      ),
      invoiceDate: invoiceDate,
      dueDate: _readDate(data, 'dueDate') ?? invoiceDate,
      createdAt: _readDate(data, 'createdAt') ?? DateTime.now(),
      updatedAt: _readDate(data, 'updatedAt') ?? DateTime.now(),
      createdByUid: _readString(data, 'createdByUid'),
      createdByName: _readString(data, 'createdByName'),
      createdByRole: _readString(data, 'createdByRole'),
      salesRepId: _readString(data, 'salesRepId').isEmpty
          ? _readString(data, 'createdByUid')
          : _readString(data, 'salesRepId'),
      salesRepName: _readString(data, 'salesRepName').isEmpty
          ? _readString(data, 'createdByName')
          : _readString(data, 'salesRepName'),
      customerId: _readString(data, 'customerId'),
      customerSnapshot: data['customerSnapshot'] == null
          ? null
          : InvoiceCustomerSnapshot.fromMap(data['customerSnapshot']),
      items: items,
      subtotal: _readDouble(data, 'subtotal'),
      totalDiscount: _readDouble(data, 'totalDiscount'),
      totalTax: _readDouble(data, 'totalTax'),
      grandTotal: grandTotal,
      paidAmount: paidAmount,
      remainingAmount: remainingAmount,
      notes: _readString(data, 'notes'),
      paymentMethod: _readString(data, 'paymentMethod').isEmpty
          ? paymentType.value
          : _readString(data, 'paymentMethod'),
      isLocked: _readBool(data, 'isLocked'),
      financialPosted: _readBool(data, 'financialPosted'),
      financialPostedAt: _readDate(data, 'financialPostedAt'),
      financialPostedByUid: _readString(data, 'financialPostedByUid'),
      financialPostedByName: _readString(data, 'financialPostedByName'),
      customerTransactionIds: _readStringList(data['customerTransactionIds']),
      cashMovementIds: _readStringList(data['cashMovementIds']),
      inventoryPosted: _readBool(data, 'inventoryPosted'),
      inventoryPostedAt: _readDate(data, 'inventoryPostedAt'),
      inventoryPostedByUid: _readString(data, 'inventoryPostedByUid'),
      inventoryPostedByName: _readString(data, 'inventoryPostedByName'),
      inventoryMovementIds: _readStringList(data['inventoryMovementIds']),
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
    'paymentType': paymentType.value,
    'paymentStatus': paymentStatus.value,
    'hasReceivedPayment': hasReceivedPayment,
    'invoiceDate': Timestamp.fromDate(invoiceDate),
    'dueDate': Timestamp.fromDate(dueDate),
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
    'createdByUid': createdByUid,
    'createdByName': createdByName,
    'createdByRole': createdByRole,
    'salesRepId': salesRepId,
    'salesRepName': salesRepName,
    'customerId': customerId,
    'customerSnapshot': customerSnapshot?.toMap(),
    'items': items.map((item) => item.toMap()).toList(),
    'subtotal': subtotal,
    'totalDiscount': totalDiscount,
    'totalTax': totalTax,
    'grandTotal': grandTotal,
    'paidAmount': paidAmount,
    'remainingAmount': remainingAmount,
    'notes': notes,
    'paymentMethod': paymentMethod,
    'isLocked': isLocked,
    'financialPosted': financialPosted,
    'financialPostedAt': financialPostedAt == null
        ? null
        : Timestamp.fromDate(financialPostedAt!),
    'financialPostedByUid': financialPostedByUid,
    'financialPostedByName': financialPostedByName,
    'customerTransactionIds': customerTransactionIds,
    'cashMovementIds': cashMovementIds,
    'inventoryPosted': inventoryPosted,
    'inventoryPostedAt': inventoryPostedAt == null
        ? null
        : Timestamp.fromDate(inventoryPostedAt!),
    'inventoryPostedByUid': inventoryPostedByUid,
    'inventoryPostedByName': inventoryPostedByName,
    'inventoryMovementIds': inventoryMovementIds,
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
    PaymentType? paymentType,
    PaymentStatus? paymentStatus,
    bool? hasReceivedPayment,
    DateTime? invoiceDate,
    DateTime? dueDate,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdByUid,
    String? createdByName,
    String? createdByRole,
    String? salesRepId,
    String? salesRepName,
    String? customerId,
    InvoiceCustomerSnapshot? customerSnapshot,
    List<InvoiceItemSnapshot>? items,
    double? subtotal,
    double? totalDiscount,
    double? totalTax,
    double? grandTotal,
    double? paidAmount,
    double? remainingAmount,
    String? notes,
    String? paymentMethod,
    bool? isLocked,
    bool? financialPosted,
    DateTime? financialPostedAt,
    bool clearFinancialPostedAt = false,
    String? financialPostedByUid,
    String? financialPostedByName,
    List<String>? customerTransactionIds,
    List<String>? cashMovementIds,
    bool? inventoryPosted,
    DateTime? inventoryPostedAt,
    bool clearInventoryPostedAt = false,
    String? inventoryPostedByUid,
    String? inventoryPostedByName,
    List<String>? inventoryMovementIds,
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
      paymentType: paymentType ?? this.paymentType,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      hasReceivedPayment: hasReceivedPayment ?? this.hasReceivedPayment,
      invoiceDate: invoiceDate ?? this.invoiceDate,
      dueDate: dueDate ?? this.dueDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdByUid: createdByUid ?? this.createdByUid,
      createdByName: createdByName ?? this.createdByName,
      createdByRole: createdByRole ?? this.createdByRole,
      salesRepId: salesRepId ?? this.salesRepId,
      salesRepName: salesRepName ?? this.salesRepName,
      customerId: customerId ?? this.customerId,
      customerSnapshot: customerSnapshot ?? this.customerSnapshot,
      items: items ?? this.items,
      subtotal: subtotal ?? this.subtotal,
      totalDiscount: totalDiscount ?? this.totalDiscount,
      totalTax: totalTax ?? this.totalTax,
      grandTotal: grandTotal ?? this.grandTotal,
      paidAmount: paidAmount ?? this.paidAmount,
      remainingAmount: remainingAmount ?? this.remainingAmount,
      notes: notes ?? this.notes,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      isLocked: isLocked ?? this.isLocked,
      financialPosted: financialPosted ?? this.financialPosted,
      financialPostedAt: clearFinancialPostedAt
          ? null
          : financialPostedAt ?? this.financialPostedAt,
      financialPostedByUid: financialPostedByUid ?? this.financialPostedByUid,
      financialPostedByName:
          financialPostedByName ?? this.financialPostedByName,
      customerTransactionIds:
          customerTransactionIds ?? this.customerTransactionIds,
      cashMovementIds: cashMovementIds ?? this.cashMovementIds,
      inventoryPosted: inventoryPosted ?? this.inventoryPosted,
      inventoryPostedAt: clearInventoryPostedAt
          ? null
          : inventoryPostedAt ?? this.inventoryPostedAt,
      inventoryPostedByUid: inventoryPostedByUid ?? this.inventoryPostedByUid,
      inventoryPostedByName:
          inventoryPostedByName ?? this.inventoryPostedByName,
      inventoryMovementIds: inventoryMovementIds ?? this.inventoryMovementIds,
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
    final customerPhone = _normalize(customerSnapshot?.phone ?? '');
    final itemNames = items
        .map((item) => _normalize(item.itemName))
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final numberLower = _normalize(invoiceNumber);
    final date = _formatDate(invoiceDate);
    final repName = _normalize(salesRepName);
    return copyWith(
      customerNameLower: customerLower,
      itemNamesLower: itemNames,
      invoiceNumberLower: numberLower,
      dateString: date,
      searchKeywords: buildSearchKeywords(
        invoiceNumber: numberLower,
        customerName: customerLower,
        customerPhone: customerPhone,
        salesRepName: repName,
        itemNames: itemNames,
        dateString: date,
      ),
    );
  }

  static List<String> buildSearchKeywords({
    required String invoiceNumber,
    required String customerName,
    required String customerPhone,
    required String salesRepName,
    required List<String> itemNames,
    required String dateString,
  }) {
    final keywords = <String>{};
    for (final value in [
      invoiceNumber,
      customerName,
      customerPhone,
      salesRepName,
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

  static String _paymentStatusValue(
    PaymentType paymentType,
    double grandTotal,
    double paidAmount,
  ) {
    if (paymentType == PaymentType.credit || paidAmount <= 0) {
      return PaymentStatus.unpaid.value;
    }
    if (paidAmount >= grandTotal) return PaymentStatus.paid.value;
    return PaymentStatus.partiallyPaid.value;
  }

  static String _readString(Map<String, dynamic> data, String key) {
    final value = data[key];
    return value is String ? value.trim() : '';
  }

  static bool _readBool(
    Map<String, dynamic> data,
    String key, {
    bool fallback = false,
  }) {
    final value = data[key];
    return value is bool ? value : fallback;
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
