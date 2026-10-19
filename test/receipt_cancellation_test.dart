import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:excel/excel.dart';
import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/localization/translation.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/invoices/data/models/invoice_customer_snapshot.dart';
import 'package:fatoora/features/receipts/controllers/receipt_details_controller.dart';
import 'package:fatoora/features/receipts/controllers/receipt_error_mapper.dart';
import 'package:fatoora/features/receipts/data/models/receipt_model.dart';
import 'package:fatoora/features/operational_report/data/models/operational_report_data.dart';
import 'package:fatoora/features/operational_report/data/services/operational_report_excel_service.dart';
import 'package:fatoora/features/receipts/data/services/receipt_pdf_service.dart';
import 'package:fatoora/core/pdf/business_pdf_configuration.dart';
import 'package:fatoora/features/receipts/data/repositories/receipt_repository.dart';
import 'package:fatoora/features/receipts/view/screens/receipt_details_screen.dart';
import 'package:fatoora/features/receipts/view/screens/receipts_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ar'));
  tearDown(Get.reset);
  test(
    'legacy receipts default to posted and cancelled metadata round-trips',
    () {
      final original = _receipt().toMap()..remove('status');
      expect(ReceiptModel.fromFirestore(_Snapshot(original)).isPosted, isTrue);
      final cancelled = ReceiptModel.fromFirestore(
        _Snapshot(_receipt(cancelled: true).toMap()),
      );
      expect(cancelled.isCancelled, isTrue);
      expect(cancelled.amount, 35);
      expect(cancelled.effectiveAmount, 0);
      expect(cancelled.invoiceAllocations, {'invoice': 35});
      expect(cancelled.cancellationReason, 'Wrong payment');
      expect(cancelled.cancelledByUid, 'admin');
      expect(cancelled.cancelledAt, DateTime(2026, 10, 19));
    },
  );
  test('trusted dependency details map to specific cancellation errors', () {
    for (final entry in {
      'allocated invoice has sales returns': 'receipts_cancel_blocked_returns',
      'cash has subsequent spending or settlements':
          'receipts_cancel_blocked_cash',
      'customer credit has subsequent transactions':
          'receipts_cancel_blocked_credit',
      'incomplete financial ledger': 'receipts_cancel_blocked_history',
    }.entries) {
      expect(ReceiptErrorMapper.messageKey(_blocked(entry.key)), entry.value);
    }
    expect(
      ReceiptErrorMapper.messageKey(
        ReceiptRepositoryException(
          ReceiptRepositoryError.unknown,
          FirebaseFunctionsException(
            code: 'unavailable',
            message: 'Other error',
          ),
        ),
      ),
      'receipts_error',
    );
  });
  test(
    'cancelled operational export separates zero effective amounts from historical evidence',
    () {
      final receipt = _receipt(cancelled: true);
      final rows = buildOperationalReceiptRows([receipt], {});
      expect(rows.single.totalAllocatedAmount, 0);
      expect(rows.single.unallocatedAmount, 0);
      final bytes = OperationalReportExcelService().buildWorkbook(
        OperationalReportData(
          companyId: 'default_company',
          invoices: [],
          expenses: [],
          receipts: [receipt],
        ),
      );
      final sheet = Excel.decodeBytes(bytes)['Receipts'];
      expect(double.parse(sheet.rows[1][4]!.value.toString()), 0);
      expect(sheet.rows[1][17]!.value.toString(), contains('Cancelled'));
      expect(double.parse(sheet.rows[1][18]!.value.toString()), 35);
      expect(sheet.rows[1][19]!.value.toString(), contains('Wrong payment'));
    },
  );
  test(
    'cancelled historical PDF still renders in Arabic and English',
    () async {
      for (final locale in ['ar', 'en']) {
        final bytes = await ReceiptPdfService.build(
          _receipt(cancelled: true),
          configuration: BusinessPdfConfiguration.defaults(
            languageCode: locale,
          ),
        );
        expect(bytes.length, greaterThan(1000));
      }
    },
  );
  for (final locale in ['ar', 'en']) {
    testWidgets(
      'admin $locale confirms a required reason and sees an immutable cancelled receipt',
      (tester) async {
        final repo = _Repository();
        final controller = await _pump(tester, repo, locale: locale);
        expect(controller.canCancel, isTrue);
        await tester.ensureVisible(
          find.byKey(const ValueKey('receipt-cancel-action')),
        );
        await tester.tap(find.byKey(const ValueKey('receipt-cancel-action')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('receipt-cancel-confirm')));
        await tester.pumpAndSettle();
        expect(repo.reasons, isEmpty);
        expect(find.text('receipts_cancel_reason_required'.tr), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('receipt-cancel-reason')),
          ' Wrong payment ',
        );
        await tester.tap(find.byKey(const ValueKey('receipt-cancel-confirm')));
        await tester.pumpAndSettle();
        expect(repo.reasons, ['Wrong payment']);
        expect(controller.receipt!.isCancelled, isTrue);
        expect(controller.canCancel, isFalse);
        expect(
          find.byKey(const ValueKey('receipt-cancel-action')),
          findsNothing,
        );
        expect(find.text('receipts_status_cancelled'.tr), findsOneWidget);
        expect(find.textContaining('Wrong payment'), findsOneWidget);
        expect(controller.receipt!.amount, 35);
        expect(
          find.text('export_pdf'.tr),
          findsOneWidget,
          reason: 'Historical PDF remains available and is labelled cancelled.',
        );
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
      },
    );
  }
  testWidgets(
    'Sales Rep cannot invoke cancellation; posted and cancelled receipts remain viewable',
    (tester) async {
      final repo = _Repository();
      final controller = await _pump(tester, repo, role: 'sales_rep');
      expect(controller.canCancel, isFalse);
      expect(find.byKey(const ValueKey('receipt-cancel-action')), findsNothing);
      await controller.cancelReceipt('Attempt');
      expect(repo.reasons, isEmpty);
      controller.receipt = _receipt(cancelled: true);
      controller.update();
      await tester.pumpAndSettle();
      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.byKey(const ValueKey('receipt-cancel-action')), findsNothing);
    },
  );
  testWidgets(
    'cancel request is guarded in flight and failures keep original details visible',
    (tester) async {
      final repo = _Repository()..pending = Completer();
      final controller = await _pump(tester, repo);
      final first = controller.cancelReceipt('Valid reason');
      await controller.cancelReceipt('Second click');
      expect(repo.reasons, ['Valid reason']);
      expect(controller.isCancelling, isTrue);
      repo.pending!.completeError(
        _blocked('cash has subsequent spending or settlements'),
      );
      await first;
      await tester.pumpAndSettle();
      expect(controller.receipt!.isPosted, isTrue);
      expect(controller.canCancel, isTrue);
      expect(find.text('receipts_cancel_blocked_cash'.tr), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    },
  );
  testWidgets('cancelled list card clearly labels the historical amount', (
    tester,
  ) async {
    await tester.pumpWidget(
      GetMaterialApp(
        translations: MyTranslation(),
        locale: const Locale('en'),
        home: Scaffold(
          body: ReceiptListCard(
            receipt: _receipt(cancelled: true),
            showSalesRepresentative: true,
            onTap: () {},
          ),
        ),
      ),
    );
    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.textContaining('35.000'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

ReceiptRepositoryException _blocked(String dependency) =>
    ReceiptRepositoryException(
      ReceiptRepositoryError.unknown,
      FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'Unsafe cancellation',
        details: {
          'reason': 'receipt-cancellation-unsafe',
          'dependency': dependency,
        },
      ),
    );

Future<ReceiptDetailsController> _pump(
  WidgetTester tester,
  _Repository repo, {
  String role = 'admin',
  String locale = 'en',
}) async {
  SharedPreferences.setMockInitialValues({
    'companyId': 'default_company',
    'role': role,
    'uid': role,
  });
  final services = await MyServices().init();
  Get.put<MyServices>(services);
  final controller = Get.put(
    ReceiptDetailsController(repository: repo, myServices: services),
  );
  await tester.pumpWidget(
    GetMaterialApp(
      translations: MyTranslation(),
      locale: Locale(locale),
      initialRoute: AppRoute.receiptDetailsPath('receipt'),
      getPages: [
        GetPage(
          name: AppRoute.receiptDetails,
          page: () => const ReceiptDetailsScreen(),
        ),
      ],
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

ReceiptModel _receipt({bool cancelled = false}) => ReceiptModel(
  id: 'receipt',
  companyId: 'default_company',
  receiptNumber: 'REC-001',
  receiptDate: DateTime(2026),
  customerId: 'customer',
  customerSnapshot: InvoiceCustomerSnapshot.fromMap({
    'id': 'customer',
    'name': 'Customer',
  }),
  amount: 35,
  paymentMethod: 'cash',
  notes: 'Original notes',
  salesRepId: 'rep',
  salesRepName: 'Rep',
  createdByUid: 'rep',
  createdByName: 'Rep',
  createdByRole: 'sales_rep',
  customerTransactionIds: ['credit'],
  cashMovementIds: ['cash'],
  invoiceAllocations: {'invoice': 35},
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  status: cancelled ? 'cancelled' : 'posted',
  cancelledAt: cancelled ? DateTime(2026, 10, 19) : null,
  cancelledByUid: cancelled ? 'admin' : '',
  cancelledByName: cancelled ? 'Admin' : '',
  cancellationReason: cancelled ? 'Wrong payment' : '',
);

class _Repository implements ReceiptRepository {
  final reasons = <String>[];
  Completer<ReceiptModel>? pending;
  @override
  Future<ReceiptModel?> getReceiptById({
    String companyId = 'default_company',
    required String receiptId,
  }) async => _receipt();
  @override
  Future<ReceiptModel> cancelReceipt({
    required String companyId,
    required String receiptId,
    required String reason,
  }) {
    reasons.add(reason);
    return pending?.future ?? Future.value(_receipt(cancelled: true));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Firestore snapshots are sealed; this read-only fixture supplies model data.
// ignore: subtype_of_sealed_class
class _Snapshot implements DocumentSnapshot<Map<String, dynamic>> {
  _Snapshot(this.value);
  final Map<String, dynamic> value;
  @override
  String get id => 'receipt';
  @override
  Map<String, dynamic> data() => value;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
