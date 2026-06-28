import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/core/settings/business_settings_resolver.dart';
import 'package:fatoora/features/admin_dashboard/binding/admin_dashboard_binding.dart';
import 'package:fatoora/features/customers/bindings/customers_binding.dart';
import 'package:fatoora/features/receipts/controllers/receipt_details_controller.dart';
import 'package:fatoora/features/receipts/controllers/receipt_form_controller.dart';
import 'package:fatoora/features/receipts/controllers/receipts_list_controller.dart';
import 'package:fatoora/features/receipts/data/repositories/receipt_repository.dart';
import 'package:fatoora/features/settings/bindings/settings_dependencies.dart';
import 'package:get/get.dart';

void registerReceiptDependencies() {
  registerSettingsDependencies();
  registerAdminDashboardDependencies();
  registerCustomerDependencies();
  if (!Get.isRegistered<ReceiptRepository>()) {
    Get.lazyPut<ReceiptRepository>(ReceiptRepository.new, fenix: true);
  }
}

class ReceiptsBinding extends Bindings {
  @override
  void dependencies() {
    registerReceiptDependencies();
    Get.lazyPut<ReceiptsListController>(
      () => ReceiptsListController(
        repository: Get.find<ReceiptRepository>(),
        myServices: Get.find<MyServices>(),
      ),
    );
  }
}

class ReceiptFormBinding extends Bindings {
  @override
  void dependencies() {
    registerReceiptDependencies();
    Get.lazyPut<ReceiptFormController>(
      () => ReceiptFormController(
        repository: Get.find<ReceiptRepository>(),
        myServices: Get.find<MyServices>(),
        settingsResolver: Get.find<BusinessSettingsResolver>(),
      ),
    );
  }
}

class ReceiptDetailsBinding extends Bindings {
  @override
  void dependencies() {
    registerReceiptDependencies();
    Get.lazyPut<ReceiptDetailsController>(
      () => ReceiptDetailsController(
        repository: Get.find<ReceiptRepository>(),
        myServices: Get.find<MyServices>(),
      ),
    );
  }
}
