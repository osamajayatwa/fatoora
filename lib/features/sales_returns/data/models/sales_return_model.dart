import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fatoora/features/invoices/data/models/invoice_customer_snapshot.dart';
import 'package:fatoora/features/sales_returns/data/models/sales_return_enums.dart';
import 'package:fatoora/features/sales_returns/data/models/sales_return_item_model.dart';

class SalesReturnModel {
  const SalesReturnModel({
    required this.id,
    required this.companyId,
    required this.returnNumber,
    required this.originalInvoiceId,
    required this.originalInvoiceNumber,
    required this.customerId,
    required this.customerSnapshot,
    required this.items,
    required this.subtotal,
    required this.totalTax,
    required this.grandTotal,
    required this.refundType,
    required this.returnDate,
    required this.reason,
    required this.status,
    required this.salesRepId,
    required this.salesRepName,
    required this.createdByUid,
    required this.createdByName,
    required this.createdByRole,
    required this.financialPosted,
    required this.inventoryPosted,
    this.financialPostedAt,
    this.inventoryPostedAt,
    required this.stockMovementIds,
    required this.customerTransactionIds,
    required this.cashMovementIds,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String companyId;
  final String returnNumber;
  final String originalInvoiceId;
  final String originalInvoiceNumber;
  final String customerId;
  final InvoiceCustomerSnapshot? customerSnapshot;
  final List<SalesReturnItemModel> items;
  final double subtotal;
  final double totalTax;
  final double grandTotal;
  final RefundType refundType;
  final DateTime returnDate;
  final String reason;
  final SalesReturnStatus status;
  final String salesRepId;
  final String salesRepName;
  final String createdByUid;
  final String createdByName;
  final String createdByRole;
  final bool financialPosted;
  final bool inventoryPosted;
  final DateTime? financialPostedAt;
  final DateTime? inventoryPostedAt;
  final List<String> stockMovementIds;
  final List<String> customerTransactionIds;
  final List<String> cashMovementIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isDraft => status == SalesReturnStatus.draft;
  bool get isConfirmed => status == SalesReturnStatus.confirmed;

  factory SalesReturnModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    return SalesReturnModel.fromMap(
      document.data() ?? const {},
      id: document.id,
    );
  }

  factory SalesReturnModel.fromMap(Map<String, dynamic> data, {String? id}) {
    final returnDate = _readDate(data, 'returnDate') ?? DateTime.now();
    return SalesReturnModel(
      id: id ?? _readString(data, 'id'),
      companyId: _readString(data, 'companyId'),
      returnNumber: _readString(data, 'returnNumber'),
      originalInvoiceId: _readString(data, 'originalInvoiceId'),
      originalInvoiceNumber: _readString(data, 'originalInvoiceNumber'),
      customerId: _readString(data, 'customerId'),
      customerSnapshot: data['customerSnapshot'] == null
          ? null
          : InvoiceCustomerSnapshot.fromMap(data['customerSnapshot']),
      items: _readList(
        data['items'],
      ).map(SalesReturnItemModel.fromMap).toList(growable: false),
      subtotal: _readDouble(data, 'subtotal'),
      totalTax: _readDouble(data, 'totalTax'),
      grandTotal: _readDouble(data, 'grandTotal'),
      refundType: refundTypeFromValue(data['refundType']),
      returnDate: returnDate,
      reason: _readString(data, 'reason'),
      status: salesReturnStatusFromValue(data['status']),
      salesRepId: _readString(data, 'salesRepId'),
      salesRepName: _readString(data, 'salesRepName'),
      createdByUid: _readString(data, 'createdByUid'),
      createdByName: _readString(data, 'createdByName'),
      createdByRole: _readString(data, 'createdByRole'),
      financialPosted: _readBool(data, 'financialPosted'),
      inventoryPosted: _readBool(data, 'inventoryPosted'),
      financialPostedAt: _readDate(data, 'financialPostedAt'),
      inventoryPostedAt: _readDate(data, 'inventoryPostedAt'),
      stockMovementIds: _readStringList(data['stockMovementIds']),
      customerTransactionIds: _readStringList(data['customerTransactionIds']),
      cashMovementIds: _readStringList(data['cashMovementIds']),
      createdAt: _readDate(data, 'createdAt') ?? DateTime.now(),
      updatedAt: _readDate(data, 'updatedAt') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'companyId': companyId,
    'returnNumber': returnNumber,
    'originalInvoiceId': originalInvoiceId,
    'originalInvoiceNumber': originalInvoiceNumber,
    'customerId': customerId,
    'customerSnapshot': customerSnapshot?.toMap(),
    'items': items.map((item) => item.toMap()).toList(growable: false),
    'subtotal': subtotal,
    'totalTax': totalTax,
    'grandTotal': grandTotal,
    'refundType': refundType.value,
    'returnDate': Timestamp.fromDate(returnDate),
    'reason': reason,
    'status': status.value,
    'salesRepId': salesRepId,
    'salesRepName': salesRepName,
    'createdByUid': createdByUid,
    'createdByName': createdByName,
    'createdByRole': createdByRole,
    'financialPosted': financialPosted,
    'inventoryPosted': inventoryPosted,
    'financialPostedAt': financialPostedAt == null
        ? null
        : Timestamp.fromDate(financialPostedAt!),
    'inventoryPostedAt': inventoryPostedAt == null
        ? null
        : Timestamp.fromDate(inventoryPostedAt!),
    'stockMovementIds': stockMovementIds,
    'customerTransactionIds': customerTransactionIds,
    'cashMovementIds': cashMovementIds,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  SalesReturnModel copyWith({
    String? id,
    String? companyId,
    String? returnNumber,
    String? originalInvoiceId,
    String? originalInvoiceNumber,
    String? customerId,
    InvoiceCustomerSnapshot? customerSnapshot,
    List<SalesReturnItemModel>? items,
    double? subtotal,
    double? totalTax,
    double? grandTotal,
    RefundType? refundType,
    DateTime? returnDate,
    String? reason,
    SalesReturnStatus? status,
    String? salesRepId,
    String? salesRepName,
    String? createdByUid,
    String? createdByName,
    String? createdByRole,
    bool? financialPosted,
    bool? inventoryPosted,
    DateTime? financialPostedAt,
    bool clearFinancialPostedAt = false,
    DateTime? inventoryPostedAt,
    bool clearInventoryPostedAt = false,
    List<String>? stockMovementIds,
    List<String>? customerTransactionIds,
    List<String>? cashMovementIds,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SalesReturnModel(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      returnNumber: returnNumber ?? this.returnNumber,
      originalInvoiceId: originalInvoiceId ?? this.originalInvoiceId,
      originalInvoiceNumber:
          originalInvoiceNumber ?? this.originalInvoiceNumber,
      customerId: customerId ?? this.customerId,
      customerSnapshot: customerSnapshot ?? this.customerSnapshot,
      items: items ?? this.items,
      subtotal: subtotal ?? this.subtotal,
      totalTax: totalTax ?? this.totalTax,
      grandTotal: grandTotal ?? this.grandTotal,
      refundType: refundType ?? this.refundType,
      returnDate: returnDate ?? this.returnDate,
      reason: reason ?? this.reason,
      status: status ?? this.status,
      salesRepId: salesRepId ?? this.salesRepId,
      salesRepName: salesRepName ?? this.salesRepName,
      createdByUid: createdByUid ?? this.createdByUid,
      createdByName: createdByName ?? this.createdByName,
      createdByRole: createdByRole ?? this.createdByRole,
      financialPosted: financialPosted ?? this.financialPosted,
      inventoryPosted: inventoryPosted ?? this.inventoryPosted,
      financialPostedAt: clearFinancialPostedAt
          ? null
          : financialPostedAt ?? this.financialPostedAt,
      inventoryPostedAt: clearInventoryPostedAt
          ? null
          : inventoryPostedAt ?? this.inventoryPostedAt,
      stockMovementIds: stockMovementIds ?? this.stockMovementIds,
      customerTransactionIds:
          customerTransactionIds ?? this.customerTransactionIds,
      cashMovementIds: cashMovementIds ?? this.cashMovementIds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static String _readString(Map<String, dynamic> data, String key) {
    final value = data[key];
    return value is String ? value.trim() : '';
  }

  static bool _readBool(Map<String, dynamic> data, String key) {
    final value = data[key];
    return value is bool && value;
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
