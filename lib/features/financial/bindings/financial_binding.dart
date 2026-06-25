import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/financial/controllers/cash_movements_controller.dart';
import 'package:fatoora/features/financial/controllers/receivables_controller.dart';
import 'package:fatoora/features/financial/controllers/sales_rep_dashboard_controller.dart';
import 'package:fatoora/features/financial/data/repositories/financial_repository.dart';
import 'package:get/get.dart';

void registerFinancialDependencies() {
  if (!Get.isRegistered<FinancialRepository>()) {
    Get.lazyPut<FinancialRepository>(FinancialRepository.new, fenix: true);
  }
}

class SalesRepDashboardBinding extends Bindings {
  @override
  void dependencies() {
    registerFinancialDependencies();
    Get.lazyPut<SalesRepDashboardController>(
      () => SalesRepDashboardController(
        repository: Get.find<FinancialRepository>(),
        myServices: Get.find<MyServices>(),
      ),
    );
  }
}

class ReceivablesBinding extends Bindings {
  @override
  void dependencies() {
    registerFinancialDependencies();
    Get.lazyPut<ReceivablesController>(
      () => ReceivablesController(
        repository: Get.find<FinancialRepository>(),
        myServices: Get.find<MyServices>(),
      ),
    );
  }
}

class CashMovementsBinding extends Bindings {
  @override
  void dependencies() {
    registerFinancialDependencies();
    Get.lazyPut<CashMovementsController>(
      () => CashMovementsController(
        repository: Get.find<FinancialRepository>(),
        myServices: Get.find<MyServices>(),
      ),
    );
  }
}
