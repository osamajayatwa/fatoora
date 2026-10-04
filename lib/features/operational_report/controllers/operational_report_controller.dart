import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/operational_report/data/models/operational_report_filters.dart';
import 'package:fatoora/features/operational_report/data/repositories/operational_report_repository.dart';
import 'package:fatoora/features/operational_report/data/services/operational_report_excel_service.dart';
import 'package:get/get.dart';

class OperationalReportController extends GetxController {
  OperationalReportController({
    required OperationalReportRepository repository,
    required OperationalReportExcelService excelService,
    required MyServices myServices,
  }) : _repository = repository,
       _excelService = excelService,
       _myServices = myServices;

  final OperationalReportRepository _repository;
  final OperationalReportExcelService _excelService;
  final MyServices _myServices;

  bool isExporting = false;

  String get companyId =>
      _myServices.sharedPreferences.getString('companyId') ??
      AuthRepository.defaultCompanyId;

  Future<void> exportReport({DateTime? fromDate, DateTime? toDate}) async {
    if (isExporting) return;
    isExporting = true;
    update();
    try {
      final filters = OperationalReportFilters(
        fromDate: fromDate,
        toDate: toDate,
      );
      final data = await _repository.fetchReport(
        companyId: companyId,
        filters: filters,
      );
      await _excelService.saveReport(data: data, filters: filters);
      final message = data.warnings.isEmpty
          ? 'operational_report_export_success'.tr
          : 'operational_report_export_success_warnings'.trParams({
              'count': data.warnings.length.toString(),
            });
      Get.snackbar('operational_report'.tr, message);
    } catch (error) {
      Get.snackbar('operational_report'.tr, _messageFor(error).tr);
    } finally {
      isExporting = false;
      if (!isClosed) update();
    }
  }

  String _messageFor(Object error) {
    if (error is OperationalReportRepositoryException) {
      return switch (error.error) {
        OperationalReportRepositoryError.permissionDenied =>
          'operational_report_permission_error',
        OperationalReportRepositoryError.invalidData =>
          'operational_report_invalid_range',
        OperationalReportRepositoryError.offline =>
          'operational_report_offline_error',
        OperationalReportRepositoryError.timeout =>
          'operational_report_timeout_error',
        OperationalReportRepositoryError.unknown =>
          'operational_report_export_error',
      };
    }
    return 'operational_report_export_error';
  }
}
