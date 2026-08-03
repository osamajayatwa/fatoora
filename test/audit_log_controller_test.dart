import 'package:fatoora/features/admin/audit_log/controllers/audit_log_controller.dart';
import 'package:fatoora/features/admin/audit_log/data/models/audit_event_model.dart';
import 'package:fatoora/features/admin/audit_log/data/repositories/audit_log_repository.dart';
import 'package:fatoora/features/shared/business/business_user_context.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'audit controller uses cursor pages without replacing earlier events',
    () async {
      final repository = _FakeAuditRepository();
      final controller = AuditLogController(
        repository: repository,
        contextLoader: _adminContext,
      );

      await controller.load();
      expect(controller.events.map((event) => event.id), ['one']);
      expect(controller.hasMore, isTrue);

      await controller.loadMore();
      expect(controller.events.map((event) => event.id), ['one', 'two']);
      expect(controller.hasMore, isFalse);
      expect(repository.pageCalls, 2);
    },
  );

  test('audit controller search is scoped to loaded snapshots', () async {
    final controller = AuditLogController(
      repository: _FakeAuditRepository(),
      contextLoader: _adminContext,
    );
    await controller.load();
    controller.search('invoice');
    expect(controller.visibleEvents, hasLength(1));
    controller.search('missing actor');
    expect(controller.visibleEvents, isEmpty);
  });
}

Future<BusinessUserContext> _adminContext() async => const BusinessUserContext(
  uid: 'admin',
  name: 'Admin',
  email: 'admin@example.test',
  phone: '',
  role: 'admin',
  companyId: 'default_company',
  active: true,
  approvalStatus: 'approved',
);

class _FakeAuditRepository implements AuditLogDataSource {
  int pageCalls = 0;

  @override
  Future<AuditLogPage> fetchPage({
    required String companyId,
    AuditLogFilter filter = const AuditLogFilter(),
    after,
  }) async {
    pageCalls++;
    return AuditLogPage(
      events: [_event(pageCalls == 1 ? 'one' : 'two')],
      cursor: null,
      hasMore: pageCalls == 1,
    );
  }

  @override
  Future<List<AuditEventModel>> fetchEntityTimeline({
    required String companyId,
    required String entityType,
    required String entityId,
    int limit = 20,
  }) async => const [];

  @override
  Future<List<AuditEventModel>> fetchOperationEvents({
    required String companyId,
    required String operationId,
  }) async => const [];
}

AuditEventModel _event(String id) => AuditEventModel(
  id: id,
  schemaVersion: 1,
  occurredAt: DateTime.utc(2026, 7, 29),
  eventLevel: 'business',
  category: 'sales',
  action: 'invoice.confirmed',
  severity: 'info',
  result: 'success',
  displayInTimeline: true,
  operationId: 'invoice-1',
  actorUid: 'admin',
  actorName: 'Admin',
  actorRole: 'admin',
  source: 'web',
  platform: 'web',
  entityType: 'invoice',
  entityId: 'invoice-1',
  entityNumber: 'INV-2026-000001',
  entityLabel: '',
  customerName: 'Customer',
  salesRepName: '',
  summaryKey: 'invoice.confirmed',
  summaryArgs: const {},
  changedFields: const ['invoiceStatus'],
  changes: const [],
  financialImpact: const {'documentTotal': 10},
  inventoryImpact: const [],
  relatedEntities: const [],
  reason: '',
  notes: '',
  metadata: const {},
);
