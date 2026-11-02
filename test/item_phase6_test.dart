import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/data/firestore_query_pager.dart';
import 'package:fatoora/core/localization/translation.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/core/settings/business_settings_resolver.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/invoices/view/widgets/item_picker_sheet.dart';
import 'package:fatoora/features/items/controller/item_details_controller.dart';
import 'package:fatoora/features/items/controller/add_item_controller.dart';
import 'package:fatoora/features/items/controller/edit_item_controller.dart';
import 'package:fatoora/features/items/controller/items_controller.dart';
import 'package:fatoora/features/items/data/models/item_model.dart';
import 'package:fatoora/features/items/data/repositories/item_repository.dart';
import 'package:fatoora/features/items/view/screen/item_details_screen.dart';
import 'package:fatoora/features/items/view/screen/add_item_screen.dart';
import 'package:fatoora/features/items/view/screen/edit_item_screen.dart';
import 'package:fatoora/features/items/view/screen/items_screen.dart';
import 'package:fatoora/features/items/view/widgets/item_card.dart';
import 'package:fatoora/features/items/view/widgets/item_form.dart';
import 'package:fatoora/features/settings/data/models/app_settings_model.dart';
import 'package:fatoora/features/settings/data/models/user_preferences_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(Get.reset);

  test('Items retain 36-record cursor paging and server sort/filter', () async {
    final repository = _PagingRepository([
      [_item('one')],
      [_item('two')],
    ]);
    final controller = ItemsController(repository: repository);
    await controller.loadItems();
    expect(repository.calls.first.pageSize, 36);
    expect(repository.calls.first.after, isNull);
    expect(controller.items.single.id, 'one');
    expect(controller.hasMore, isTrue);
    await controller.loadMoreItems();
    expect(repository.calls.last.after, isNotNull);
    expect(controller.items.map((item) => item.id), ['one', 'two']);

    controller.setFilter(ItemFilter.inactive);
    await Future<void>.delayed(Duration.zero);
    expect(repository.calls.last.active, isFalse);
    controller.setSort(ItemSort.priceLow);
    await Future<void>.delayed(Duration.zero);
    expect(repository.calls.last.orderField, 'price');
    expect(repository.calls.last.descending, isFalse);
  });

  testWidgets('search keeps two-character minimum, debounce and Enter', (
    tester,
  ) async {
    final repository = _PagingRepository([
      [_item('one')],
    ]);
    final controller = ItemsController(repository: repository);
    await controller.loadItems();
    controller.onSearchChanged('x');
    expect(controller.searchIsTooShort, isTrue);
    await tester.pump(const Duration(milliseconds: 500));
    expect(repository.calls, hasLength(1));

    controller.onSearchChanged('pump');
    await tester.pump(const Duration(milliseconds: 449));
    expect(repository.calls, hasLength(1));
    await tester.pump(const Duration(milliseconds: 2));
    await tester.pump();
    expect(repository.calls.last.searchText, 'pump');

    controller.onSearchChanged('motor');
    controller.submitSearch();
    await tester.pump();
    expect(repository.calls.last.searchText, 'motor');
  });

  test('older server response cannot replace new results', () async {
    final repository = _DeferredRepository();
    final controller = ItemsController(repository: repository);
    controller.searchQuery = 'first';
    final first = controller.loadItems();
    controller.searchQuery = 'second';
    final second = controller.loadItems();
    repository.complete('second', [_item('new')]);
    await second;
    repository.complete('first', [_item('old')]);
    await first;
    expect(controller.items.single.id, 'new');
  });

  testWidgets('compact cards show description, price and truthful stock', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final tracked = _item(
      'tracked',
      stock: 3,
      description: 'Long model detail ' * 20,
    );
    final untracked = _item('untracked', tracked: false);
    await tester.pumpWidget(
      _app(
        scale: 2,
        child: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                ItemCard(item: tracked, onTap: () {}),
                ItemCard(item: untracked, onTap: () {}),
              ],
            ),
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('item-description-tracked')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('item-description-tracked')))
          .maxLines,
      2,
    );
    expect(find.byKey(const ValueKey('item-price-tracked')), findsOneWidget);
    expect(find.byKey(const ValueKey('item-stock-tracked')), findsOneWidget);
    expect(find.byKey(const ValueKey('item-stock-untracked')), findsNothing);
    expect(
      find.byKey(const ValueKey('item-tracking-disabled-untracked')),
      findsOneWidget,
    );
    expect(find.text('Stock tracking disabled'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final config in <({Size size, Locale locale, double scale})>[
    (size: const Size(320, 700), locale: const Locale('en'), scale: 2),
    (size: const Size(320, 700), locale: const Locale('ar'), scale: 2),
    (size: const Size(800, 900), locale: const Locale('ar'), scale: 1),
    (size: const Size(1366, 900), locale: const Locale('en'), scale: 1),
  ]) {
    testWidgets(
      'Items layout ${config.size.width}px ${config.locale.languageCode} ${config.scale}x',
      (tester) async {
        final controller = await _pumpItems(
          tester,
          size: config.size,
          locale: config.locale,
          scale: config.scale,
        );
        expect(
          find.byKey(const ValueKey('items-search-field')),
          findsOneWidget,
        );
        if (config.size.width >= 900) {
          expect(find.byType(DataTable), findsOneWidget);
        } else {
          expect(
            find.byKey(const ValueKey('item-card-tracked')),
            findsOneWidget,
          );
        }
        expect(controller.items, hasLength(3));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('card and desktop row open Item Details', (tester) async {
    final controller = await _pumpItems(tester, size: const Size(390, 800));
    await tester.tap(find.byKey(const ValueKey('item-card-tracked')));
    expect(controller.openedId, 'tracked');
    await tester.binding.setSurfaceSize(const Size(1366, 900));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Model tracked'));
    expect(controller.openedId, 'tracked');
  });

  testWidgets('list keeps controls for loading, error, empty and Load More', (
    tester,
  ) async {
    final controller = await _pumpItems(tester, size: const Size(390, 800));
    controller
      ..items = const []
      ..statusRequest = StatusRequest.loading
      ..update();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('items-search-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('items-results-loading')), findsOneWidget);
    controller
      ..statusRequest = StatusRequest.serverfailure
      ..update();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('items-results-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('items-retry')), findsOneWidget);
    controller
      ..statusRequest = StatusRequest.success
      ..update();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('items-empty')), findsOneWidget);
    controller
      ..items = [_item('tracked')]
      ..hasMore = true
      ..update();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('items-load-more')), findsOneWidget);
    controller
      ..loadMoreErrorMessageKey = 'items_load_error'
      ..update();
    await tester.pumpAndSettle();
    expect(
      find.text('Unable to load items. Please try again.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('sort sheet keeps all four server sort choices', (tester) async {
    final controller = await _pumpItems(tester, size: const Size(390, 800));
    await tester.tap(find.byKey(const ValueKey('items-sort-button')));
    await tester.pumpAndSettle();
    for (final sort in ItemSort.values) {
      expect(find.byKey(ValueKey('items-sort-${sort.name}')), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('items-sort-priceLow')));
    await tester.pumpAndSettle();
    expect(controller.sort, ItemSort.priceLow);
  });

  testWidgets('details keep full description and hide untracked quantities', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Get.put<MyServices>(await _services(AuthRepository.adminRole));
    final controller = _TestDetailsController();
    Get.put<ItemDetailsController>(controller);
    controller
      ..item = _item(
        'untracked',
        tracked: false,
        description: 'Full detail ' * 20,
      )
      ..statusRequest = StatusRequest.success;
    await tester.pumpWidget(_app(scale: 1.7, child: const ItemDetailsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Full detail ' * 20), findsOneWidget);
    expect(find.text('Stock tracking disabled'), findsOneWidget);
    expect(find.text('Current stock'), findsNothing);
    expect(find.text('Minimum stock'), findsNothing);
    expect(find.text('Edit item'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'shared form keeps required description and stock values when disabled',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fields = _Fields();
      addTearDown(fields.dispose);
      final formKey = GlobalKey<FormState>();
      var tracked = true;
      var saving = false;
      late StateSetter rebuild;
      await tester.pumpWidget(
        _app(
          scale: 1.7,
          child: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) {
                  rebuild = setState;
                  return fields.form(
                    formKey,
                    tracked: tracked,
                    saving: saving,
                    onTrack: (value) => setState(() => tracked = value),
                  );
                },
              ),
            ),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('item-description-field')),
        findsOneWidget,
      );
      expect(formKey.currentState!.validate(), isFalse);
      await tester.ensureVisible(
        find.byKey(const ValueKey('item-track-switch')),
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('item-track-switch')),
          matching: find.byType(Switch),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('item-opening-stock-field')),
        findsNothing,
      );
      expect(fields.opening.text, '7');
      expect(
        find.byKey(const ValueKey('item-tracking-disabled')),
        findsOneWidget,
      );
      rebuild(() => saving = true);
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('item-save-button')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('item-description-field')),
            )
            .enabled,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final locale in [const Locale('en'), const Locale('ar')]) {
    for (final width in [320.0, 1366.0]) {
      testWidgets(
        'existing inventory metadata is locked ${locale.languageCode} ${width}px',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 800));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final fields = _Fields();
          addTearDown(fields.dispose);
          await tester.pumpWidget(
            _app(
              locale: locale,
              scale: width == 320 ? 2 : 1,
              child: Scaffold(
                body: SingleChildScrollView(
                  child: fields.form(
                    GlobalKey<FormState>(),
                    tracked: true,
                    saving: false,
                    locked: true,
                    onTrack: (_) => fail('Existing tracking must stay locked'),
                  ),
                ),
              ),
            ),
          );
          final toggle = tester.widget<Switch>(
            find.descendant(
              of: find.byKey(const ValueKey('item-track-switch')),
              matching: find.byType(Switch),
            ),
          );
          expect(toggle.onChanged, isNull);
          for (final key in [
            'item-current-stock-field',
            'item-opening-stock-field',
            'item-warehouse-field',
          ]) {
            expect(
              tester
                  .widget<TextField>(
                    find.descendant(
                      of: find.byKey(ValueKey(key)),
                      matching: find.byType(TextField),
                    ),
                  )
                  .readOnly,
              isTrue,
            );
          }
          expect(
            tester
                .widget<TextField>(
                  find.descendant(
                    of: find.byKey(const ValueKey('item-price-field')),
                    matching: find.byType(TextField),
                  ),
                )
                .readOnly,
            isFalse,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('picker shows description and excludes warehouse stock for rep', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Get.put<MyServices>(await _services(AuthRepository.salesRepRole));
    final repository = _PagingRepository([
      [_item('tracked')],
    ]);
    Get.put<ItemRepository>(repository);
    await tester.pumpWidget(
      _app(scale: 1.7, child: const Scaffold(body: InvoiceItemPickerSheet())),
    );
    await tester.pumpAndSettle();
    expect(repository.calls.single.pageSize, 30);
    expect(repository.calls.single.active, isTrue);
    expect(repository.calls.single.orderField, 'nameLower');
    expect(
      find.byKey(const ValueKey('item-picker-description-tracked')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('item-picker-stock-tracked')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('picker retains warehouse stock presentation for Admin', (
    tester,
  ) async {
    Get.put<MyServices>(await _services(AuthRepository.adminRole));
    Get.put<ItemRepository>(
      _PagingRepository([
        [_item('tracked')],
      ]),
    );
    await tester.pumpWidget(
      _app(child: const Scaffold(body: InvoiceItemPickerSheet())),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('item-picker-stock-tracked')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Add screen keeps its form visible and disabled during save', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final services = await _services(AuthRepository.adminRole);
    Get.put<MyServices>(services);
    final controller = AddItemController(
      repository: _PagingRepository([const []]),
      settingsResolver: BusinessSettingsResolver.withLoaders(
        appSettingsLoader: (_) async => AppSettingsModel.defaults,
        userPreferencesLoader: (_) async => UserPreferencesModel.defaults,
      ),
      myServices: services,
    );
    Get.put<AddItemController>(controller);
    await tester.pumpWidget(
      _app(
        locale: const Locale('ar'),
        scale: 1.7,
        child: const AddItemScreen(),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('item-description-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('item-current-stock-field')),
      findsNothing,
    );
    controller
      ..statusRequest = StatusRequest.loading
      ..update();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('item-description-field')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('item-save-button')))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Edit screen keeps description and stock form during save', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Get.put<MyServices>(await _services(AuthRepository.adminRole));
    final controller = _TestEditController();
    Get.put<EditItemController>(controller);
    controller
      ..item = _item('tracked')
      ..descriptionController.text = 'Existing description'
      ..statusRequest = StatusRequest.loading;
    await tester.pumpWidget(_app(child: const EditItemScreen()));
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      find.byKey(const ValueKey('item-description-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('item-current-stock-field')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('item-save-button')))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
}

Widget _app({
  required Widget child,
  Locale locale = const Locale('en'),
  double scale = 1,
}) => GetMaterialApp(
  locale: locale,
  translations: MyTranslation(),
  builder: (context, appChild) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: appChild!,
  ),
  home: child,
);

Future<_TestItemsController> _pumpItems(
  WidgetTester tester, {
  required Size size,
  Locale locale = const Locale('en'),
  double scale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  Get.put<MyServices>(await _services(AuthRepository.adminRole));
  final controller = _TestItemsController()
    ..statusRequest = StatusRequest.success
    ..items = [
      _item('tracked'),
      _item('low', stock: 2),
      _item('untracked', tracked: false),
    ];
  Get.put<ItemsController>(controller);
  await tester.pumpWidget(
    _app(child: const ItemsScreen(), locale: locale, scale: scale),
  );
  await tester.pumpAndSettle();
  return controller;
}

Future<MyServices> _services(String role) async {
  SharedPreferences.setMockInitialValues({
    'companyId': 'company-1',
    'role': role,
  });
  return MyServices().init();
}

ItemModel _item(
  String id, {
  double stock = 18,
  bool tracked = true,
  String description = 'Catalog description',
}) {
  final now = DateTime(2026, 9, 23);
  return ItemModel(
    id: id,
    code: 'DSS-$id',
    name: 'Model $id',
    description: description,
    unit: 'PCS',
    price: 12.5,
    taxRate: 16,
    active: true,
    deleted: false,
    createdAt: now,
    updatedAt: now,
    createdBy: 'admin-1',
    currentStock: stock,
    openingStock: 7,
    minStock: 5,
    trackStock: tracked,
    costPrice: 6,
    warehouseId: ItemModel.defaultWarehouseId,
  );
}

class _Call {
  const _Call({
    required this.searchText,
    required this.active,
    required this.orderField,
    required this.descending,
    required this.after,
    required this.pageSize,
  });
  final String searchText;
  final bool? active;
  final String orderField;
  final bool descending;
  final FirestorePageCursor? after;
  final int pageSize;
}

class _PagingRepository implements ItemRepository {
  _PagingRepository(this.pages);
  final List<List<ItemModel>> pages;
  final calls = <_Call>[];
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
      _Call(
        searchText: searchText,
        active: active,
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

class _DeferredRepository implements ItemRepository {
  final pending = <String, Completer<FirestorePage<ItemModel>>>{};
  @override
  Future<FirestorePage<ItemModel>> fetchItemsPage({
    String searchText = '',
    bool? active,
    String orderField = 'createdAt',
    bool descending = true,
    FirestorePageCursor? after,
    int pageSize = 36,
  }) => (pending[searchText] ??= Completer()).future;
  void complete(String search, List<ItemModel> items) => pending[search]!
      .complete(FirestorePage(items: items, cursor: null, hasMore: false));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Cursor implements FirestorePageCursor {
  @override
  QueryDocumentSnapshot<Map<String, dynamic>> get document =>
      throw UnimplementedError();
}

class _TestItemsController extends ItemsController {
  _TestItemsController() : super(repository: _PagingRepository([const []]));
  String openedId = '';
  @override
  void onReady() {}
  @override
  Future<void> openItemDetails(ItemModel item) async {
    openedId = item.id;
  }
}

class _TestDetailsController extends ItemDetailsController {
  _TestDetailsController() : super(repository: _PagingRepository([const []]));
}

class _TestEditController extends EditItemController {
  _TestEditController() : super(repository: _PagingRepository([const []]));
  @override
  void onReady() {}
}

class _Fields {
  final name = TextEditingController();
  final code = TextEditingController();
  final description = TextEditingController();
  final unit = TextEditingController();
  final price = TextEditingController(text: '12.5');
  final tax = TextEditingController(text: '16');
  final current = TextEditingController(text: '7');
  final opening = TextEditingController(text: '7');
  final minimum = TextEditingController(text: '5');
  final cost = TextEditingController(text: '6');
  final barcode = TextEditingController();
  final category = TextEditingController();
  final warehouse = TextEditingController(text: 'default_warehouse');

  ItemForm form(
    GlobalKey<FormState> key, {
    required bool tracked,
    required bool saving,
    required ValueChanged<bool> onTrack,
    bool locked = false,
  }) => ItemForm(
    formKey: key,
    nameController: name,
    codeController: code,
    descriptionController: description,
    unitController: unit,
    priceController: price,
    taxRateController: tax,
    currentStockController: current,
    openingStockController: opening,
    minStockController: minimum,
    costPriceController: cost,
    barcodeController: barcode,
    categoryController: category,
    warehouseController: warehouse,
    active: true,
    trackStock: tracked,
    onActiveChanged: (_) {},
    onTrackStockChanged: onTrack,
    onSubmit: () {},
    submitLabel: 'Save',
    loading: saving,
    inventoryLocked: locked,
  );

  void dispose() {
    for (final controller in [
      name,
      code,
      description,
      unit,
      price,
      tax,
      current,
      opening,
      minimum,
      cost,
      barcode,
      category,
      warehouse,
    ]) {
      controller.dispose();
    }
  }
}
