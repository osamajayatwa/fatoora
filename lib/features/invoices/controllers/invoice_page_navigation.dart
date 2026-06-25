import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

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
}
