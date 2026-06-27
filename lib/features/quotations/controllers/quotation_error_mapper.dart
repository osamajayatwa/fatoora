import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/features/quotations/data/repositories/quotation_repository.dart';

class QuotationErrorMapper {
  const QuotationErrorMapper._();

  static StatusRequest status(Object error) {
    final repositoryError = _read(error);
    return switch (repositoryError) {
      QuotationRepositoryError.unauthenticated => StatusRequest.unauthorized,
      QuotationRepositoryError.permissionDenied => StatusRequest.unauthorized,
      QuotationRepositoryError.unavailable => StatusRequest.offlinefailure,
      QuotationRepositoryError.timeout => StatusRequest.serverfailure,
      QuotationRepositoryError.notFound => StatusRequest.failure,
      QuotationRepositoryError.invalidData => StatusRequest.failure,
      QuotationRepositoryError.invalidState => StatusRequest.failure,
      QuotationRepositoryError.locked => StatusRequest.failure,
      QuotationRepositoryError.unknown => StatusRequest.serverfailure,
    };
  }

  static String messageKey(
    Object error, {
    String fallback = 'quotation_error',
  }) {
    final repositoryError = _read(error);
    return switch (repositoryError) {
      QuotationRepositoryError.unauthenticated => 'quotation_session_error',
      QuotationRepositoryError.permissionDenied => 'quotation_permission_error',
      QuotationRepositoryError.unavailable => 'quotation_offline_error',
      QuotationRepositoryError.timeout => 'quotation_timeout_error',
      QuotationRepositoryError.notFound => 'quotation_not_found',
      QuotationRepositoryError.invalidData => 'quotation_invalid_data',
      QuotationRepositoryError.invalidState => 'quotation_invalid_state',
      QuotationRepositoryError.locked => 'quotation_locked',
      QuotationRepositoryError.unknown => fallback,
    };
  }

  static QuotationRepositoryError _read(Object error) {
    if (error is QuotationRepositoryException) return error.error;
    return QuotationRepositoryError.unknown;
  }
}
