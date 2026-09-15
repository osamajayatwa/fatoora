import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/financial_ledger/controllers/financial_ledger_controller.dart';
import 'package:fatoora/features/financial_ledger/data/repositories/financial_ledger_repository.dart';
import 'package:fatoora/features/financial_ledger/data/services/financial_ledger_excel_service.dart';
import 'package:get/get.dart';

class FinancialLedgerBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<FinancialLedgerRepository>()) {
      Get.lazyPut<FinancialLedgerRepository>(
        FinancialLedgerRepository.new,
        fenix: true,
      );
    }
    if (!Get.isRegistered<FinancialLedgerExcelService>()) {
      Get.lazyPut<FinancialLedgerExcelService>(
        FinancialLedgerExcelService.new,
        fenix: true,
      );
    }
    Get.lazyPut<FinancialLedgerController>(
      () => FinancialLedgerController(
        repository: Get.find<FinancialLedgerRepository>(),
        excelService: Get.find<FinancialLedgerExcelService>(),
        myServices: Get.find<MyServices>(),
      ),
    );
  }
}
