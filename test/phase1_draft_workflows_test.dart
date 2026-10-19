import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/localization/translation.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/core/settings/business_permission_resolver.dart';
import 'package:fatoora/features/invoices/data/models/invoice_model.dart';
import 'package:fatoora/features/invoices/data/repositories/invoice_repository.dart';
import 'package:fatoora/features/quotations/controllers/quotation_details_controller.dart';
import 'package:fatoora/features/quotations/data/models/quotation_model.dart';
import 'package:fatoora/features/quotations/data/repositories/quotation_repository.dart';
import 'package:fatoora/features/quotations/view/screens/quotation_details_screen.dart';
import 'package:fatoora/features/sales_returns/controllers/sales_return_form_controller.dart';
import 'package:fatoora/features/sales_returns/data/models/sales_return_enums.dart';
import 'package:fatoora/features/sales_returns/data/models/sales_return_model.dart';
import 'package:fatoora/features/sales_returns/data/repositories/sales_return_repository.dart';
import 'package:fatoora/features/settings/data/models/permission_settings_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  tearDown(Get.reset);

  for (final confirm in [false, true]) {
    testWidgets(
      'existing return draft ${confirm ? 'saves before confirming' : 'reopens and saves'} edited quantities',
      (tester) async {
        final services = await _services();
        final repository = _ReturnRepository();
        final controller = SalesReturnFormController(
          repository: repository,
          invoiceRepository: _InvoiceRepository(),
          myServices: services,
          permissionResolver: _Permissions(),
        );
        await tester.pumpWidget(
          GetMaterialApp(
            translations: MyTranslation(),
            locale: const Locale('en'),
            home: const SizedBox(),
            getPages: [
              GetPage(
                name: '/return-editor',
                page: () => const SizedBox(),
                binding: BindingsBuilder(() {
                  Get.put<SalesReturnFormController>(controller);
                }),
              ),
              GetPage(
                name: AppRoute.salesReturnDetails,
                page: () => const SizedBox(),
              ),
            ],
          ),
        );
        Get.toNamed(
          '/return-editor',
          arguments: {'companyId': 'company', 'returnId': 'draft'},
        );
        await tester.pumpAndSettle();
        expect(controller.statusRequest, StatusRequest.success);
        expect(controller.isEditMode, isTrue);
        expect(controller.originalInvoiceId, 'invoice');
        expect(controller.quantityControllers['invoice:line:line']!.text, '1');
        expect(controller.reasonController.text, 'Original reason');
        controller.reasonController.text = 'Edited reason';
        controller.updateReturnedQuantity('invoice:line:line', '2');
        final operation = confirm
            ? controller.confirmReturn()
            : controller.saveDraft();
        await tester.pumpAndSettle();
        expect(repository.calls, confirm ? ['save', 'confirm'] : ['save']);
        expect(repository.saved!.id, 'draft');
        expect(repository.saved!.returnNumber, 'RET-2026-000001');
        expect(repository.saved!.createdByUid, 'rep');
        expect(repository.saved!.reason, 'Edited reason');
        expect(repository.saved!.items.single.returnedQuantity, 2);
        expect(repository.saved!.grandTotal, 20);
        if (confirm) {
          Get.back();
          await tester.pumpAndSettle();
        }
        await operation;
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('posted return cannot reopen as an editable draft', (
    tester,
  ) async {
    final services = await _services();
    final repository = _ReturnRepository(posted: true);
    final controller = SalesReturnFormController(
      repository: repository,
      invoiceRepository: _InvoiceRepository(),
      myServices: services,
      permissionResolver: _Permissions(),
    );
    await tester.pumpWidget(
      GetMaterialApp(
        home: const SizedBox(),
        getPages: [
          GetPage(
            name: '/return-editor',
            page: () => const SizedBox(),
            binding: BindingsBuilder(() {
              Get.put<SalesReturnFormController>(controller);
            }),
          ),
        ],
      ),
    );
    Get.toNamed(
      '/return-editor',
      arguments: {'companyId': 'company', 'returnId': 'draft'},
    );
    await tester.pumpAndSettle();
    expect(controller.statusRequest, isNot(StatusRequest.success));
    expect(controller.items, isEmpty);
    expect(repository.calls, isEmpty);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'quotation draft deletion requires confirmation and returns to its list',
    (tester) async {
      final services = await _services();
      final repository = _QuotationRepository();
      final controller = QuotationDetailsController(
        repository: repository,
        myServices: services,
      );
      await tester.pumpWidget(
        GetMaterialApp(
          translations: MyTranslation(),
          locale: const Locale('en'),
          home: const Text('list'),
          getPages: [
            GetPage(name: '/quote', page: () => const QuotationDetailsScreen()),
          ],
        ),
      );
      Get.put<QuotationDetailsController>(controller);
      Get.toNamed(
        '/quote',
        arguments: {'companyId': 'company', 'quotationId': 'quote'},
      );
      await tester.pumpAndSettle();
      expect(controller.canDelete, isTrue);
      await tester.tap(find.byKey(const ValueKey('quotation-delete-draft')));
      await tester.pumpAndSettle();
      expect(repository.deleted, isFalse);
      await tester.tap(find.byKey(const ValueKey('quotation-delete-confirm')));
      await tester.pumpAndSettle();
      expect(repository.deleted, isTrue);
      expect(find.text('list'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<MyServices> _services() async {
  SharedPreferences.setMockInitialValues({
    'companyId': 'company',
    'role': 'sales_rep',
    'uid': 'rep',
    'active': true,
    'approvalStatus': 'approved',
  });
  final services = await MyServices().init();
  Get.put<MyServices>(services);
  return services;
}

class _Permissions implements BusinessPermissionResolver {
  @override
  Future<EffectiveBusinessPermissions> resolve(String companyId) async =>
      EffectiveBusinessPermissions.resolve(
        role: 'sales_rep',
        active: true,
        approvalStatus: 'approved',
        settings: PermissionSettingsModel.defaults.copyWith(
          allowSalesRepCreateReturns: false,
        ),
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _InvoiceRepository implements InvoiceRepository {
  @override
  Future<InvoiceModel?> getInvoiceById({
    required String companyId,
    required String invoiceId,
  }) async => InvoiceModel.fromMap({
    'id': 'invoice',
    'companyId': 'company',
    'invoiceNumber': 'INV-2026-000001',
    'invoiceStatus': 'confirmed',
    'isLocked': true,
    'financialPosted': true,
    'inventoryPosted': true,
    'customerId': 'customer',
    'salesRepId': 'rep',
    'salesRepName': 'Rep',
    'items': [
      {
        'lineId': 'line',
        'lineType': 'custom',
        'itemId': null,
        'itemName': 'Service',
        'description': 'At site',
        'unit': 'service',
        'quantity': 3,
        'unitPrice': 10,
        'subtotal': 30,
        'total': 30,
      },
    ],
  });
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ReturnRepository implements SalesReturnRepository {
  _ReturnRepository({this.posted = false});
  final bool posted;
  final calls = <String>[];
  SalesReturnModel? saved;
  @override
  Future<SalesReturnModel?> getSalesReturnById({
    String companyId = 'default_company',
    required String returnId,
  }) async => SalesReturnModel.fromMap({
    'id': 'draft',
    'companyId': 'company',
    'returnNumber': 'RET-2026-000001',
    'returnInvoiceId': 'draft',
    'originalInvoiceId': 'invoice',
    'status': 'draft',
    'financialPosted': posted,
    'inventoryPosted': false,
    'salesRepId': 'rep',
    'createdByUid': 'rep',
    'createdByName': 'Rep',
    'createdByRole': 'sales_rep',
    'reason': 'Original reason',
    'refundType': 'credit_customer_balance',
    'items': [
      {'originalInvoiceItemId': 'invoice:line:line', 'returnedQuantity': 1},
    ],
  });
  @override
  Future<Map<String, double>> getConfirmedReturnedQuantities({
    String companyId = 'default_company',
    required String originalInvoiceId,
  }) async => {};
  @override
  Future<SalesReturnModel> saveDraft({
    required SalesReturnModel salesReturn,
  }) async {
    calls.add('save');
    saved = salesReturn;
    return salesReturn;
  }

  @override
  Future<SalesReturnModel> confirmSalesReturn({
    required SalesReturnModel salesReturn,
  }) async {
    calls.add('confirm');
    expect(
      salesReturn.items.single.returnedQuantity,
      saved!.items.single.returnedQuantity,
    );
    return salesReturn.copyWith(status: SalesReturnStatus.confirmed);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QuotationRepository implements QuotationRepository {
  bool deleted = false;
  @override
  Future<QuotationModel?> getQuotationById({
    required String companyId,
    required String quotationId,
  }) async => QuotationModel.empty(
    companyId: 'company',
    createdByUid: 'rep',
    createdByName: 'Rep',
    createdByRole: 'sales_rep',
  ).copyWith(id: 'quote', quotationNumber: 'QUO-2026-000001');
  @override
  Future<void> deleteDraftQuotation({
    required String companyId,
    required String quotationId,
  }) async {
    expect(companyId, 'company');
    expect(quotationId, 'quote');
    deleted = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
