import 'package:cloud_firestore/cloud_firestore.dart';

class AuditEventModel {
  const AuditEventModel({
    required this.id,
    required this.schemaVersion,
    required this.occurredAt,
    required this.eventLevel,
    required this.category,
    required this.action,
    required this.severity,
    required this.result,
    required this.displayInTimeline,
    required this.operationId,
    required this.actorUid,
    required this.actorName,
    required this.actorRole,
    required this.source,
    required this.platform,
    required this.entityType,
    required this.entityId,
    required this.entityNumber,
    required this.entityLabel,
    required this.customerName,
    required this.salesRepName,
    required this.summaryKey,
    required this.summaryArgs,
    required this.changedFields,
    required this.changes,
    required this.financialImpact,
    required this.inventoryImpact,
    required this.relatedEntities,
    required this.reason,
    required this.notes,
    required this.metadata,
  });

  final String id;
  final int schemaVersion;
  final DateTime occurredAt;
  final String eventLevel;
  final String category;
  final String action;
  final String severity;
  final String result;
  final bool displayInTimeline;
  final String operationId;
  final String actorUid;
  final String actorName;
  final String actorRole;
  final String source;
  final String platform;
  final String entityType;
  final String entityId;
  final String entityNumber;
  final String entityLabel;
  final String customerName;
  final String salesRepName;
  final String summaryKey;
  final Map<String, dynamic> summaryArgs;
  final List<String> changedFields;
  final List<AuditFieldChange> changes;
  final Map<String, dynamic> financialImpact;
  final List<Map<String, dynamic>> inventoryImpact;
  final List<Map<String, dynamic>> relatedEntities;
  final String reason;
  final String notes;
  final Map<String, dynamic> metadata;

  String get entityDisplay =>
      entityNumber.isNotEmpty ? entityNumber : entityLabel;
  bool get hasFinancialImpact => financialImpact.values.any(_meaningful);
  bool get hasInventoryImpact => inventoryImpact.isNotEmpty;

  factory AuditEventModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final timestamp = data['occurredAt'];
    return AuditEventModel(
      id: snapshot.id,
      schemaVersion: _int(data['schemaVersion'], fallback: 1),
      occurredAt: timestamp is Timestamp
          ? timestamp.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
      eventLevel: _string(data['eventLevel']),
      category: _string(data['category']),
      action: _string(data['action']),
      severity: _string(data['severity']),
      result: _string(data['result']),
      displayInTimeline: data['displayInTimeline'] == true,
      operationId: _string(data['operationId']),
      actorUid: _string(data['actorUid']),
      actorName: _string(data['actorName']),
      actorRole: _string(data['actorRole']),
      source: _string(data['source']),
      platform: _string(data['platform']),
      entityType: _string(data['entityType']),
      entityId: _string(data['entityId']),
      entityNumber: _string(data['entityNumber']),
      entityLabel: _string(data['entityLabel']),
      customerName: _string(data['customerNameSnapshot']),
      salesRepName: _string(data['salesRepNameSnapshot']),
      summaryKey: _string(data['summaryKey']),
      summaryArgs: _map(data['summaryArgs']),
      changedFields: _list(
        data['changedFields'],
      ).map((value) => value.toString()).toList(growable: false),
      changes: _list(data['changes'])
          .whereType<Map>()
          .map((value) => AuditFieldChange.fromMap(_map(value)))
          .toList(growable: false),
      financialImpact: _map(data['financialImpact']),
      inventoryImpact: _list(
        data['inventoryImpact'],
      ).whereType<Map>().map(_map).toList(growable: false),
      relatedEntities: _list(
        data['relatedEntities'],
      ).whereType<Map>().map(_map).toList(growable: false),
      reason: _string(data['reason']),
      notes: _string(data['notes']),
      metadata: _map(data['metadata']),
    );
  }

  static bool _meaningful(Object? value) =>
      value != null && value != '' && value != 0 && value != 0.0;
}

class AuditFieldChange {
  const AuditFieldChange({
    required this.field,
    required this.before,
    required this.after,
  });

  final String field;
  final Object? before;
  final Object? after;

  factory AuditFieldChange.fromMap(Map<String, dynamic> data) =>
      AuditFieldChange(
        field: _string(data['field']),
        before: data['before'],
        after: data['after'],
      );
}

String _string(Object? value) => value is String ? value : '';
int _int(Object? value, {required int fallback}) =>
    value is num ? value.toInt() : fallback;
List<dynamic> _list(Object? value) => value is List ? value : const [];
Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};
