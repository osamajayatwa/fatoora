import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/financial_ledger/controllers/financial_ledger_controller.dart';
import 'package:fatoora/features/financial_ledger/data/repositories/financial_ledger_repository.dart';
import 'package:fatoora/features/financial_ledger/data/services/financial_ledger_excel_service.dart';
import 'package:fatoora/features/operational_report/controllers/operational_report_controller.dart';
import 'package:fatoora/features/operational_report/data/repositories/operational_report_repository.dart';
import 'package:fatoora/features/operational_report/data/services/operational_report_excel_service.dart';
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
    if (!Get.isRegistered<OperationalReportRepository>()) {
      Get.lazyPut<OperationalReportRepository>(
        OperationalReportRepository.new,
        fenix: true,
      );
    }
    if (!Get.isRegistered<OperationalReportExcelService>()) {
      Get.lazyPut<OperationalReportExcelService>(
        OperationalReportExcelService.new,
        fenix: true,
      );
    }
    Get.lazyPut<OperationalReportController>(
      () => OperationalReportController(
        repository: Get.find<OperationalReportRepository>(),
        excelService: Get.find<OperationalReportExcelService>(),
        myServices: Get.find<MyServices>(),
      ),
    );
    Get.lazyPut<FinancialLedgerController>(
      () => FinancialLedgerController(
        repository: Get.find<FinancialLedgerRepository>(),
        excelService: Get.find<FinancialLedgerExcelService>(),
        myServices: Get.find<MyServices>(),
      ),
    );
  }
}
