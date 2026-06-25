import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/financial/controllers/financial_error_mapper.dart';
import 'package:fatoora/features/financial/data/models/financial_dashboard_snapshot.dart';
import 'package:fatoora/features/financial/data/repositories/financial_repository.dart';
import 'package:get/get.dart';

class ReceivablesController extends GetxController {
  ReceivablesController({
    required FinancialRepository repository,
    required MyServices myServices,
  }) : _repository = repository,
       _myServices = myServices;

  final FinancialRepository _repository;
  final MyServices _myServices;

  StatusRequest statusRequest = StatusRequest.loading;
  String loadErrorMessageKey = 'financial_load_error';
  DateTime? fromDate;
  DateTime? toDate;
  FinancialReceivablesSnapshot snapshot = const FinancialReceivablesSnapshot(
    customers: [],
    totalReceivables: 0,
  );

  String get companyId =>
      _myServices.sharedPreferences.getString('companyId') ??
      AuthRepository.defaultCompanyId;

  @override
  void onReady() {
    super.onReady();
    loadReceivables();
  }

  Future<void> loadReceivables() async {
    statusRequest = StatusRequest.loading;
    update();
    try {
      snapshot = await _repository.fetchReceivables(
        companyId: companyId,
        fromDate: fromDate,
        toDate: toDate,
      );
      statusRequest = StatusRequest.success;
    } catch (error) {
      statusRequest = FinancialErrorMapper.status(error);
      loadErrorMessageKey = FinancialErrorMapper.messageKey(error);
    }
    if (!isClosed) update();
  }

  Future<void> refreshReceivables() => loadReceivables();

  void setDateRange(DateTime? from, DateTime? to) {
    fromDate = from;
    toDate = to;
    loadReceivables();
  }

  void clearDateRange() {
    fromDate = null;
    toDate = null;
    loadReceivables();
  }

  void openStatement(FinancialCustomerBalance item) {
    Get.toNamed(
      AppRoute.customerStatement,
      arguments: {'companyId': companyId, 'customerId': item.customer.id},
    );
  }
}
