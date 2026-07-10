import 'package:cloud_firestore/cloud_firestore.dart';

enum ExpenseCategory {
  fuel('fuel'),
  parking('parking'),
  maintenance('maintenance'),
  delivery('delivery'),
  meals('meals'),
  office('office'),
  utilities('utilities'),
  salary('salary'),
  rent('rent'),
  other('other');

  const ExpenseCategory(this.value);
  final String value;

  static ExpenseCategory fromValue(String value) {
    return ExpenseCategory.values.firstWhere(
      (item) => item.value == value.trim(),
      orElse: () => ExpenseCategory.other,
    );
  }

  String get labelKey => 'expense_category_$value';
}

enum ExpenseFundingSource {
  companyCash('company_cash'),
  repCollectedCash('rep_collected_cash'),
  personalCash('personal_cash');

  const ExpenseFundingSource(this.value);
  final String value;

  static ExpenseFundingSource fromValue(String value) {
    return ExpenseFundingSource.values.firstWhere(
      (item) => item.value == value.trim(),
      orElse: () => ExpenseFundingSource.personalCash,
    );
  }

  String get labelKey => 'expense_funding_$value';
}

enum ExpenseStatus {
  posted('posted'),
  pending('pending'),
  approved('approved'),
  rejected('rejected'),
  cancelled('cancelled');

  const ExpenseStatus(this.value);
  final String value;

  static ExpenseStatus fromValue(String value) {
    return ExpenseStatus.values.firstWhere(
      (item) => item.value == value.trim(),
      orElse: () => ExpenseStatus.pending,
    );
  }

  String get labelKey => 'expense_status_$value';
}

enum ExpenseReimbursementStatus {
  none('none'),
  payable('payable'),
  paid('paid');

  const ExpenseReimbursementStatus(this.value);
  final String value;

  static ExpenseReimbursementStatus fromValue(String value) {
    return ExpenseReimbursementStatus.values.firstWhere(
      (item) => item.value == value.trim(),
      orElse: () => ExpenseReimbursementStatus.none,
    );
  }

  String get labelKey => 'expense_reimbursement_$value';
}

class ExpenseModel {
  const ExpenseModel({
    required this.id,
    required this.companyId,
    required this.amount,
    required this.expenseDate,
    required this.category,
    required this.customCategoryName,
    required this.description,
    required this.paidByUid,
    required this.paidByName,
    required this.paidByRole,
    required this.salesRepId,
    required this.salesRepName,
    required this.paymentMethod,
    required this.fundingSource,
    required this.status,
    required this.cashMovementId,
    required this.reimbursementStatus,
    required this.approvedByUid,
    required this.approvedByName,
    required this.approvedAt,
    required this.rejectedByUid,
    required this.rejectedByName,
    required this.rejectedAt,
    required this.rejectionReason,
    required this.createdByUid,
    required this.createdByName,
    required this.createdByRole,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String companyId;
  final double amount;
  final DateTime expenseDate;
  final ExpenseCategory category;
  final String customCategoryName;
  final String description;
  final String paidByUid;
  final String paidByName;
  final String paidByRole;
  final String salesRepId;
  final String salesRepName;
  final String paymentMethod;
  final ExpenseFundingSource fundingSource;
  final ExpenseStatus status;
  final String cashMovementId;
  final ExpenseReimbursementStatus reimbursementStatus;
  final String approvedByUid;
  final String approvedByName;
  final DateTime? approvedAt;
  final String rejectedByUid;
  final String rejectedByName;
  final DateTime? rejectedAt;
  final String rejectionReason;
  final String createdByUid;
  final String createdByName;
  final String createdByRole;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isPending => status == ExpenseStatus.pending;
  bool get isPostedOrApproved =>
      status == ExpenseStatus.posted || status == ExpenseStatus.approved;
  bool get usesCompanyCash => fundingSource == ExpenseFundingSource.companyCash;
  bool get usesRepCollectedCash =>
      fundingSource == ExpenseFundingSource.repCollectedCash;
  bool get usesPersonalCash =>
      fundingSource == ExpenseFundingSource.personalCash;

  String get displayCategoryName =>
      category == ExpenseCategory.other && customCategoryName.isNotEmpty
      ? customCategoryName
      : category.labelKey;

  factory ExpenseModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const {};
    final now = DateTime.now();
    return ExpenseModel(
      id: _readString(data, 'id').isEmpty
          ? document.id
          : _readString(data, 'id'),
      companyId: _readString(data, 'companyId'),
      amount: _readDouble(data, 'amount'),
      expenseDate: _readDate(data, 'expenseDate') ?? now,
      category: ExpenseCategory.fromValue(_readString(data, 'category')),
      customCategoryName: _readString(data, 'customCategoryName'),
      description: _readString(data, 'description').isEmpty
          ? _readString(data, 'notes')
          : _readString(data, 'description'),
      paidByUid: _readString(data, 'paidByUid'),
      paidByName: _readString(data, 'paidByName'),
      paidByRole: _readString(data, 'paidByRole'),
      salesRepId: _readString(data, 'salesRepId'),
      salesRepName: _readString(data, 'salesRepName'),
      paymentMethod: _readString(data, 'paymentMethod').isEmpty
          ? 'cash'
          : _readString(data, 'paymentMethod'),
      fundingSource: ExpenseFundingSource.fromValue(
        _readString(data, 'fundingSource'),
      ),
      status: ExpenseStatus.fromValue(_readString(data, 'status')),
      cashMovementId: _readString(data, 'cashMovementId'),
      reimbursementStatus: ExpenseReimbursementStatus.fromValue(
        _readString(data, 'reimbursementStatus'),
      ),
      approvedByUid: _readString(data, 'approvedByUid'),
      approvedByName: _readString(data, 'approvedByName'),
      approvedAt: _readDate(data, 'approvedAt'),
      rejectedByUid: _readString(data, 'rejectedByUid'),
      rejectedByName: _readString(data, 'rejectedByName'),
      rejectedAt: _readDate(data, 'rejectedAt'),
      rejectionReason: _readString(data, 'rejectionReason'),
      createdByUid: _readString(data, 'createdByUid'),
      createdByName: _readString(data, 'createdByName'),
      createdByRole: _readString(data, 'createdByRole'),
      createdAt: _readDate(data, 'createdAt') ?? now,
      updatedAt:
          _readDate(data, 'updatedAt') ?? _readDate(data, 'createdAt') ?? now,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'companyId': companyId,
    'amount': amount,
    'expenseDate': Timestamp.fromDate(expenseDate),
    'category': category.value,
    'categoryName': category.value,
    'customCategoryName': customCategoryName,
    'description': description,
    'notes': description,
    'paidByUid': paidByUid,
    'paidByName': paidByName,
    'paidByRole': paidByRole,
    'salesRepId': salesRepId,
    'salesRepName': salesRepName,
    'paymentMethod': paymentMethod,
    'fundingSource': fundingSource.value,
    'status': status.value,
    'cashMovementId': cashMovementId,
    'reimbursementStatus': reimbursementStatus.value,
    'approvedByUid': approvedByUid,
    'approvedByName': approvedByName,
    if (approvedAt != null) 'approvedAt': Timestamp.fromDate(approvedAt!),
    'rejectedByUid': rejectedByUid,
    'rejectedByName': rejectedByName,
    if (rejectedAt != null) 'rejectedAt': Timestamp.fromDate(rejectedAt!),
    'rejectionReason': rejectionReason,
    'createdByUid': createdByUid,
    'createdByName': createdByName,
    'createdByRole': createdByRole,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

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
}
