import 'dart:async';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/data/firestore_query_pager.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/rep_inventory/controllers/rep_inventory_controllers.dart';
import 'package:fatoora/features/rep_inventory/data/models/inventory_transfer_model.dart';
import 'package:fatoora/features/rep_inventory/data/models/rep_inventory_balance_model.dart';
import 'package:fatoora/features/rep_inventory/data/models/rep_inventory_enums.dart';
import 'package:fatoora/features/rep_inventory/data/models/rep_inventory_movement_model.dart';
import 'package:fatoora/features/rep_inventory/data/repositories/rep_inventory_repository.dart';
import 'package:fatoora/features/shared/business/business_user_context.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(Get.reset);

  test(
    'repository owner resolution never accepts another rep or inactive user',
    () {
      expect(repInventoryOwnerId(_user('sales_rep'), 'rep-b'), 'rep-a');
      expect(repInventoryOwnerId(_user('admin'), 'rep-b'), 'rep-b');
      expect(
        () => repInventoryOwnerId(_user('admin'), ''),
        throwsA(isA<RepInventoryRepositoryException>()),
      );
      expect(
        () => repInventoryOwnerId(_user('sales_rep', active: false), 'rep-a'),
        throwsA(isA<RepInventoryRepositoryException>()),
      );
    },
  );

  test(
    'custody pages preserve ownership, cursor, quantities and full-dataset KPIs',
    () async {
      final repo = _Repository();
      final controller = await _controller(repo);
      controller.selectedSalesRepId = 'rep-b';
      await controller.load();
      expect(controller.selectedSalesRepId, 'rep-a');
      expect(controller.summary.itemCount, 100);
      expect(controller.summary.totalQuantity, 321);
      expect(controller.balances.single.quantity, 4);
      expect(controller.hasMoreBalances, isTrue);
      await controller.loadMoreBalances();
      expect(controller.balances.map((b) => b.id), ['one', 'two']);
      expect(repo.calls.last.after, isNotNull);
      expect(repo.calls.every((call) => call.owner == 'rep-a'), isTrue);
      await controller.selectSalesRep('rep-b');
      expect(controller.selectedSalesRepId, 'rep-a');
      expect(controller.summary.itemCount, 100);
    },
  );

  testWidgets(
    'custody multi-word search follows 450ms/minimum, Enter and clear',
    (tester) async {
      final repo = _Repository();
      final controller = await _controller(repo);
      await controller.loadBalances();
      controller.onBalanceSearchChanged('a');
      await tester.pump(const Duration(milliseconds: 500));
      expect(repo.calls, hasLength(1));
      controller.onBalanceSearchChanged('  Water   Pump ');
      await tester.pump(const Duration(milliseconds: 449));
      expect(repo.calls, hasLength(1));
      await tester.pump(const Duration(milliseconds: 1));
      expect(repo.calls.last.search, 'Water Pump');
      controller.onBalanceSearchChanged(' أَحمد    عبد ');
      controller.submitBalanceSearch();
      await tester.pump();
      expect(repo.calls.last.search, 'أَحمد عبد');
      final count = repo.calls.length;
      await tester.pump(const Duration(milliseconds: 500));
      expect(repo.calls.length, count);
      controller.clearBalanceSearch();
      await tester.pump();
      expect(repo.calls.last.search, '');
    },
  );

  test(
    'late first-page and old load-more results cannot replace a newer search',
    () async {
      final repo = _Repository();
      final controller = await _controller(repo);
      final pending =
          <String, Completer<FirestorePage<RepInventoryBalanceModel>>>{};
      repo.handler = (call) => (pending[call.search] = Completer()).future;
      controller.balanceSearchText = 'first phrase';
      final first = controller.loadBalances();
      controller.balanceSearchText = 'new phrase';
      final newer = controller.loadBalances();
      pending['new phrase']!.complete(_page('new', more: true));
      await newer;
      pending['first phrase']!.complete(_page('stale'));
      await first;
      expect(controller.balances.single.id, 'new');
      final oldPage = controller.loadMoreBalances();
      controller.onBalanceSearchChanged('latest phrase');
      controller.submitBalanceSearch();
      pending['latest phrase']!.complete(_page('latest'));
      await Future<void>.delayed(Duration.zero);
      pending['new phrase']!.complete(_page('stale-page'));
      await oldPage;
      expect(controller.balances.single.id, 'latest');
      expect(controller.balanceLoadMoreErrorKey, isNull);
    },
  );

  test(
    'empty results and failures retain an explicit retryable state',
    () async {
      final repo = _Repository();
      final controller = await _controller(repo);
      repo.handler = (_) async =>
          const FirestorePage(items: [], cursor: null, hasMore: false);
      await controller.loadBalances();
      expect(controller.balanceStatus, StatusRequest.success);
      expect(controller.balances, isEmpty);
      repo.handler = (_) async => throw const RepInventoryRepositoryException(
        RepInventoryRepositoryError.unavailable,
      );
      await controller.loadBalances();
      expect(controller.balanceStatus, StatusRequest.failure);
      expect(controller.balanceErrorKey, 'rep_inventory_error_unavailable');
      repo.handler = (_) async => _page('retry', more: true);
      await controller.loadBalances();
      repo.handler = (_) async => throw const RepInventoryRepositoryException(
        RepInventoryRepositoryError.timeout,
      );
      await controller.loadMoreBalances();
      expect(controller.balances.single.id, 'retry');
      expect(controller.balanceLoadMoreErrorKey, 'rep_inventory_error_timeout');
      expect(controller.isLoadingMoreBalances, isFalse);
    },
  );
}

