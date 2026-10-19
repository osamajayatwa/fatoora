import 'package:cloud_functions/cloud_functions.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/localization/translation.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/core/settings/business_permission_resolver.dart';
import 'package:fatoora/core/settings/business_settings_resolver.dart';
import 'package:fatoora/features/invoices/controllers/invoice_error_mapper.dart';
import 'package:fatoora/features/invoices/controllers/invoice_form_controller.dart';
import 'package:fatoora/features/invoices/data/models/invoice_customer_snapshot.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:fatoora/features/invoices/data/models/invoice_item_snapshot.dart';
import 'package:fatoora/features/invoices/data/models/invoice_model.dart';
import 'package:fatoora/features/invoices/data/repositories/invoice_repository.dart';
import 'package:fatoora/features/invoices/data/services/invoice_number_service.dart';
import 'package:fatoora/features/invoices/data/services/invoice_totals_service.dart';
import 'package:fatoora/features/settings/data/models/app_settings_model.dart';
import 'package:fatoora/features/settings/data/models/permission_settings_model.dart';
import 'package:fatoora/features/settings/data/models/user_preferences_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  tearDown(Get.reset);
  test('only exact trusted stock failures receive the stock message', () {
    for (final source in ['representative', 'warehouse']) {
      final error = _shortage(source);
      final stock = InsufficientStockFailure.fromCallable(error)!;
      expect(stock.itemId, 'item-1');
      expect(
        stock.source,
        source == 'representative'
            ? InvoiceStockSource.representative
            : InvoiceStockSource.warehouse,
      );
      expect(InvoiceErrorMapper.insufficientStock(error), isNotNull);
      expect(
        InvoiceErrorMapper.insufficientStock(
          InvoiceRepositoryException(InvoiceRepositoryError.unknown, error),
        ),
        isNotNull,
      );
    }
    for (final error in [
      FirebaseFunctionsException(
        code: 'permission-denied',
        message: 'Insufficient representative stock for item-1.',
      ),
      FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'Invoice is already posted.',
      ),
      FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'Invalid stock source.',
      ),
      FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'Other: Insufficient warehouse stock for item-1.',
      ),
      Exception('Insufficient representative stock for item-1.'),
    ]) {
      expect(InsufficientStockFailure.fromCallable(error), isNull);
      expect(InvoiceErrorMapper.insufficientStock(error), isNull);
      expect(
        InvoiceErrorMapper.messageKey(error),
        isNot(contains('stock_shortage')),
      );
    }
  });

  for (final role in ['sales_rep', 'admin']) {
    for (final locale in ['ar', 'en']) {
      testWidgets(
        '$role/$locale shortage shows translated snackbar and retries the same intact draft',
        (tester) async {
          SharedPreferences.setMockInitialValues({
            'companyId': 'company',
            'role': role,
            'uid': 'user',
          });
          final services = await MyServices().init();
          final repository = _Repository(
            role == 'sales_rep' ? 'representative' : 'warehouse',
          );
          final controller = InvoiceFormController(
            repository: repository,
            numberService: const InvoiceNumberService(),
            totalsService: const InvoiceTotalsService(),
            myServices: services,
            settingsResolver: BusinessSettingsResolver.withLoaders(
              appSettingsLoader: (_) async => AppSettingsModel.defaults,
              userPreferencesLoader: (_) async => UserPreferencesModel.defaults,
            ),
            permissionResolver: _Permissions(role),
          );
          addTearDown(controller.onClose);
          await tester.pumpWidget(
            GetMaterialApp(
              translations: MyTranslation(),
              locale: Locale(locale),
              home: const SizedBox(),
            ),
          );
          await controller.initialize();
          controller.customerSnapshot = InvoiceCustomerSnapshot.fromMap({
            'id': 'customer',
            'name': 'Customer Name',
          });
          controller.items = [
            InvoiceItemSnapshot.fromMap({
              'lineId': 'line-1',
              'lineType': 'catalog',
              'itemId': 'item-1',
              'itemName': 'Water Pump',
              'quantity': 2,
              'unitPrice': 10,
              'discount': 1,
              'taxPercent': 0,
              'subtotal': 20,
              'total': 19,
            }),
          ];
          controller.notesController.text = 'Keep my notes';
          final expected = role == 'sales_rep'
              ? locale == 'ar'
                    ? 'ما معك من هذا الصنف يا فهمان!'
                    : "You don't have enough of this item in your inventory, genius!"
              : locale == 'ar'
              ? 'المخزون المتاح من هذا الصنف في المستودع غير كافٍ.'
              : 'There is not enough of this item in warehouse stock.';
          for (var attempt = 0; attempt < 2; attempt++) {
            await controller.confirmInvoice();
            await tester.pumpAndSettle();
            expect(find.text(expected), findsOneWidget);
            expect(controller.invoiceId, 'saved-draft');
            expect(controller.isEditMode, isTrue);
            expect(controller.statusRequest, StatusRequest.success);
            expect(controller.isSaving, isFalse);
            expect(controller.notesController.text, 'Keep my notes');
            expect(controller.customerSnapshot!.id, 'customer');
            expect(controller.items.single.quantity, 2);
            expect(controller.items.single.discount, 1);
            expect(controller.paymentType, PaymentType.credit);
            expect(repository.saved!.invoiceStatus, InvoiceStatus.draft);
            expect(repository.saved!.grandTotal, 19);
            expect(tester.takeException(), isNull);
            await tester.pump(const Duration(seconds: 4));
            await tester.pumpAndSettle();
          }
          expect(repository.creates, 1);
          expect(repository.updates, 1);
          expect(repository.confirmations, ['saved-draft', 'saved-draft']);
        },
      );
    }
  }
}

FirebaseFunctionsException _shortage(String source) =>
    FirebaseFunctionsException(
      code: 'failed-precondition',
      message: 'Insufficient $source stock for item-1.',
    );

class _Repository implements InvoiceRepository {
  _Repository(this.source);
  final String source;
  int creates = 0;
  int updates = 0;
  InvoiceModel? saved;
  final confirmations = <String>[];
  @override
  Future<String> createInvoice({required InvoiceModel invoice}) async {
    creates++;
    saved = invoice;
    return 'saved-draft';
  }

  @override
  Future<void> updateInvoice({required InvoiceModel invoice}) async {
    updates++;
    saved = invoice;
    expect(invoice.id, 'saved-draft');
  }

  @override
  Future<void> confirmDraftInvoice({
    required String companyId,
    required String invoiceId,
  }) async {
    confirmations.add(invoiceId);
    throw InvoiceRepositoryException(
      InvoiceRepositoryError.unknown,
      _shortage(source),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Permissions implements BusinessPermissionResolver {
  _Permissions(this.role);
  final String role;
  @override
  Future<EffectiveBusinessPermissions> resolve(String companyId) async =>
      EffectiveBusinessPermissions.resolve(
        role: role,
        active: true,
        approvalStatus: 'approved',
        settings: PermissionSettingsModel.defaults,
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
