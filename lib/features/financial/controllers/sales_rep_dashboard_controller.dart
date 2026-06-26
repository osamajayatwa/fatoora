import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/financial/controllers/financial_error_mapper.dart';
import 'package:fatoora/features/financial/data/models/financial_dashboard_snapshot.dart';
import 'package:fatoora/features/financial/data/repositories/financial_repository.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:get/get.dart';

class SalesRepDashboardController extends GetxController {
  SalesRepDashboardController({
    required FinancialRepository repository,
    required MyServices myServices,
  }) : _repository = repository,
       _myServices = myServices;

  final FinancialRepository _repository;
  final MyServices _myServices;

  StatusRequest statusRequest = StatusRequest.loading;
  String loadErrorMessageKey = 'financial_load_error';
  FinancialDashboardSnapshot snapshot =
      const FinancialDashboardSnapshot.empty();

  String get companyId =>
      _myServices.sharedPreferences.getString('companyId') ??
      AuthRepository.defaultCompanyId;

  @override
  void onReady() {
    super.onReady();
    loadDashboard();
  }

  Future<void> loadDashboard() async {
    statusRequest = StatusRequest.loading;
    update();
    try {
      snapshot = await _repository.fetchDashboard(companyId: companyId);
      statusRequest = StatusRequest.success;
    } catch (error) {
      statusRequest = FinancialErrorMapper.status(error);
      loadErrorMessageKey = FinancialErrorMapper.messageKey(error);
    }
    if (!isClosed) update();
  }

  Future<void> refreshDashboard() => loadDashboard();

  void createInvoice() {
    Get.toNamed(
      AppRoute.invoiceForm,
      arguments: {'mode': 'create', 'invoiceType': InvoiceType.regular.value},
    );
  }

  void openInvoices() => Get.toNamed(AppRoute.invoices);
  void openCustomers() => Get.toNamed(AppRoute.customers);
  void openReceivables() => Get.toNamed(AppRoute.receivables);
  void openCash() => Get.toNamed(AppRoute.cashMovements);
  void openSalesReturns() => Get.toNamed(AppRoute.salesReturns);
}
