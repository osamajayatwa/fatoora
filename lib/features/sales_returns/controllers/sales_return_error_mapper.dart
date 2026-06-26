import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/features/sales_returns/data/repositories/sales_return_repository.dart';

class SalesReturnErrorMapper {
  const SalesReturnErrorMapper._();

  static StatusRequest status(Object error) {
    if (error is! SalesReturnRepositoryException) {
      return StatusRequest.serverfailure;
    }
    return switch (error.error) {
      SalesReturnRepositoryError.unauthenticated ||
      SalesReturnRepositoryError.permissionDenied => StatusRequest.unauthorized,
      SalesReturnRepositoryError.unavailable => StatusRequest.offlinefailure,
      SalesReturnRepositoryError.timeout => StatusRequest.timeout,
      SalesReturnRepositoryError.notFound ||
      SalesReturnRepositoryError.invalidState ||
      SalesReturnRepositoryError.quantityExceeded ||
      SalesReturnRepositoryError.alreadyPosted => StatusRequest.failure,
      SalesReturnRepositoryError.invalidData ||
      SalesReturnRepositoryError.unknown => StatusRequest.serverfailure,
    };
  }

  static String messageKey(
    Object error, {
    String fallback = 'sales_return_action_error',
  }) {
    if (error is! SalesReturnRepositoryException) return fallback;
    return switch (error.error) {
      SalesReturnRepositoryError.unauthenticated =>
        'sales_return_session_error',
      SalesReturnRepositoryError.permissionDenied =>
        'sales_return_permission_error',
      SalesReturnRepositoryError.unavailable => 'sales_return_offline_error',
      SalesReturnRepositoryError.timeout => 'sales_return_timeout_error',
      SalesReturnRepositoryError.notFound => 'sales_return_not_found',
      SalesReturnRepositoryError.invalidData => 'sales_return_invalid_data',
      SalesReturnRepositoryError.invalidState => 'sales_return_invalid_state',
      SalesReturnRepositoryError.quantityExceeded =>
        'cannot_return_more_than_sold',
      SalesReturnRepositoryError.alreadyPosted => 'sales_return_already_posted',
      SalesReturnRepositoryError.unknown => fallback,
    };
  }

  static SalesReturnQuantityFailure? quantityFailure(Object error) {
    if (error is! SalesReturnRepositoryException) return null;
    final cause = error.cause;
    return cause is SalesReturnQuantityFailure ? cause : null;
  }
}
