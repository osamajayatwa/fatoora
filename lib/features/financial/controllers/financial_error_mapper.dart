import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/features/financial/data/repositories/financial_repository.dart';

class FinancialErrorMapper {
  const FinancialErrorMapper._();

  static StatusRequest status(Object error) {
    if (error is! FinancialRepositoryException) {
      return StatusRequest.serverfailure;
    }
    return switch (error.error) {
      FinancialRepositoryError.unauthenticated ||
      FinancialRepositoryError.permissionDenied => StatusRequest.unauthorized,
      FinancialRepositoryError.unavailable => StatusRequest.offlinefailure,
      FinancialRepositoryError.timeout => StatusRequest.timeout,
      FinancialRepositoryError.alreadyExists ||
      FinancialRepositoryError.invalidData ||
      FinancialRepositoryError.unknown => StatusRequest.serverfailure,
    };
  }

  static String messageKey(Object error, {String? fallback}) {
    if (error is! FinancialRepositoryException) {
      return fallback ?? 'financial_load_error';
    }
    return switch (error.error) {
      FinancialRepositoryError.unauthenticated => 'financial_session_error',
      FinancialRepositoryError.permissionDenied => 'financial_permission_error',
      FinancialRepositoryError.unavailable => 'financial_offline_error',
      FinancialRepositoryError.timeout => 'financial_timeout_error',
      FinancialRepositoryError.alreadyExists =>
        'financial_company_cash_opening_balance_exists',
      FinancialRepositoryError.invalidData => 'financial_invalid_data',
      FinancialRepositoryError.unknown => fallback ?? 'financial_load_error',
    };
  }
}
