import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/app/routes/not_found_screen.dart';
import 'package:fatoora/core/middleware/middleware.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  tearDown(Get.reset);

  test('record path builders produce stable URL-addressable paths', () {
    expect(AppRoute.customerDetailsPath('customer-1'), '/customers/customer-1');
    expect(
      AppRoute.customerEditPath('customer-1'),
      '/customers/customer-1/edit',
    );
    expect(AppRoute.itemDetailsPath('item-1'), '/items/item-1');
    expect(AppRoute.invoiceDetailsPath('invoice-1'), '/invoices/invoice-1');
    expect(AppRoute.invoiceEditPath('invoice-1'), '/invoices/invoice-1/edit');
    expect(AppRoute.quotationDetailsPath('quote-1'), '/quotations/quote-1');
    expect(AppRoute.receiptDetailsPath('receipt-1'), '/receipts/receipt-1');
    expect(
      AppRoute.salesReturnDetailsPath('return-1'),
      '/sales-returns/return-1',
    );
    expect(AppRoute.expenseDetailsPath('expense-1'), '/expenses/expense-1');
    expect(
      AppRoute.inventoryTransferDetailsPath('transfer-1'),
      '/inventory-transfers/transfer-1',
    );
  });

  testWidgets('direct customer link restores its route identity', (
    tester,
  ) async {
    await tester.pumpWidget(
      GetMaterialApp(
        initialRoute: AppRoute.customerDetailsPath('customer-direct'),
        getPages: [
          GetPage(
            name: AppRoute.customerDetails,
            page: () => Text(
              'customer:${Get.parameters['customerId']}',
              textDirection: TextDirection.ltr,
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('customer:customer-direct'), findsOneWidget);
  });

  testWidgets('direct invoice edit link remains edit mode after startup', (
    tester,
  ) async {
    await tester.pumpWidget(
      GetMaterialApp(
        initialRoute: AppRoute.invoiceEditPath('invoice-direct'),
        getPages: [
          GetPage(
            name: AppRoute.invoiceEdit,
            page: () => Text(
              'edit:${Get.parameters['invoiceId']}',
              textDirection: TextDirection.ltr,
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('edit:invoice-direct'), findsOneWidget);
  });

  testWidgets('unknown route renders a recoverable not-found page', (
    tester,
  ) async {
    await tester.pumpWidget(
      GetMaterialApp(
        translations: _TestTranslations(),
        locale: const Locale('en'),
        initialRoute: '/does-not-exist',
        getPages: [
          GetPage(
            name: '/',
            page: () => const SizedBox.shrink(),
            middlewares: [ExactRouteMiddleware()],
          ),
          GetPage(name: AppRoute.notFound, page: NotFoundScreen.new),
        ],
        unknownRoute: GetPage(
          name: AppRoute.notFound,
          page: NotFoundScreen.new,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NotFoundScreen), findsOneWidget);
    expect(find.text('Page not found'), findsOneWidget);
    expect(find.text('Go back'), findsOneWidget);
  });
}

class _TestTranslations extends Translations {
  @override
  Map<String, Map<String, String>> get keys => {
    'en': {
      'page_not_found_title': 'Page not found',
      'page_not_found_body': 'Unavailable',
      'go_back': 'Go back',
    },
  };
}
