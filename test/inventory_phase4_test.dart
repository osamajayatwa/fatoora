import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/data/firestore_query_pager.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/inventory/controllers/inventory_dashboard_controller.dart';
import 'package:fatoora/features/inventory/data/models/inventory_dashboard_snapshot.dart';
import 'package:fatoora/features/inventory/data/models/stock_movement_model.dart';
import 'package:fatoora/features/inventory/data/repositories/inventory_repository.dart';
import 'package:fatoora/features/inventory/view/screens/inventory_dashboard_screen.dart';
import 'package:fatoora/features/items/data/models/item_model.dart';
import 'package:fatoora/features/items/data/repositories/item_repository.dart';
import 'package:fatoora/features/rep_inventory/controllers/rep_inventory_controllers.dart';
import 'package:fatoora/features/rep_inventory/data/models/inventory_transfer_model.dart';
import 'package:fatoora/features/rep_inventory/data/models/rep_inventory_balance_model.dart';
import 'package:fatoora/features/rep_inventory/data/models/rep_inventory_enums.dart';
import 'package:fatoora/features/rep_inventory/data/models/rep_inventory_movement_model.dart';
import 'package:fatoora/features/rep_inventory/data/repositories/rep_inventory_repository.dart';
import 'package:fatoora/features/rep_inventory/view/screens/rep_inventory_screens.dart';
import 'package:fatoora/features/shared/inventory/inventory_presentation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(Get.reset);

  test(
    'Admin item query uses the existing 36-record cursor convention',
    () async {
      final repository = _PagingItemRepository([
        [_item('one', stock: 1)],
        [_item('two', stock: 2)],
      ]);
      final controller = InventoryDashboardController(
        repository: _InventoryRepository(),
        itemRepository: repository,
        myServices: await _services(role: 'admin'),
      );

      await controller.loadDashboard();
      expect(controller.items.map((item) => item.id), ['one']);
      expect(controller.hasMoreItems, isTrue);
      expect(repository.calls.first.pageSize, 36);
      expect(repository.calls.first.after, isNull);

      await controller.loadMoreItems();
      expect(controller.items.map((item) => item.id), ['one', 'two']);
      expect(repository.calls.last.after, isNotNull);
      expect(controller.hasMoreItems, isFalse);
    },
  );

  test(
    'Admin search and sort stay server-backed and discard stale results',
    () async {
      final repository = _DeferredItemRepository();
      final controller = InventoryDashboardController(
        repository: _InventoryRepository(),
        itemRepository: repository,
        myServices: await _services(role: 'admin'),
      );

      controller.itemSearchQuery = 'first';
      final first = controller.loadItems();
      controller.itemSearchQuery = 'second';
      final second = controller.loadItems();
      repository.complete('second', [_item('new', stock: 8)]);
      await second;
      repository.complete('first', [_item('stale', stock: 1)]);
      await first;
      expect(controller.items.single.id, 'new');

      controller.itemSearchQuery = 'sort-query';
      controller.setItemSort(InventoryItemSort.priceLow);
      repository.complete('sort-query', [_item('sorted', stock: 3)]);
      await Future<void>.delayed(Duration.zero);
      expect(repository.calls.last.orderField, 'price');
      expect(repository.calls.last.descending, isFalse);
    },
  );

  test(
    'Sales Representative inventory requests only the signed-in rep scope',
    () async {
      final services = await _services(role: 'sales_rep', uid: 'rep-7');
      final repository = _RepRepository();
      final controller = RepInventoryController(
        repository: repository,
        myServices: services,
      );
      Get.put(controller);

      await controller.load();
      expect(controller.selectedSalesRepId, 'rep-7');
      expect(repository.requestedRepIds, everyElement('rep-7'));
      expect(controller.balances.single.quantity, 4);
    },
  );

  testWidgets(
    'warehouse cards show real quantity, unit, minimum, and statuses',
    (tester) async {
      final items = [
        _item('zero', stock: 0, minimum: 5),
        _item('low', stock: 3, minimum: 5),
        _item('healthy', stock: 18, minimum: 5),
        _item('untracked', stock: 0, minimum: 0, tracked: false),
      ];
      await _pumpCards(tester, items: items);

      expect(
        find.byKey(const ValueKey('warehouse-quantity-zero')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('minimum-stock-low')), findsOneWidget);
      expect(find.text('out_of_stock'), findsOneWidget);
      expect(find.text('low_stock'), findsOneWidget);
      expect(find.text('in_stock'), findsOneWidget);
      expect(find.text('track_stock_disabled'), findsOneWidget);
      expect(find.textContaining('PCS'), findsWidgets);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('warehouse-quantity-healthy')),
          matching: find.textContaining('18'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('warehouse-quantity-untracked')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('warehouse-item-untracked')),
          matching: find.text('out_of_stock'),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('custody card displays rep balance and never warehouse stock', (
    tester,
  ) async {
    final balance = _balance(quantity: 4.5);
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: CustodyInventoryItemCard(balance: balance),
          ),
        ),
      ),
    );

    expect(find.text('rep_inventory_custody_quantity'), findsOneWidget);
    expect(find.textContaining('4.5'), findsOneWidget);
    expect(find.text('current_stock'), findsNothing);
    expect(find.text('min_stock'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Sales Rep custody screen stays role-scoped and overflow-safe', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final services = await _services(role: 'sales_rep', uid: 'rep-7');
    Get.put<MyServices>(services);
    final controller = _TestRepController(services)
      ..statusRequest = StatusRequest.success
      ..balances = [_balance(quantity: 4.5)];
    Get.put<RepInventoryController>(controller);
    await tester.pumpWidget(
      GetMaterialApp(
        locale: const Locale('ar'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.7)),
          child: child!,
        ),
        home: const RepInventoryScreen(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -650));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('custody-item-item-1')), findsOneWidget);
    expect(find.text('rep_inventory_custody_quantity'), findsOneWidget);
    expect(find.text('rep_inventory_new_transfer'), findsNothing);
    expect(find.text('current_stock'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stock movement card keeps audit-important details visible', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      GetMaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.7)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: StockMovementCard(movement: _movement()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('DSS40-25-6'), findsOneWidget);
    expect(find.text('INV-42'), findsOneWidget);
    expect(find.textContaining('quantity_before'), findsOneWidget);
    expect(find.textContaining('quantity_after'), findsOneWidget);
    expect(find.textContaining('Warehouse Admin'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final configuration in <({Size size, Locale locale, double scale})>[
    (size: const Size(320, 700), locale: const Locale('en'), scale: 2),
    (size: const Size(800, 900), locale: const Locale('ar'), scale: 1),
    (size: const Size(1366, 900), locale: const Locale('en'), scale: 1),
  ]) {
    testWidgets(
      'Admin inventory is overflow-safe at ${configuration.size.width}px '
      '${configuration.locale.languageCode} ${configuration.scale}x',
      (tester) async {
        final controller = await _pumpDashboard(
          tester,
          configuration.size,
          locale: configuration.locale,
          textScale: configuration.scale,
        );
        expect(
          find.byKey(const ValueKey('inventory-item-search')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('inventory-item-sort')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('warehouse-item-healthy')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        expect(controller.items, hasLength(4));
      },
    );
  }

  testWidgets(
    'Admin item list keeps loading, error, empty, and Load More states',
    (tester) async {
      final controller = await _pumpDashboard(tester, const Size(390, 800));

      controller
        ..itemStatusRequest = StatusRequest.loading
        ..update();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.byKey(const ValueKey('inventory-item-search')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('inventory-items-loading')),
        findsOneWidget,
      );

      controller
        ..itemStatusRequest = StatusRequest.serverfailure
        ..itemLoadErrorMessageKey = 'items_load_error'
        ..update();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('inventory-items-error')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('inventory-items-retry')),
        findsOneWidget,
      );

      controller
        ..itemStatusRequest = StatusRequest.success
        ..items = const []
        ..update();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('inventory-items-empty')),
        findsOneWidget,
      );

      controller
        ..items = [_item('healthy', stock: 18, minimum: 5)]
        ..hasMoreItems = true
        ..update();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('inventory-items-load-more')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Admin inventory item uses the existing item navigation callback',
    (tester) async {
      final controller = await _pumpDashboard(tester, const Size(390, 800));
      final card = find.byKey(const ValueKey('warehouse-item-healthy'));
      await tester.ensureVisible(card);
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(controller.openedItemId, 'healthy');
    },
  );
}

