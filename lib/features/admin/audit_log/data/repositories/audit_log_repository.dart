import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fatoora/core/data/firestore_query_pager.dart';
import 'package:fatoora/features/admin/audit_log/data/models/audit_event_model.dart';

class AuditLogFilter {
  const AuditLogFilter({this.field, this.value, this.from, this.to});

  final String? field;
  final String? value;
  final DateTime? from;
  final DateTime? to;

  bool get hasField => field != null && value != null && value!.isNotEmpty;
}

class AuditLogPage {
  const AuditLogPage({
    required this.events,
    required this.cursor,
    required this.hasMore,
  });

  final List<AuditEventModel> events;
  final DocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool hasMore;
}

abstract interface class AuditLogDataSource {
  Future<AuditLogPage> fetchPage({
    required String companyId,
    AuditLogFilter filter = const AuditLogFilter(),
    DocumentSnapshot<Map<String, dynamic>>? after,
  });

  Future<List<AuditEventModel>> fetchOperationEvents({
    required String companyId,
    required String operationId,
  });

  Future<List<AuditEventModel>> fetchEntityTimeline({
    required String companyId,
    required String entityType,
    required String entityId,
    int limit = 20,
  });
}

class AuditLogRepository implements AuditLogDataSource {
  AuditLogRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  static const int pageSize = 50;

  CollectionReference<Map<String, dynamic>> _events(String companyId) =>
      _firestore
          .collection('companies')
          .doc(companyId)
          .collection('audit_events');

  @override
  Future<AuditLogPage> fetchPage({
    required String companyId,
    AuditLogFilter filter = const AuditLogFilter(),
    DocumentSnapshot<Map<String, dynamic>>? after,
  }) async {
    Query<Map<String, dynamic>> query = _events(
      companyId,
    ).where('displayInTimeline', isEqualTo: true);
    if (filter.hasField) {
      query = query.where(filter.field!, isEqualTo: filter.value);
    }
    if (filter.from != null) {
      query = query.where(
        'occurredAt',
        isGreaterThanOrEqualTo: Timestamp.fromDate(filter.from!.toUtc()),
      );
    }
    if (filter.to != null) {
      query = query.where(
        'occurredAt',
        isLessThan: Timestamp.fromDate(filter.to!.toUtc()),
      );
    }
    query = query
        .orderBy('occurredAt', descending: true)
        .orderBy(FieldPath.documentId, descending: true)
        .limit(pageSize);
    if (after != null) query = query.startAfterDocument(after);
    final snapshot = await query.get();
    return AuditLogPage(
      events: snapshot.docs
          .map(AuditEventModel.fromFirestore)
          .toList(growable: false),
      cursor: snapshot.docs.isEmpty ? null : snapshot.docs.last,
      hasMore: snapshot.docs.length == pageSize,
    );
  }

  @override
  Future<List<AuditEventModel>> fetchOperationEvents({
    required String companyId,
    required String operationId,
  }) async {
    if (operationId.isEmpty) return const [];
    final documents = await _events(companyId)
        .where('operationId', isEqualTo: operationId)
        .orderBy('occurredAt')
        .orderBy(FieldPath.documentId)
        .getAllPages();
    return documents.map(AuditEventModel.fromFirestore).toList(growable: false);
  }

  @override
  Future<List<AuditEventModel>> fetchEntityTimeline({
    required String companyId,
    required String entityType,
    required String entityId,
    int limit = 20,
  }) async {
    final snapshot = await _events(companyId)
        .where('entityType', isEqualTo: entityType)
        .where('entityId', isEqualTo: entityId)
        .orderBy('occurredAt', descending: true)
        .limit(limit)
        .get();
    return snapshot.docs
        .map(AuditEventModel.fromFirestore)
        .toList(growable: false);
  }
}
