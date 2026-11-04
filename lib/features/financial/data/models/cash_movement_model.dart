import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fatoora/core/finance/exact_decimal.dart';

/// Read contract for existing cash movements. Unknown facts stay nullable/empty;
/// exact display never uses the compatibility double adapter.
class CashMovementModel {
  const CashMovementModel({
    required this.id,
    required this.companyId,
    required this.salesRepId,
    required this.salesRepName,
    required this.type,
    required this.movementType,
    required this.direction,
    required double? amount,
    required this.referenceId,
    required this.referenceNumber,
    required this.sourceCollection,
    required this.sourceId,
    required this.sourceNumber,
    required this.customerId,
    required this.customerName,
    required this.date,
    required this.notes,
    this.cashAccount = '',
    this.settlementId = '',
    required this.createdByUid,
    required this.createdByName,
    required this.createdByRole,
    required this.createdAt,
    this.storedDetails = const {},
  }) : _amount = amount;

  final String id, companyId, salesRepId, salesRepName;
  final String type, movementType, direction;
  final double? _amount;
  final String referenceId,
      referenceNumber,
      sourceCollection,
      sourceId,
      sourceNumber;
  final String customerId, customerName, notes, cashAccount, settlementId;
  final String createdByUid, createdByName, createdByRole;
  final DateTime? date, createdAt;
  final Map<String, dynamic> storedDetails;

  static const companyCashAccount = 'company_cash';
  static const repCashAccount = 'rep_cash';
  static const moneyScale =
      3; // Existing stored JOD semantics; no schema conversion.

  String detail(String key) => _string(storedDetails[key]);
  List<String> references(String key) => storedDetails[key] is List
      ? (storedDetails[key] as List)
            .whereType<String>()
            .where((s) => s.trim().isNotEmpty)
            .toList(growable: false)
      : const [];

  static BigInt? readMoneyUnits(Object? value) {
    if (value is! String && value is! num) return null;
    if (value is num &&
        (!value.isFinite || value.abs() > 9007199254740991 / 1000)) {
      return null;
    }
    try {
      return ExactDecimal.parseUnits(value.toString(), moneyScale);
    } on FormatException {
      return null;
    }
  }

  BigInt? get amountUnits {
    final units = readMoneyUnits(
      storedDetails.containsKey('amount') ? storedDetails['amount'] : _amount,
    );
    return units != null && units > BigInt.zero ? units : null;
  }

  BigInt? get balanceBeforeUnits =>
      readMoneyUnits(storedDetails['balanceBefore']);
  BigInt? get balanceAfterUnits =>
      readMoneyUnits(storedDetails['balanceAfter']);

  /// Compatibility only. Missing/invalid/unrepresentable values fail, never zero.
  double get amount {
    final units = amountUnits;
    if (units == null) throw const FormatException('Cash amount unavailable.');
    return ExactDecimal.fromUnits(units);
  }

  bool get isIn => direction == 'in';
  bool get isOut => direction == 'out';
  bool get hasDirection => isIn || isOut;
  double get signedAmount {
    if (!hasDirection) {
      throw const FormatException('Cash direction unavailable.');
    }
    return isOut ? -amount : amount;
  }

  bool get isCompanyCashAccount => cashAccount == companyCashAccount;
  bool get isRepCashAccount => cashAccount == repCashAccount;
  bool get hasCashAccount => cashAccount.isNotEmpty;

  /// Legacy cashAccount + salesRepId identifies the rep account, NOT the creator.
  /// Conflicting explicit holder metadata makes the holder ambiguous.
  String? get holderUid {
    if (!isRepCashAccount) return null;
    if (detail('holderUid').isNotEmpty &&
        detail('cashAccountSalesRepId').isNotEmpty &&
        detail('holderUid') != detail('cashAccountSalesRepId')) {
      return null;
    }
    final explicit = detail('holderUid').isNotEmpty
        ? detail('holderUid')
        : detail('cashAccountSalesRepId');
    if (explicit.isNotEmpty &&
        salesRepId.isNotEmpty &&
        explicit != salesRepId) {
      return null;
    }
    final holder = explicit.isNotEmpty ? explicit : salesRepId;
    return holder.isEmpty ? null : holder;
  }

  bool get hasVerifiedHolder {
    final kind = detail('holderType');
    if (isCompanyCashAccount) {
      return (kind.isEmpty || kind == 'company') &&
          (detail('holderUid').isEmpty || detail('holderUid') == companyId);
    }
    return isRepCashAccount &&
        holderUid != null &&
        (kind.isEmpty || kind == 'representative' || kind == 'sales_rep');
  }