Future<_TestDashboardController> _pumpDashboard(
  WidgetTester tester,
  Size size, {
  Locale locale = const Locale('en'),
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final services = await _services(role: 'admin');
  Get.put<MyServices>(services);
  final controller = _TestDashboardController(services)
    ..statusRequest = StatusRequest.success
    ..itemStatusRequest = StatusRequest.success
    ..snapshot = const InventoryDashboardSnapshot.empty()
    ..items = [
      _item('zero', stock: 0, minimum: 5),
      _item('low', stock: 3, minimum: 5),
      _item('healthy', stock: 18, minimum: 5),
      _item('untracked', stock: 0, tracked: false),
    ];
  Get.put<InventoryDashboardController>(controller);
  await tester.pumpWidget(
    GetMaterialApp(
      locale: locale,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const InventoryDashboardScreen(),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _pumpCards(
  WidgetTester tester, {
  required List<ItemModel> items,
}) async {
  await tester.binding.setSurfaceSize(const Size(320, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    GetMaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(1.7)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: items
                .map(
                  (item) =>
                      WarehouseInventoryItemCard(item: item, onTap: () {}),
                )
                .toList(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<MyServices> _services({
  required String role,
  String uid = 'user-1',
}) async {
  SharedPreferences.setMockInitialValues({
    'companyId': 'company-1',
    'role': role,
    'uid': uid,
    'name': 'Test User',
  });
  return MyServices().init();
}

ItemModel _item(
  String id, {
  required double stock,
  double minimum = 5,
  bool tracked = true,
}) {
  final now = DateTime(2026, 9, 23);
  return ItemModel(
    id: id,
    code: 'DSS40-$id',
    name: 'Pump model $id',
    description: '',
    unit: 'PCS',
    price: 10,
    taxRate: 0,
    active: true,
    deleted: false,
    createdAt: now,
    updatedAt: now,
    createdBy: 'admin-1',
    currentStock: stock,
    openingStock: stock,
    minStock: minimum,
    trackStock: tracked,
    costPrice: 5,
    warehouseId: ItemModel.defaultWarehouseId,
  );
}

RepInventoryBalanceModel _balance({required double quantity}) {
  final now = DateTime(2026, 9, 23, 12);
  return RepInventoryBalanceModel(
    id: 'rep-7_item-1',
    companyId: 'company-1',
    salesRepId: 'rep-7',
    itemId: 'item-1',
    quantity: quantity,
    modelSnapshot: 'DSS40-25-6',
    itemNameSnapshot: 'Pump',
    unitSnapshot: 'PCS',
    createdAt: now,
    updatedAt: now,
  );
}

StockMovementModel _movement() {
  final now = DateTime(2026, 9, 23, 12);
  return StockMovementModel(
    id: 'movement-1',
    companyId: 'company-1',
    warehouseId: ItemModel.defaultWarehouseId,
    itemId: 'item-1',
    itemName: 'Pump',
    itemCode: 'DSS40-25-6',
    movementType: 'invoice_sale',
    direction: 'out',
    quantity: 2,
    quantityBefore: 20,
    quantityAfter: 18,
    referenceType: 'invoice',
    referenceId: 'invoice-42',
    referenceNumber: 'INV-42',
    movementDate: now,
    notes: '',
    createdByUid: 'admin-1',
    createdByName: 'Warehouse Admin',
    createdByRole: 'admin',
    createdAt: now,
  );
}

class _InventoryRepository implements InventoryRepository {
  @override
  Future<InventoryDashboardSnapshot> fetchDashboard({
    String companyId = 'default_company',
  }) async => const InventoryDashboardSnapshot.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ItemCall {
  const _ItemCall({
    required this.searchText,
    required this.orderField,
    required this.descending,
    required this.after,
    required this.pageSize,
  });

  final String searchText;
  final String orderField;
  final bool descending;
  final FirestorePageCursor? after;
  final int pageSize;
}

class _PagingItemRepository implements ItemRepository {
  _PagingItemRepository(this.pages);

  final List<List<ItemModel>> pages;
  final List<_ItemCall> calls = [];

  @override
  Future<FirestorePage<ItemModel>> fetchItemsPage({
    String searchText = '',
    bool? active,
    String orderField = 'createdAt',
    bool descending = true,
    FirestorePageCursor? after,
    int pageSize = 36,
  }) async {
    calls.add(
      _ItemCall(
        searchText: searchText,
        orderField: orderField,
        descending: descending,
        after: after,
        pageSize: pageSize,
      ),
    );
    final index = after == null ? 0 : 1;
    final hasMore = index + 1 < pages.length;
    return FirestorePage(
      items: pages[index],
      cursor: hasMore ? _Cursor() : null,
      hasMore: hasMore,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DeferredItemRepository implements ItemRepository {
  final calls = <_ItemCall>[];
  final _completers = <String, Completer<FirestorePage<ItemModel>>>{};

  @override
  Future<FirestorePage<ItemModel>> fetchItemsPage({
    String searchText = '',
    bool? active,
    String orderField = 'createdAt',
    bool descending = true,
    FirestorePageCursor? after,
    int pageSize = 36,
  }) {
    calls.add(
      _ItemCall(
        searchText: searchText,
        orderField: orderField,
        descending: descending,
        after: after,
        pageSize: pageSize,
      ),
    );
    return (_completers[searchText] ??= Completer()).future;
  }

  void complete(String search, List<ItemModel> items) {
    _completers[search]!.complete(
      FirestorePage(items: items, cursor: null, hasMore: false),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Cursor implements FirestorePageCursor {
  @override
  QueryDocumentSnapshot<Map<String, dynamic>> get document =>
      throw UnimplementedError();
}

class _TestDashboardController extends InventoryDashboardController {
  _TestDashboardController(MyServices services)
    : super(
        repository: _InventoryRepository(),
        itemRepository: _PagingItemRepository([const []]),
        myServices: services,
      );

  String openedItemId = '';

  @override
  void onReady() {}

  @override
  Future<void> openItem(ItemModel item) async {
    openedItemId = item.id;
  }
}

class _RepRepository implements RepInventoryRepository {
  final requestedRepIds = <String>[];

  @override
  Future<List<RepInventoryBalanceModel>> fetchBalances({
    String companyId = 'default_company',
    String salesRepId = '',
    int pageSize = 700,
  }) async {
    requestedRepIds.add(salesRepId);
    return [_balance(quantity: 4)];
  }

  @override
  Future<List<RepInventoryMovementModel>> fetchRecentMovements({
    String companyId = 'default_company',
    String salesRepId = '',
    int limit = 40,
  }) async {
    requestedRepIds.add(salesRepId);
    return const [];
  }

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
  }) async {
    requestedRepIds.add(salesRepId);
    return const FirestorePage(items: [], cursor: null, hasMore: false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestRepController extends RepInventoryController {
  _TestRepController(MyServices services)
    : super(repository: _RepRepository(), myServices: services);

  @override
  void onReady() {}
}
