import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/features/invoices/controllers/invoice_page_navigation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saved invoice navigation removes form and stale details routes', () {
    expect(keepInvoiceParentRoute(_route(AppRoute.invoiceForm)), isFalse);
    expect(keepInvoiceParentRoute(_route(AppRoute.invoiceDetails)), isFalse);
  });

  test('saved invoice navigation preserves its parent route', () {
    expect(keepInvoiceParentRoute(_route(AppRoute.invoices)), isTrue);
    expect(keepInvoiceParentRoute(_route(AppRoute.adminHome)), isTrue);
  });
}

Route<void> _route(String name) {
  return PageRouteBuilder<void>(
    settings: RouteSettings(name: name),
    pageBuilder: (_, _, _) => const SizedBox.shrink(),
  );
}
