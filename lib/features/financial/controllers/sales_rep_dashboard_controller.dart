import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/settings/business_permission_resolver.dart';
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
    required BusinessPermissionResolver permissionResolver,
  }) : _repository = repository,
       _myServices = myServices,
       _permissionResolver = permissionResolver;

  final FinancialRepository _repository;
  final MyServices _myServices;
  final BusinessPermissionResolver _permissionResolver;

  StatusRequest statusRequest = StatusRequest.loading;
  String loadErrorMessageKey = 'financial_load_error';
  FinancialDashboardSnapshot snapshot =
      const FinancialDashboardSnapshot.empty();
  EffectiveBusinessPermissions permissions =
      EffectiveBusinessPermissions.denied;
  bool get canCreateQuotation => permissions.createQuotations;

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
      permissions = await _permissionResolver.resolve(companyId);
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
  void openQuotations() => Get.toNamed(AppRoute.quotations);
  void createQuotation() {
    if (!canCreateQuotation) {
      Get.snackbar(
        'permission_denied'.tr,
        'sales_rep_quotation_create_disabled'.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppColor.error,
        colorText: AppColor.surface,
      );
      return;
    }
    Get.toNamed(AppRoute.createQuotation);
  }

  void openCustomers() => Get.toNamed(AppRoute.customers);
  void openStatements() => Get.toNamed(AppRoute.statements);
  void openReceivables() => Get.toNamed(AppRoute.receivables);
  void openCash() => Get.toNamed(AppRoute.cashMovements);
  void openSalesReturns() => Get.toNamed(AppRoute.salesReturns);
  void openSettings() => Get.toNamed(AppRoute.settings);
}