Future<RepInventoryController> _controller(_Repository repo) async {
  SharedPreferences.setMockInitialValues({
    'companyId': 'default_company',
    'role': 'sales_rep',
    'uid': 'rep-a',
  });
  final controller = RepInventoryController(
    repository: repo,
    myServices: await MyServices().init(),
  );
  addTearDown(controller.onClose);
  return controller;
}

BusinessUserContext _user(String role, {bool active = true}) =>
    BusinessUserContext(
      uid: 'rep-a',
      name: 'User',
      email: '',
      phone: '',
      role: role,
      companyId: 'default_company',
      active: active,
      approvalStatus: 'approved',
    );

FirestorePage<RepInventoryBalanceModel> _page(String id, {bool more = false}) =>
    FirestorePage(
      items: [
        RepInventoryBalanceModel(
          id: id,
          companyId: 'default_company',
          salesRepId: 'rep-a',
          itemId: id,
          quantity: 4,
          modelSnapshot: 'WP-12',
          itemNameSnapshot: 'Water Pump',
          unitSnapshot: 'pcs',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ],
      cursor: more ? _Cursor() : null,
      hasMore: more,
    );

class _Cursor implements FirestorePageCursor {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Call {
  _Call(this.owner, this.search, this.after);
  final String owner;
  final String search;
  final FirestorePageCursor? after;
}

class _Repository implements RepInventoryRepository {
  final calls = <_Call>[];
  Future<FirestorePage<RepInventoryBalanceModel>> Function(_Call call)? handler;
  @override
  Future<FirestorePage<RepInventoryBalanceModel>> fetchBalancesPage({
    String companyId = 'default_company',
    String salesRepId = '',
    String searchText = '',
    FirestorePageCursor? after,
    int pageSize = 36,
  }) {
    final call = _Call(salesRepId, searchText, after);
    calls.add(call);
    return handler?.call(call) ??
        Future.value(_page(after == null ? 'one' : 'two', more: after == null));
  }

  @override
  Future<RepInventorySummary> fetchBalanceSummary({
    String companyId = 'default_company',
    String salesRepId = '',
  }) async => const RepInventorySummary(itemCount: 100, totalQuantity: 321);
  @override
  Future<List<RepInventoryMovementModel>> fetchRecentMovements({
    String companyId = 'default_company',
    String salesRepId = '',
    int limit = 40,
  }) async => [];
  @override
  Future<FirestorePage<InventoryTransferModel>> fetchTransfersPage({
    String companyId = 'default_company',
    String salesRepId = '',
    InventoryTransferType? type,
    InventoryTransferStatus? status,
    DateTime? fromDate,
    DateTime? toDate,
    String searchText = '',
    FirestorePageCursor? after,
    int pageSize = 40,
  }) async => const FirestorePage(items: [], cursor: null, hasMore: false);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
