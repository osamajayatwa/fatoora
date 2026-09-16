import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/core/settings/business_permission_resolver.dart';
import 'package:fatoora/core/settings/business_settings_resolver.dart';
import 'package:fatoora/features/customers/controllers/customer_form_controller.dart';
import 'package:fatoora/features/customers/data/models/customer_model.dart';
import 'package:fatoora/features/customers/data/repositories/customer_repository.dart';
import 'package:fatoora/features/invoices/controllers/invoice_form_controller.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:fatoora/features/invoices/data/models/invoice_item_snapshot.dart';
import 'package:fatoora/features/invoices/data/repositories/invoice_repository.dart';
import 'package:fatoora/features/invoices/data/services/invoice_number_service.dart';
import 'package:fatoora/features/invoices/data/services/invoice_totals_service.dart';
import 'package:fatoora/features/settings/data/repositories/settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late MyServices services;
  late CustomerModel createdCustomer;

  setUp(() async {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({'companyId': 'company-1'});
    services = await MyServices().init();
    createdCustomer = _customer(id: 'customer-new', name: 'New Customer');
  });

  tearDown(Get.reset);

  testWidgets('customer list creation continues to customer details', (
    tester,
  ) async {
    final controller = CustomerFormController(
      repository: _CustomerRepositoryFake(createdCustomer),
      myServices: services,
    );

    await tester.pumpWidget(
      GetMaterialApp(
        home: _CustomerFormHarness(controller: controller),
        getPages: [
          GetPage(
            name: '/customers/:customerId',
            page: () => const Scaffold(body: Text('customer-details')),
          ),
        ],
      ),
    );

    await tester.enterText(find.byType(TextFormField), 'New Customer');
    await tester.tap(find.text('save-customer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(Get.currentRoute, AppRoute.customerDetailsPath(createdCustomer.id));
    expect(find.text('customer-details'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('invoice-origin creation returns the created customer', (
    tester,
  ) async {
    await tester.pumpWidget(
      GetMaterialApp(
        home: _ReturnLauncher(
          services: services,
          repository: _CustomerRepositoryFake(createdCustomer),
        ),
        getPages: [
          GetPage(
            name: AppRoute.createCustomer,
            page: () {
              final controller = CustomerFormController(
                repository: _CustomerRepositoryFake(createdCustomer),
                myServices: services,
              )..returningCustomer = true;
              return _CustomerFormHarness(
                controller: controller,
                initialize: false,
              );
            },
          ),
        ],
      ),
    );

    await tester.tap(find.text('open-customer-form'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'New Customer');
    await tester.tap(find.text('save-customer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(Get.currentRoute, '/');
    expect(find.text('returned:customer-new'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  test(
    'selecting the returned customer preserves the complete invoice draft',
    () async {
      final settingsResolver = BusinessSettingsResolver(
        repository: _SettingsRepositoryFake(),
      );
      final controller = InvoiceFormController(
        repository: _InvoiceRepositoryFake(),
        numberService: const InvoiceNumberService(),
        totalsService: const InvoiceTotalsService(),
        myServices: services,
        settingsResolver: settingsResolver,
        permissionResolver: _BusinessPermissionResolverFake(),
      );
      final invoiceDate = DateTime(2026, 9, 10);
      final dueDate = DateTime(2026, 10, 10);
      final item = const InvoiceItemSnapshot(
        itemId: 'item-1',
        itemName: 'Snapshot Item',
        itemCode: 'MODEL-7',
        unit: 'box',
        quantity: 3.5,
        unitPrice: 12.345,
        discount: 1.25,
        taxPercent: 16,
        subtotal: 43.208,
        taxAmount: 6.713,
        total: 48.671,
      );

      controller
        ..companyId = 'company-1'
        ..invoiceId = 'draft-id'
        ..invoiceType = InvoiceType.regular
        ..invoiceStatus = InvoiceStatus.draft
        ..paymentType = PaymentType.partial
        ..paymentStatus = PaymentStatus.partiallyPaid
        ..hasReceivedPayment = true
        ..invoiceDate = invoiceDate
        ..dueDate = dueDate
        ..items = [item]
        ..subtotal = 43.208
        ..totalDiscount = 1.25
        ..totalTax = 6.713
        ..grandTotal = 48.671
        ..paidAmount = 20
        ..remainingAmount = 28.671
        ..invoiceNumberController.text = 'INV-DRAFT-42'
        ..notesController.text = 'Keep these invoice notes'
        ..paymentMethodController.text = PaymentType.partial.value
        ..paidAmountController.text = '20.000'
        ..itemNameController.text = 'Uncommitted item name'
        ..itemCodeController.text = 'UNCOMMITTED-CODE'
        ..itemUnitController.text = 'carton'
        ..itemQuantityController.text = '9'
        ..itemPriceController.text = '7.125'
        ..itemDiscountController.text = '2.500'
        ..itemTaxController.text = '8';

      final originalItems = controller.items;
      controller.selectCustomer(createdCustomer);

      expect(controller.customerSnapshot?.id, 'customer-new');
      expect(controller.customerSnapshot?.name, 'New Customer');
      expect(controller.items, same(originalItems));
      expect(controller.items, [same(item)]);
      expect(controller.items.single.quantity, 3.5);
      expect(controller.items.single.unitPrice, 12.345);
      expect(controller.subtotal, 43.208);
      expect(controller.totalDiscount, 1.25);
      expect(controller.totalTax, 6.713);
      expect(controller.grandTotal, 48.671);
      expect(controller.hasReceivedPayment, isTrue);
      expect(controller.paymentType, PaymentType.partial);
      expect(controller.paymentStatus, PaymentStatus.partiallyPaid);
      expect(controller.paidAmount, 20);
      expect(controller.remainingAmount, 28.671);
      expect(controller.paidAmountController.text, '20.000');
      expect(controller.paymentMethodController.text, 'partial');
      expect(controller.notesController.text, 'Keep these invoice notes');
      expect(controller.invoiceNumberController.text, 'INV-DRAFT-42');
      expect(controller.invoiceDate, invoiceDate);
      expect(controller.dueDate, dueDate);
      expect(controller.itemNameController.text, 'Uncommitted item name');
      expect(controller.itemCodeController.text, 'UNCOMMITTED-CODE');
      expect(controller.itemUnitController.text, 'carton');
      expect(controller.itemQuantityController.text, '9');
      expect(controller.itemPriceController.text, '7.125');
      expect(controller.itemDiscountController.text, '2.500');
      expect(controller.itemTaxController.text, '8');

      controller.onClose();
    },
  );
}

class _CustomerFormHarness extends StatefulWidget {
  const _CustomerFormHarness({
    required this.controller,
    this.initialize = true,
  });

  final CustomerFormController controller;
  final bool initialize;

  @override
  State<_CustomerFormHarness> createState() => _CustomerFormHarnessState();
}

class _CustomerFormHarnessState extends State<_CustomerFormHarness> {
  @override
  void initState() {
    super.initState();
    if (widget.initialize) widget.controller.initialize();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Scaffold(
      body: Form(
        key: controller.formKey,
        child: Column(
          children: [
            TextFormField(
              controller: controller.nameController,
              validator: controller.validateName,
            ),
            TextButton(
              onPressed: controller.saveCustomer,
              child: const Text('save-customer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReturnLauncher extends StatefulWidget {
  const _ReturnLauncher({required this.services, required this.repository});

  final MyServices services;
  final CustomerRepository repository;

  @override
  State<_ReturnLauncher> createState() => _ReturnLauncherState();
}

class _ReturnLauncherState extends State<_ReturnLauncher> {
  CustomerModel? result;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TextButton(
            onPressed: () async {
              final value = await Get.toNamed(
                AppRoute.createCustomer,
                arguments: {'returnCustomer': true},
              );
              if (mounted && value is CustomerModel) {
                setState(() => result = value);
              }
            },
            child: const Text('open-customer-form'),
          ),
          Text('returned:${result?.id ?? ''}'),
        ],
      ),
    );
  }
}

class _CustomerRepositoryFake implements CustomerRepository {
  _CustomerRepositoryFake(this.customer);

  final CustomerModel customer;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #addCustomer) {
      return Future<CustomerModel>.value(customer);
    }
    return super.noSuchMethod(invocation);
  }
}

class _InvoiceRepositoryFake implements InvoiceRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SettingsRepositoryFake implements SettingsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BusinessPermissionResolverFake implements BusinessPermissionResolver {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CustomerModel _customer({required String id, required String name}) {
  final now = DateTime(2026, 9, 15);
  return CustomerModel(
    id: id,
    companyId: 'company-1',
    name: name,
    phone: '0790000000',
    addressText: 'Amman',
    city: 'Amman',
    area: 'Shmeisani',
    notes: '',
    active: true,
    createdByUid: 'admin-1',
    createdByName: 'Admin',
    createdByRole: 'admin',
    createdAt: now,
    updatedAt: now,
    currentBalance: 0,
    totalSales: 0,
    totalPaid: 0,
    searchKeywords: const [],
    nameLower: name.toLowerCase(),
    phoneNormalized: '0790000000',
    cityLower: 'amman',
    areaLower: 'shmeisani',
  );
}
