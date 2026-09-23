import 'package:fatoora/core/localization/translation.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/admin/audit_log/controllers/audit_log_controller.dart';
import 'package:fatoora/features/admin/audit_log/data/models/audit_event_model.dart';
import 'package:fatoora/features/admin/audit_log/data/repositories/audit_log_repository.dart'
    as audit_data;
import 'package:fatoora/features/admin/audit_log/presentation/pages/audit_log_page.dart';
import 'package:fatoora/features/auth/admin_users/controller/admin_users_controller.dart';
import 'package:fatoora/features/auth/admin_users/view/screen/admin_users_screen.dart';
import 'package:fatoora/features/auth/data/models/app_user_model.dart';
import 'package:fatoora/features/auth/data/repositories/admin_auth_repository.dart';
import 'package:fatoora/features/shared/business/business_user_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(Get.reset);

  testWidgets('Audit 320px 2x keeps compact filter and complete event card', (
    tester,
  ) async {
    await _pumpAudit(tester, const Size(320, 640), textScale: 2);
    expect(find.byKey(const ValueKey('audit-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('audit-filter-button')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('INV-2026-000001'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('INV-2026-000001'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Audit filter sheet and RTL do not overflow', (tester) async {
    await _pumpAudit(tester, const Size(390, 800), locale: const Locale('ar'));
    await tester.tap(find.byKey(const ValueKey('audit-filter-button')));
    await tester.pumpAndSettle();
    expect(find.text('تصفية'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Pending Users 320px 2x retains approval actions', (
    tester,
  ) async {
    await _pumpUsers(tester, const Size(320, 640), textScale: 2);
    expect(find.text('Pending User'), findsOneWidget);
    expect(find.text('Approve as sales rep'), findsOneWidget);
    expect(find.text('Approve as admin'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Pending Users desktop keeps table and actions', (tester) async {
    await _pumpUsers(tester, const Size(1366, 900));
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('Pending User'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpAudit(
  WidgetTester tester,
  Size size, {
  Locale locale = const Locale('en'),
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({
    'companyId': 'default_company',
    'role': 'admin',
    'uid': 'admin-1',
  });
  Get.reset();
  final services = await MyServices().init();
  Get.put<MyServices>(services);
  final controller = AuditLogController(
    repository: _AuditRepoFake(),
    contextLoader: () async => const BusinessUserContext(
      uid: 'admin-1',
      name: 'Admin',
      email: 'admin@example.test',
      phone: '',
      role: 'admin',
      companyId: 'default_company',
      active: true,
      approvalStatus: 'approved',
    ),
  );
  Get.put<AuditLogController>(controller);
  await tester.pumpWidget(
    GetMaterialApp(
      locale: locale,
      translations: MyTranslation(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const AuditLogPage(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpUsers(
  WidgetTester tester,
  Size size, {
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({
    'companyId': 'default_company',
    'role': 'admin',
    'uid': 'admin-1',
  });
  Get.reset();
  final services = await MyServices().init();
  Get.put<MyServices>(services);
  Get.put<AdminUsersController>(
    AdminUsersController(repository: _UsersRepoFake(), myServices: services),
  );
  await tester.pumpWidget(
    GetMaterialApp(
      locale: const Locale('en'),
      translations: MyTranslation(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const AdminUsersScreen(),
    ),
  );
  await tester.pumpAndSettle();
}

class _AuditRepoFake implements audit_data.AuditLogDataSource {
  @override
  Future<audit_data.AuditLogPage> fetchPage({
    required String companyId,
    audit_data.AuditLogFilter filter = const audit_data.AuditLogFilter(),
    after,
  }) async =>
      audit_data.AuditLogPage(events: [_event()], cursor: null, hasMore: false);

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

AuditEventModel _event() => AuditEventModel(
  id: 'event-1',
  schemaVersion: 1,
  occurredAt: DateTime.utc(2026, 9, 23),
  eventLevel: 'business',
  category: 'sales',
  action: 'invoice.confirmed',
  severity: 'info',
  result: 'success',
  displayInTimeline: true,
  operationId: 'invoice-1',
  actorUid: 'admin-1',
  actorName: 'Admin',
  actorRole: 'admin',
  source: 'web',
  platform: 'web',
  entityType: 'invoice',
  entityId: 'invoice-1',
  entityNumber: 'INV-2026-000001',
  entityLabel: '',
  customerName: 'Acme Pumps',
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

class _UsersRepoFake implements AdminAuthRepository {
  @override
  Future<List<AppUserModel>> fetchPendingUsers() async => [_pendingUser()];
  @override
  Future<List<AppUserModel>> fetchSalesReps() async => const [];
  @override
  Future<List<AppUserModel>> fetchAdmins() async => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AppUserModel _pendingUser() {
  final now = DateTime(2026, 9, 23);
  return AppUserModel(
    uid: 'pending-1',
    name: 'Pending User',
    email: 'pending@example.test',
    phone: '0790000000',
    photoUrl: '',
    role: 'pending_sales_rep',
    active: false,
    approvalStatus: 'pending',
    companyId: 'default_company',
    createdAt: now,
    updatedAt: now,
  );
}
