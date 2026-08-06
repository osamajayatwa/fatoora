import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/data/firestore_query_pager.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/invoices/controllers/invoices_list_controller.dart';
import 'package:fatoora/features/invoices/data/models/invoice_customer_snapshot.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:fatoora/features/invoices/data/models/invoice_model.dart';
import 'package:fatoora/features/invoices/data/repositories/invoice_repository.dart';
import 'package:fatoora/features/invoices/view/screens/invoices_list_screen.dart';
import 'package:fatoora/features/invoices/view/widgets/invoice_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    await Get.delete<InvoicesListController>(force: true);
    await Get.delete<MyServices>(force: true);
    Get.reset();
  });

  testWidgets('invoice list uses cards at narrow mobile width', (tester) async {
    await _pumpInvoiceList(tester, const Size(390, 800));

    expect(find.byType(InvoiceCard), findsNWidgets(_invoices.length));
    expect(find.byType(DataTable), findsNothing);
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'invoice list shows accessible View and PDF actions at 1024 web width',
    (tester) async {
      await _pumpInvoiceList(tester, const Size(1024, 800));

      expect(find.byType(DataTable), findsOneWidget);
      expect(find.byType(InvoiceCard), findsNothing);
      expect(
        find.byTooltip('invoice_details'),
        findsNWidgets(_invoices.length),
      );
      expect(find.byTooltip('print_export'), findsNWidgets(_invoices.length));
      _expectFinderInsideViewport(
        tester,
        find.byTooltip('print_export').first,
        viewportWidth: 1024,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('invoice list uses full table columns at wide web width', (
    tester,
  ) async {
    await _pumpInvoiceList(tester, const Size(1536, 900));

    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('return_status'), findsWidgets);
    expect(find.text('created_by'), findsWidgets);
    expect(find.byTooltip('print_export'), findsNWidgets(_invoices.length));
    _expectFinderInsideViewport(
      tester,
      find.byTooltip('print_export').last,
      viewportWidth: 1536,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('invoice list keeps actions visible at 1366 web width', (
    tester,
  ) async {
    await _pumpInvoiceList(tester, const Size(1366, 850));

    expect(find.byType(DataTable), findsOneWidget);
    expect(find.byTooltip('invoice_details'), findsNWidgets(_invoices.length));
    expect(find.byTooltip('print_export'), findsNWidgets(_invoices.length));
    _expectFinderInsideViewport(
      tester,
      find.byTooltip('print_export').last,
      viewportWidth: 1366,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('invoice table supports Arabic customer names without overflow', (
    tester,
  ) async {
    await _pumpInvoiceList(
      tester,
      const Size(1024, 800),
      locale: const Locale('ar'),
    );

    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('شركة مضخات المياه المتقدمة'), findsOneWidget);
    expect(find.byTooltip('print_export'), findsNWidgets(_invoices.length));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpInvoiceList(
  WidgetTester tester,
  Size size, {
  Locale locale = const Locale('en'),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  SharedPreferences.setMockInitialValues({
    'companyId': 'default_company',
    'role': 'sales_rep',
    'uid': 'rep-1',
    'name': 'Sales Rep',
    'approvalStatus': 'approved',
    'active': true,
  });
  Get.reset();
  final services = await MyServices().init();
  Get.put<MyServices>(services);
  final controller = InvoicesListController(
    repository: _FakeInvoiceRepository(_invoices),
    myServices: services,
  );
  controller.statusRequest = StatusRequest.success;
  controller.invoices = _invoices;
  Get.put<InvoicesListController>(controller);

  await tester.pumpWidget(
    GetMaterialApp(locale: locale, home: const InvoicesListScreen()),
  );
  await tester.pumpAndSettle();
}

void _expectFinderInsideViewport(
  WidgetTester tester,
  Finder finder, {
  required double viewportWidth,
}) {
  final topRight = tester.getTopRight(finder);
  final bottomRight = tester.getBottomRight(finder);

  expect(topRight.dx, lessThanOrEqualTo(viewportWidth));
  expect(bottomRight.dx, lessThanOrEqualTo(viewportWidth));
}

class _FakeInvoiceRepository implements InvoiceRepository {
  const _FakeInvoiceRepository(this.invoices);

  final List<InvoiceModel> invoices;

  @override
  Future<List<InvoiceModel>> getInvoices({
    required String companyId,
    InvoiceType? type,
    InvoiceStatus? status,
    DateTime? fromDate,
    DateTime? toDate,
    String? searchText,
  }) async {
    return invoices
        .where((invoice) => type == null || invoice.invoiceType == type)
        .where((invoice) => status == null || invoice.invoiceStatus == status)
        .toList(growable: false);
  }

  @override
  Future<FirestorePage<InvoiceModel>> getInvoicesPage({
    required String companyId,
    InvoiceType? type,
    InvoiceStatus? status,
    DateTime? fromDate,
    DateTime? toDate,
    String? searchText,
    FirestorePageCursor? after,
    int pageSize = 50,
  }) async {
    return FirestorePage(
      items: await getInvoices(
        companyId: companyId,
        type: type,
        status: status,
        fromDate: fromDate,
        toDate: toDate,
        searchText: searchText,
      ),
      cursor: null,
      hasMore: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _invoices = [
  _invoice(
    id: 'invoice-1',
    number: 'INV-2026-000001',
    customerName: 'شركة مضخات المياه المتقدمة',
    status: InvoiceStatus.draft,
    paymentStatus: PaymentStatus.unpaid,
    amount: 145.75,
  ),
  _invoice(
    id: 'invoice-2',
    number: 'INV-2026-000002',
    customerName:
        'International Pumping Solutions With A Very Long Customer Name',
    status: InvoiceStatus.confirmed,
    paymentStatus: PaymentStatus.partiallyPaid,
    amount: 2040.125,
  ),
  _invoice(
    id: 'invoice-3',
    number: 'INV-2026-000003',
    customerName: 'Fujika Model FDSS 4SP-10 Customer',
    status: InvoiceStatus.accepted,
    paymentStatus: PaymentStatus.paid,
    amount: 99.5,
  ),
];

InvoiceModel _invoice({
  required String id,
  required String number,
  required String customerName,
  required InvoiceStatus status,
  required PaymentStatus paymentStatus,
  required double amount,
}) {
  final now = DateTime(2026, 7, 12);
  return InvoiceModel(
    id: id,
    companyId: 'default_company',
    invoiceNumber: number,
    invoiceType: InvoiceType.regular,
    invoiceStatus: status,
    paymentType: paymentStatus == PaymentStatus.paid
        ? PaymentType.cash
        : PaymentType.credit,
    paymentStatus: paymentStatus,
    hasReceivedPayment: paymentStatus != PaymentStatus.unpaid,
    invoiceDate: now,
    dueDate: now.add(const Duration(days: 14)),
    createdAt: now,
    updatedAt: now,
    createdByUid: 'rep-1',
    createdByName: 'Sales Representative With Long Name',
    createdByRole: 'sales_rep',
    salesRepId: 'rep-1',
    salesRepName: 'Sales Rep',
    customerId: 'customer-$id',
    customerSnapshot: InvoiceCustomerSnapshot(
      id: 'customer-$id',
      name: customerName,
      phone: '+962 79 123 4567',
      address: 'Amman',
      taxNumber: '',
      nationalNumber: '',
      city: 'Amman',
    ),
    items: const [],
    subtotal: amount,
    totalDiscount: 0,
    totalTax: 0,
    grandTotal: amount,
    paidAmount: paymentStatus == PaymentStatus.paid ? amount : 0,
    remainingAmount: paymentStatus == PaymentStatus.paid ? 0 : amount,
    notes: '',
    paymentMethod: paymentStatus.value,
    isLocked: status != InvoiceStatus.draft,
    financialPosted: status != InvoiceStatus.draft,
    financialPostedByUid: '',
    financialPostedByName: '',
    customerTransactionIds: const [],
    cashMovementIds: const [],
    inventoryPosted: false,
    inventoryPostedByUid: '',
    inventoryPostedByName: '',
    inventoryMovementIds: const [],
    searchKeywords: const [],
    customerNameLower: customerName.toLowerCase(),
    itemNamesLower: const [],
    invoiceNumberLower: number.toLowerCase(),
    dateString: '2026-07-12',
  );
}
