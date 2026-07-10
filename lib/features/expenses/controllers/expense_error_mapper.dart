import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/features/expenses/data/repositories/expense_repository.dart';

class ExpenseErrorMapper {
  const ExpenseErrorMapper._();

  static StatusRequest status(Object error) {
    if (error is ExpenseRepositoryException) {
      return switch (error.error) {
        ExpenseRepositoryError.unauthenticated ||
        ExpenseRepositoryError.permissionDenied => StatusRequest.failure,
        ExpenseRepositoryError.unavailable ||
        ExpenseRepositoryError.timeout => StatusRequest.offlinefailure,
        ExpenseRepositoryError.notFound ||
        ExpenseRepositoryError.invalidData ||
        ExpenseRepositoryError.invalidState ||
        ExpenseRepositoryError.unknown => StatusRequest.failure,
      };
    }
    return StatusRequest.failure;
  }

  static String messageKey(Object error, {String fallback = 'expenses_error'}) {
    if (error is ExpenseRepositoryException) {
      return switch (error.error) {
        ExpenseRepositoryError.unauthenticated => 'financial_session_error',
        ExpenseRepositoryError.permissionDenied => 'financial_permission_error',
        ExpenseRepositoryError.unavailable => 'financial_offline_error',
        ExpenseRepositoryError.timeout => 'financial_timeout_error',
        ExpenseRepositoryError.notFound => 'expense_not_found',
        ExpenseRepositoryError.invalidData => 'expense_invalid_data',
        ExpenseRepositoryError.invalidState => 'expense_invalid_state',
        ExpenseRepositoryError.unknown => fallback,
      };
    }
    return fallback;
  }
}
