import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/features/invoices/data/repositories/invoice_repository.dart';

class InvoiceErrorMapper {
  const InvoiceErrorMapper._();

  static StatusRequest status(Object error) {
    if (error is! InvoiceRepositoryException) {
      return StatusRequest.serverfailure;
    }
    return switch (error.error) {
      InvoiceRepositoryError.unauthenticated ||
      InvoiceRepositoryError.permissionDenied => StatusRequest.unauthorized,
      InvoiceRepositoryError.unavailable => StatusRequest.offlinefailure,
      InvoiceRepositoryError.timeout => StatusRequest.timeout,
      InvoiceRepositoryError.notFound ||
      InvoiceRepositoryError.invalidState ||
      InvoiceRepositoryError.locked => StatusRequest.failure,
      InvoiceRepositoryError.invalidData ||
      InvoiceRepositoryError.unknown => StatusRequest.serverfailure,
    };
  }

  static String messageKey(Object error, {String? fallback}) {
    if (error is! InvoiceRepositoryException) {
      return fallback ?? 'invoice_action_error';
    }
    return switch (error.error) {
      InvoiceRepositoryError.unauthenticated => 'invoice_session_error',
      InvoiceRepositoryError.permissionDenied => 'invoice_permission_error',
      InvoiceRepositoryError.unavailable => 'invoice_offline_error',
      InvoiceRepositoryError.timeout => 'invoice_timeout_error',
      InvoiceRepositoryError.notFound => 'invoice_not_found',
      InvoiceRepositoryError.invalidData => 'invoice_invalid_data',
      InvoiceRepositoryError.invalidState => 'invoice_invalid_state',
      InvoiceRepositoryError.locked => 'accepted_invoice_cannot_be_edited',
      InvoiceRepositoryError.unknown => fallback ?? 'invoice_action_error',
    };
  }
}
