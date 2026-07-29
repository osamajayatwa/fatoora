import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/settings/business_permission_resolver.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/financial/controllers/financial_error_mapper.dart';
import 'package:fatoora/features/financial/data/models/dashboard_month_period.dart';
import 'package:fatoora/features/financial/data/models/financial_dashboard_snapshot.dart';
import 'package:fatoora/features/financial/data/repositories/financial_repository.dart';
import 'package:fatoora/features/invoices/data/models/invoice_enums.dart';
import 'package:flutter/material.dart';
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
  DashboardMonthPeriod selectedPeriod = DashboardMonthPeriod.current();
  bool _followCurrentMonth = true;
  bool get canCreateQuotation => permissions.createQuotations;
  bool get canCreateReceipt => permissions.createReceipts;

  String get companyId =>
      _myServices.sharedPreferences.getString('companyId') ??
      AuthRepository.defaultCompanyId;

  @override
  void onReady() {
    super.onReady();
    loadDashboard();
  }

  Future<void> loadDashboard() async {
    _syncCurrentMonth();
    statusRequest = StatusRequest.loading;
    update();
    try {
      permissions = await _permissionResolver.resolve(companyId);
      snapshot = await _repository.fetchDashboard(
        companyId: companyId,
        fromDate: selectedPeriod.start,
        toDate: selectedPeriod.end,
      );
      statusRequest = StatusRequest.success;
    } catch (error) {
      statusRequest = FinancialErrorMapper.status(error);
      loadErrorMessageKey = FinancialErrorMapper.messageKey(error);
    }
    if (!isClosed) update();
  }

  Future<void> refreshDashboard() => loadDashboard();

  String selectedMonthLabel(BuildContext context) {
    return MaterialLocalizations.of(
      context,
    ).formatMonthYear(selectedPeriod.month);
  }

  Future<void> selectMonth(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedPeriod.month.isAfter(now)
          ? DateTime(now.year, now.month)
          : selectedPeriod.month,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'financial_select_month'.tr,
    );
    if (picked == null) return;
    selectedPeriod = DashboardMonthPeriod.fromMonth(picked);
    _followCurrentMonth = selectedPeriod.isSameMonth(now);
    await loadDashboard();
  }

  void _syncCurrentMonth() {
    if (!_followCurrentMonth) return;
    selectedPeriod = DashboardMonthPeriod.current();
  }

  void createInvoice() {
    Get.toNamed(
      AppRoute.invoiceForm,
      arguments: {'mode': 'create', 'invoiceType': InvoiceType.regular.value},
    );
  }

  void openInvoices() => Get.toNamed(AppRoute.invoices);
  void openReceipts() => Get.toNamed(AppRoute.receipts);
  void createReceipt() {
    if (!canCreateReceipt) {
      Get.snackbar(
        'permission_denied'.tr,
        'sales_rep_receipt_create_disabled'.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppColor.error,
        colorText: AppColor.surface,
      );
      return;
    }
    Get.toNamed(AppRoute.createReceipt);
  }

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
  void createCustomer() => Get.toNamed(AppRoute.createCustomer);
  void openStatements() => Get.toNamed(AppRoute.statements);
  void openReceivables() => Get.toNamed(AppRoute.receivables);
  void openCash() => Get.toNamed(AppRoute.cashMovements);
  void openExpenses() => Get.toNamed(AppRoute.expenses);
  void createExpense() => Get.toNamed(AppRoute.createExpense);
  void openSalesReturns() => Get.toNamed(AppRoute.salesReturns);
  void openMyInventory() => Get.toNamed(AppRoute.repInventory);
  void openSettings() => Get.toNamed(AppRoute.settings);
}
