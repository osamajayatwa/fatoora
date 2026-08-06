import 'package:fatoora/app/routes/app_routes.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

bool keepInvoiceParentRoute(Route<dynamic> route) {
  final name = route.settings.name;
  return name == null || !name.startsWith('/invoices/');
}

mixin InvoicePageNavigation on GetxController {
  bool allowPop = false;
  bool _isLeaving = false;

  Future<void> leaveInvoicePage({
    required String fallbackRoute,
    Object? result,
    Object? fallbackArguments,
  }) async {
    if (_isLeaving) return;
    _isLeaving = true;

    final navigator = Get.key.currentState;
    if (navigator?.canPop() == true) {
      allowPop = true;
      update();
      await WidgetsBinding.instance.endOfFrame;
      Get.back(result: result);
      return;
    }

    Get.offNamed(fallbackRoute, arguments: fallbackArguments);
  }

  Future<void> showSavedInvoiceDetails({
    required String companyId,
    required String invoiceId,
  }) async {
    if (_isLeaving) return;
    if (companyId.trim().isEmpty || invoiceId.trim().isEmpty) {
      return leaveInvoicePage(fallbackRoute: AppRoute.invoices, result: true);
    }

    _isLeaving = true;
    allowPop = true;
    update();
    await WidgetsBinding.instance.endOfFrame;
    Get.offNamedUntil<void>(
      AppRoute.invoiceDetailsPath(invoiceId),
      keepInvoiceParentRoute,
      arguments: {'companyId': companyId, 'invoiceId': invoiceId},
    );
  }
}
