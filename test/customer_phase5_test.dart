import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/data/firestore_query_pager.dart';
import 'package:fatoora/core/localization/translation.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/core/settings/business_permission_resolver.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/customers/controllers/customer_details_controller.dart';
import 'package:fatoora/features/customers/controllers/customer_form_controller.dart';
import 'package:fatoora/features/customers/controllers/customers_controller.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';
import 'package:fatoora/features/customers/data/models/customer_transaction_model.dart';
import 'package:fatoora/features/customers/data/repositories/customer_repository.dart';
import 'package:fatoora/features/customers/view/screens/customer_details_screen.dart';
import 'package:fatoora/features/customers/view/screens/customer_form_screen.dart';
import 'package:fatoora/features/customers/view/screens/customers_list_screen.dart';
import 'package:fatoora/features/customers/view/widgets/customer_list_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(Get.reset);

  test(
    'customer paging keeps the existing 50-record cursor contract',
    () async {
      final repository = _PagingCustomerRepository([
        [_customer('one')],
        [_customer('two')],
      ]);
      final controller = CustomersController(
        repository: repository,
        myServices: await _services(role: AuthRepository.adminRole),
        permissionResolver: _PermissionResolver(_adminPermissions),
      );

      await controller.loadCustomers();
      expect(controller.customers.map((customer) => customer.id), ['one']);
      expect(controller.hasMore, isTrue);
      expect(repository.calls.first.pageSize, 50);
      expect(repository.calls.first.after, isNull);

      await controller.loadMoreCustomers();
      expect(controller.customers.map((customer) => customer.id), [
        'one',
        'two',
      ]);
      expect(repository.calls.last.after, isNotNull);
      expect(controller.hasMore, isFalse);
    },
  );

  test('customer search is server-backed and ignores stale results', () async {
    final repository = _DeferredCustomerRepository();
    final controller = CustomersController(
      repository: repository,
      myServices: await _services(role: AuthRepository.adminRole),
      permissionResolver: _PermissionResolver(_adminPermissions),
    );

    controller.searchText = 'first';
    final first = controller.loadCustomers();
    controller.searchText = 'second';
    final second = controller.loadCustomers();
    repository.complete('second', [_customer('new')]);
    await second;
    repository.complete('first', [_customer('stale')]);
    await first;

    expect(repository.calls.map((call) => call.searchText), [
      'first',
      'second',
    ]);
    expect(controller.customers.single.id, 'new');

    controller.onSearchChanged('x');
    expect(controller.searchIsTooShort, isTrue);
    repository.complete('', const []);
    await Future<void>.delayed(Duration.zero);
    expect(repository.calls.last.searchText, '');
  });

  testWidgets('balance badges explain due, credit, and zero without signs', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        child: const Scaffold(
          body: Column(
            children: [
              CustomerBalanceBadge(balance: 150),
              CustomerBalanceBadge(balance: -20),
              CustomerBalanceBadge(balance: 0),
            ],
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('customer-balance-due')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('customer-balance-credit')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('customer-balance-zero')), findsOneWidget);
    expect(find.text('JOD 150.000 due'), findsOneWidget);
    expect(find.text('JOD 20.000 customer credit'), findsOneWidget);
    expect(find.textContaining('-20'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Admin customer cards show creator and open details', (
    tester,
  ) async {
    final controller = await _pumpCustomers(
      tester,
      size: const Size(390, 800),
      role: AuthRepository.adminRole,
      permissions: _adminPermissions,
    );

    expect(find.byKey(const ValueKey('customer-card-due')), findsOneWidget);
    expect(find.textContaining('Admin One'), findsNWidgets(3));
    expect(find.text('Add customer'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('customer-card-due')));
    await tester.pump();
    expect(controller.openedCustomerId, 'due');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Sales Rep uses the same cards without repeating creator name', (
    tester,
  ) async {
    await _pumpCustomers(
      tester,
      size: const Size(390, 800),
      role: AuthRepository.salesRepRole,
      permissions: _repPermissions,
    );

    expect(find.byKey(const ValueKey('customer-card-due')), findsOneWidget);
    expect(find.textContaining('Admin One'), findsNothing);
    expect(find.text('Add customer'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final configuration in <({Size size, Locale locale, double scale})>[
    (size: const Size(320, 700), locale: const Locale('en'), scale: 2),
    (size: const Size(800, 900), locale: const Locale('ar'), scale: 1),
    (size: const Size(1366, 900), locale: const Locale('en'), scale: 1),
  ]) {
    testWidgets(
      'customer list is overflow-safe at ${configuration.size.width}px '
      '${configuration.locale.languageCode} ${configuration.scale}x',
      (tester) async {
        await _pumpCustomers(
          tester,
          size: configuration.size,
          locale: configuration.locale,
          textScale: configuration.scale,
          role: AuthRepository.adminRole,
          permissions: _adminPermissions,
        );

        expect(
          find.byKey(const ValueKey('customer-search-field')),
          findsOneWidget,
        );
        expect(find.text('Customer due'), findsOneWidget);
        if (configuration.size.width >= 900) {
          expect(find.byType(DataTable), findsOneWidget);
        } else {
          expect(
            find.byKey(const ValueKey('customer-card-due')),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('desktop table row opens existing customer details callback', (
    tester,
  ) async {
    final controller = await _pumpCustomers(
      tester,
      size: const Size(1366, 900),
      role: AuthRepository.adminRole,
      permissions: _adminPermissions,
    );

    await tester.tap(find.text('Customer due'));
    await tester.pump();
    expect(controller.openedCustomerId, 'due');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'customer controls survive loading, error, empty, and Load More',
    (tester) async {
      final controller = await _pumpCustomers(
        tester,
        size: const Size(390, 800),
        role: AuthRepository.adminRole,
        permissions: _adminPermissions,
      );

      controller
        ..customers = const []
        ..statusRequest = StatusRequest.loading
        ..update();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.byKey(const ValueKey('customer-search-field')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('customer-results-loading')),
        findsOneWidget,
      );

      controller
        ..statusRequest = StatusRequest.serverfailure
        ..loadErrorMessageKey = 'customers_load_error'
        ..update();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('customer-results-error')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('customer-retry-button')),
        findsOneWidget,
      );

      controller
        ..statusRequest = StatusRequest.success
        ..update();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('customer-list-empty')), findsOneWidget);

      controller
        ..customers = [_customer('more')]
        ..hasMore = true
        ..update();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('customer-load-more')), findsOneWidget);

      controller.onSearchChanged('x');
      await tester.pump();
      expect(
        find.byKey(const ValueKey('customer-search-minimum-hint')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Add/Edit form is keyboard-safe, disables while saving, and scales',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final services = await _services(role: AuthRepository.adminRole);
      Get.put<MyServices>(services);
      final controller = _TestCustomerFormController(services)
        ..customerId = 'due'
        ..nameController.text = 'Customer due'
        ..isSaving = true;
      Get.put<CustomerFormController>(controller);

      await tester.pumpWidget(
        _app(
          locale: const Locale('ar'),
          textScale: 1.7,
          child: const CustomerFormScreen(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(const ValueKey('customer-name-field')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('customer-phone-field')),
        findsOneWidget,
      );
      expect(find.byType(SwitchListTile), findsOneWidget);
      final save = tester.widget<FilledButton>(
        find.byKey(const ValueKey('customer-save-button')),
      );
      final name = tester.widget<TextFormField>(
        find.byKey(const ValueKey('customer-name-field')),
      );
      expect(save.onPressed, isNull);
      expect(name.enabled, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('existing opening balance is presented as an edit flow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final services = await _services(role: AuthRepository.salesRepRole);
    Get.put<MyServices>(services);
    final controller = _TestCustomerDetailsController(services)
      ..statusRequest = StatusRequest.success
      ..customer = _customer('due', balance: 90)
      ..openingBalance = _openingBalance();
    Get.put<CustomerDetailsController>(controller);

    await tester.pumpWidget(
      _app(
        locale: const Locale('en'),
        textScale: 1.7,
        child: const CustomerDetailsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Edit opening balance'), findsOneWidget);
    expect(find.text('Opening balance'), findsOneWidget);
    expect(find.textContaining('Admin One'), findsNothing);
    expect(find.byKey(const ValueKey('customer-balance-due')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

const _adminPermissions = EffectiveBusinessPermissions(
  isAdmin: true,
  isSalesRep: false,
  createCustomers: true,
  createReceipts: true,
  createReturns: true,
  createQuotations: true,
  editCatalogPrice: true,
  applyDiscount: true,
);

const _repPermissions = EffectiveBusinessPermissions(
  isAdmin: false,
  isSalesRep: true,
  createCustomers: false,
  createReceipts: true,
  createReturns: true,
  createQuotations: true,
  editCatalogPrice: false,
  applyDiscount: false,
);

Widget _app({
  required Widget child,
  Locale locale = const Locale('en'),
  double textScale = 1,
}) {
  return GetMaterialApp(
    locale: locale,
    translations: MyTranslation(),
    builder: (context, appChild) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: appChild!,
    ),
    home: child,
  );
}

Future<_TestCustomersController> _pumpCustomers(
  WidgetTester tester, {
  required Size size,
  required String role,
  required EffectiveBusinessPermissions permissions,
  Locale locale = const Locale('en'),
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final services = await _services(role: role);
  Get.put<MyServices>(services);
  final controller =
      _TestCustomersController(services, permissions: permissions)
        ..statusRequest = StatusRequest.success
        ..permissions = permissions
        ..customers = [
          _customer('due', balance: 150),
          _customer('credit', balance: -20),
          _customer('zero'),
        ];
  Get.put<CustomersController>(controller);
  await tester.pumpWidget(
    _app(
      locale: locale,
      textScale: textScale,
      child: const CustomersListScreen(),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

Future<MyServices> _services({required String role}) async {
  SharedPreferences.setMockInitialValues({
    'companyId': 'company-1',
    'role': role,
    'uid': role == AuthRepository.adminRole ? 'admin-1' : 'rep-1',
    'name': 'Test User',
  });
  return MyServices().init();
}

CustomerModel _customer(String id, {double balance = 0}) {
  final now = DateTime(2026, 9, 23);
  return CustomerModel(
    id: id,
    companyId: 'company-1',
    name: 'Customer $id',
    phone: '0790000000',
    addressText: 'Street 1',
    city: 'Amman',
    area: 'Shmeisani',
    notes: 'Notes',
    active: true,
    createdByUid: 'admin-1',
    createdByName: 'Admin One',
    createdByRole: AuthRepository.adminRole,
    createdAt: now,
    updatedAt: now,
    currentBalance: balance,
    totalSales: 250,
    totalPaid: 100,
    searchKeywords: const [],
    nameLower: 'customer $id',
    phoneNormalized: '0790000000',
    cityLower: 'amman',
    areaLower: 'shmeisani',
  );
}

CustomerTransactionModel _openingBalance() {
  final now = DateTime(2026, 9, 23);
  return CustomerTransactionModel(
    id: 'due_opening_balance',
    companyId: 'company-1',
    customerId: 'due',
    customerName: 'Customer due',
    transactionType: 'opening_balance',
    sourceCollection: 'customers',
    sourceId: 'due',
    sourceNumber: '',
    transactionDate: now,
    debitAmount: 90,
    creditAmount: 0,
    balanceAfter: 90,
    openingBalanceType: 'customer_owes_us',
    amount: 90,
    signedAmount: 90,
    notes: 'Opening',
    createdByUid: 'admin-1',
    createdByName: 'Admin One',
    createdByRole: AuthRepository.adminRole,
    salesRepId: '',
    salesRepName: '',
    createdAt: now,
  );
}

class _CustomerCall {
  const _CustomerCall({
    required this.searchText,
    required this.after,
    required this.pageSize,
  });

  final String searchText;
  final FirestorePageCursor? after;
  final int pageSize;
}

class _PagingCustomerRepository implements CustomerRepository {
  _PagingCustomerRepository(this.pages);

  final List<List<CustomerModel>> pages;
  final List<_CustomerCall> calls = [];

  @override
  Future<FirestorePage<CustomerModel>> fetchCustomersPage({
    String companyId = AuthRepository.defaultCompanyId,
    String searchText = '',
    bool activeOnly = true,
    FirestorePageCursor? after,
    int pageSize = 50,
  }) async {
    calls.add(
      _CustomerCall(searchText: searchText, after: after, pageSize: pageSize),
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

class _DeferredCustomerRepository implements CustomerRepository {
  final calls = <_CustomerCall>[];
  final _completers = <String, Completer<FirestorePage<CustomerModel>>>{};

  @override
  Future<FirestorePage<CustomerModel>> fetchCustomersPage({
    String companyId = AuthRepository.defaultCompanyId,
    String searchText = '',
    bool activeOnly = true,
    FirestorePageCursor? after,
    int pageSize = 50,
  }) {
    calls.add(
      _CustomerCall(searchText: searchText, after: after, pageSize: pageSize),
    );
    return (_completers[searchText] ??= Completer()).future;
  }

  void complete(String search, List<CustomerModel> customers) {
    _completers[search]!.complete(
      FirestorePage(items: customers, cursor: null, hasMore: false),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PermissionResolver implements BusinessPermissionResolver {
  const _PermissionResolver(this.permissions);

  final EffectiveBusinessPermissions permissions;

  @override
  Future<EffectiveBusinessPermissions> resolve(String companyId) async =>
      permissions;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Cursor implements FirestorePageCursor {
  @override
  QueryDocumentSnapshot<Map<String, dynamic>> get document =>
      throw UnimplementedError();
}

class _TestCustomersController extends CustomersController {
  _TestCustomersController(
    MyServices services, {
    required EffectiveBusinessPermissions permissions,
  }) : super(
         repository: _PagingCustomerRepository([const []]),
         myServices: services,
         permissionResolver: _PermissionResolver(permissions),
       );

  String openedCustomerId = '';

  @override
  void onReady() {}

  @override
  Future<void> openCustomerDetails(CustomerModel customer) async {
    openedCustomerId = customer.id;
  }
}

class _TestCustomerFormController extends CustomerFormController {
  _TestCustomerFormController(MyServices services)
    : super(
        repository: _PagingCustomerRepository([const []]),
        myServices: services,
      );

  @override
  void onReady() {}
}

class _TestCustomerDetailsController extends CustomerDetailsController {
  _TestCustomerDetailsController(MyServices services)
    : super(
        repository: _PagingCustomerRepository([const []]),
        myServices: services,
      );

  @override
  void onReady() {}
}