  bool get _invoiceSource =>
      sourceCollection == 'invoices' && movementType == 'invoice_payment';
  bool get _receiptSource =>
      sourceCollection == 'receipts' && movementType == 'receipt';
  bool _hasPair(String idKey, String nameKey) =>
      detail(idKey).isNotEmpty || detail(nameKey).isNotEmpty;
  String get sellerId => _hasPair('sellerId', 'sellerName')
      ? detail('sellerId')
      : _invoiceSource
      ? salesRepId
      : '';
  String get sellerName => _hasPair('sellerId', 'sellerName')
      ? detail('sellerName')
      : _invoiceSource
      ? salesRepName
      : '';
  String get sourceCreatorUid =>
      _hasPair('sourceCreatedByUid', 'sourceCreatedByName')
      ? detail('sourceCreatedByUid')
      : _invoiceSource || _receiptSource
      ? createdByUid
      : '';
  String get sourceCreatorName =>
      _hasPair('sourceCreatedByUid', 'sourceCreatedByName')
      ? detail('sourceCreatedByName')
      : _invoiceSource || _receiptSource
      ? createdByName
      : '';
  String get collectorUid => _hasPair('collectorUid', 'collectorName')
      ? detail('collectorUid')
      : _receiptSource
      ? createdByUid
      : '';
  String get collectorName => _hasPair('collectorUid', 'collectorName')
      ? detail('collectorName')
      : _receiptSource
      ? createdByName
      : '';
  // These writers store the movement actor in createdBy*. Invoice confirmation
  // stores its original creator instead, so is excluded from this alias.
  bool get _legacyPostingActor => switch ((sourceCollection, movementType)) {
    ('receipts', 'receipt' || 'receipt_cancellation') ||
    ('expenses', 'expense') ||
    ('sales_returns', 'sales_return') ||
    ('settlements', 'settlement_to_admin') => true,
    _ => false,
  };
  String get postingActorUid => _hasPair('postedByUid', 'postedByName')
      ? detail('postedByUid')
      : _hasPair('actorUid', 'actorName')
      ? detail('actorUid')
      : _legacyPostingActor
      ? createdByUid
      : '';
  String get postingActorName => _hasPair('postedByUid', 'postedByName')
      ? detail('postedByName')
      : _hasPair('actorUid', 'actorName')
      ? detail('actorName')
      : _legacyPostingActor
      ? createdByName
      : '';
  String get paymentMethod {
    final explicit = detail('paymentMethod');
    final value = explicit.isNotEmpty ? explicit : detail('paymentType');
    return const [
          'cash',
          'bank',
          'check',
          'cheque',
          'cliq',
          'card',
        ].contains(value)
        ? value
        : '';
  }

  bool? get committedBalanceConsistent {
    final before = balanceBeforeUnits,
        after = balanceAfterUnits,
        units = amountUnits;
    if (before == null || after == null || units == null || !hasDirection) {
      return null;
    }
    return before + (isOut ? -units : units) == after;
  }

  bool get hasTraceGaps =>
      amountUnits == null ||
      !hasDirection ||
      !hasVerifiedHolder ||
      date == null ||
      createdAt == null ||
      committedBalanceConsistent == false;

  String get effectiveType => type.isNotEmpty ? type : movementType;
  String get effectiveReferenceNumber =>
      referenceNumber.isNotEmpty ? referenceNumber : sourceNumber;

  factory CashMovementModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) => CashMovementModel.fromMap(document.data() ?? const {}, id: document.id);

  factory CashMovementModel.fromMap(Map<String, dynamic> data, {String? id}) {
    String s(String key) => _string(data[key]);
    final rawAmount = data['amount'];
    return CashMovementModel(
      id: id ?? s('id'),
      companyId: s('companyId'),
      salesRepId: s('salesRepId'),
      salesRepName: s('salesRepName'),
      type: s('type'),
      movementType: s('movementType'),
      direction: s('direction').toLowerCase(),
      amount: rawAmount is num && rawAmount.isFinite
          ? rawAmount.toDouble()
          : null,
      referenceId: s('referenceId').isNotEmpty
          ? s('referenceId')
          : s('sourceId'),
      referenceNumber: s('referenceNumber').isNotEmpty
          ? s('referenceNumber')
          : s('sourceNumber'),
      sourceCollection: s('sourceCollection'),
      sourceId: s('sourceId'),
      sourceNumber: s('sourceNumber'),
      customerId: s('customerId'),
      customerName: s('customerName'),
      date: readDate(
        data.containsKey('date') ? data['date'] : data['movementDate'],
      ),
      notes: s('notes'),
      cashAccount: s('cashAccount'),
      settlementId: s('settlementId'),
      createdByUid: s('createdByUid'),
      createdByName: s('createdByName'),
      createdByRole: s('createdByRole'),
      createdAt: readDate(
        data.containsKey('createdAt') ? data['createdAt'] : data['recordedAt'],
      ),
      storedDetails: Map<String, dynamic>.unmodifiable(data),
    );
  }

  // Retained for existing callers; this phase adds no writer or new persisted fields.
  Map<String, dynamic> toMap() => {
    ...storedDetails,
    'id': id,
    'companyId': companyId,
    'salesRepId': salesRepId,
    'salesRepName': salesRepName,
    'type': type,
    'movementType': movementType,
    'direction': direction,
    if (!storedDetails.containsKey('amount') && _amount != null)
      'amount': _amount,
    'referenceId': referenceId,
    'referenceNumber': referenceNumber,
    'sourceCollection': sourceCollection,
    'sourceId': sourceId,
    'sourceNumber': sourceNumber,
    'customerId': customerId,
    'customerName': customerName,
    if (date != null) 'date': Timestamp.fromDate(date!),
    if (date != null) 'movementDate': Timestamp.fromDate(date!),
    'notes': notes,
    if (cashAccount.isNotEmpty) 'cashAccount': cashAccount,
    if (settlementId.isNotEmpty) 'settlementId': settlementId,
    'createdByUid': createdByUid,
    'createdByName': createdByName,
    'createdByRole': createdByRole,
    if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
  };

  static String _string(Object? value) => value is String ? value.trim() : '';
  static DateTime? readDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is! String) return null;
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,6})?)?(?:Z|[+-]\d{2}:\d{2})?)?$',
    ).firstMatch(value);
    if (match == null || match.end != value.length) return null;
    final y = int.parse(match[1]!),
        m = int.parse(match[2]!),
        d = int.parse(match[3]!);
    final check = DateTime.utc(y, m, d);
    if (check.year != y ||
        check.month != m ||
        check.day != d ||
        (match[4] != null && int.parse(match[4]!) > 23) ||
        (match[5] != null && int.parse(match[5]!) > 59) ||
        (match[6] != null && int.parse(match[6]!) > 59)) {
      return null;
    }
    return DateTime.tryParse(value);
  }
}
