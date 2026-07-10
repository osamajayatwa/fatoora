import 'package:fatoora/app/routes/app_routes.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/services/services.dart';
import 'package:fatoora/features/auth/data/repositories/auth_repository.dart';
import 'package:fatoora/features/expenses/controllers/expense_error_mapper.dart';
import 'package:fatoora/features/expenses/data/models/expense_model.dart';
import 'package:fatoora/features/expenses/data/repositories/expense_repository.dart';
import 'package:get/get.dart';

class ExpenseDetailsController extends GetxController {
  ExpenseDetailsController({
    required ExpenseRepository repository,
    required MyServices myServices,
  }) : _repository = repository,
       _myServices = myServices;

  final ExpenseRepository _repository;
  final MyServices _myServices;

  StatusRequest statusRequest = StatusRequest.loading;
  String loadErrorMessageKey = 'expenses_load_error';
  ExpenseModel? expense;
  bool isSavingDecision = false;

  String get companyId {
    final args = Get.arguments;
    if (args is Map && args['companyId'] is String) {
      final value = (args['companyId'] as String).trim();
      if (value.isNotEmpty) return value;
    }
    return _myServices.sharedPreferences.getString('companyId') ??
        AuthRepository.defaultCompanyId;
  }

  String get expenseId {
    final args = Get.arguments;
    if (args is Map && args['expenseId'] is String) {
      return (args['expenseId'] as String).trim();
    }
    return '';
  }

  bool get isAdmin =>
      _myServices.sharedPreferences.getString('role') ==
      AuthRepository.adminRole;

  bool get canDecide => isAdmin && (expense?.isPending ?? false);

  @override
  void onReady() {
    super.onReady();
    loadExpense();
  }

  Future<void> loadExpense() async {
    if (expenseId.isEmpty) {
      statusRequest = StatusRequest.failure;
      loadErrorMessageKey = 'expense_not_found';
      update();
      return;
    }
    statusRequest = StatusRequest.loading;
    loadErrorMessageKey = 'expenses_load_error';
    update();
    try {
      expense = await _repository.fetchExpenseById(
        companyId: companyId,
        expenseId: expenseId,
      );
      statusRequest = StatusRequest.success;
    } catch (error) {
      statusRequest = ExpenseErrorMapper.status(error);
      loadErrorMessageKey = ExpenseErrorMapper.messageKey(
        error,
        fallback: 'expenses_load_error',
      );
    }
    if (!isClosed) update();
  }

  Future<void> approveExpense() async {
    if (!canDecide || isSavingDecision) return;
    isSavingDecision = true;
    update();
    try {
      await _repository.approveExpense(
        companyId: companyId,
        expenseId: expenseId,
      );
      Get.snackbar(
        'expenses'.tr,
        'expense_approved_successfully'.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppColor.success,
        colorText: AppColor.surface,
      );
      await loadExpense();
    } catch (error) {
      _showError(ExpenseErrorMapper.messageKey(error));
    } finally {
      isSavingDecision = false;
      if (!isClosed) update();
    }
  }

  Future<void> rejectExpense(String reason) async {
    if (!canDecide || isSavingDecision) return;
    if (reason.trim().isEmpty) {
      _showError('expense_rejection_reason_required');
      return;
    }
    isSavingDecision = true;
    update();
    try {
      await _repository.rejectExpense(
        companyId: companyId,
        expenseId: expenseId,
        reason: reason,
      );
      Get.snackbar(
        'expenses'.tr,
        'expense_rejected_successfully'.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppColor.success,
        colorText: AppColor.surface,
      );
      await loadExpense();
    } catch (error) {
      _showError(ExpenseErrorMapper.messageKey(error));
    } finally {
      isSavingDecision = false;
      if (!isClosed) update();
    }
  }

  Future<void> goToExpenses() async {
    await Get.offNamed(AppRoute.expenses);
  }

  void _showError(String messageKey) {
    Get.snackbar(
      'expenses'.tr,
      messageKey.tr,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: AppColor.error,
      colorText: AppColor.surface,
    );
  }
}
