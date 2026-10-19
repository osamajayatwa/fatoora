import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/features/receipts/data/repositories/receipt_repository.dart';

class ReceiptErrorMapper {
  const ReceiptErrorMapper._();

  static StatusRequest status(Object error) {
    if (error is ReceiptRepositoryException) {
      return switch (error.error) {
        ReceiptRepositoryError.unauthenticated => StatusRequest.unauthorized,
        ReceiptRepositoryError.permissionDenied => StatusRequest.unauthorized,
        ReceiptRepositoryError.createDisabled => StatusRequest.unauthorized,
        ReceiptRepositoryError.unavailable => StatusRequest.offlinefailure,
        ReceiptRepositoryError.timeout => StatusRequest.timeout,
        ReceiptRepositoryError.notFound => StatusRequest.failure,
        ReceiptRepositoryError.invalidData => StatusRequest.failure,
        ReceiptRepositoryError.unknown => StatusRequest.serverfailure,
      };
    }
    return StatusRequest.serverfailure;
  }

  static String messageKey(Object error, {String fallback = 'receipts_error'}) {
    if (error is ReceiptRepositoryException) {
      final cause = error.cause;
      if (cause is FirebaseFunctionsException &&
          cause.details is Map &&
          (cause.details as Map)['reason'] == 'receipt-cancellation-unsafe') {
        return switch ((cause.details as Map)['dependency']) {
          'allocated invoice has sales returns' =>
            'receipts_cancel_blocked_returns',
          'cash has subsequent spending or settlements' ||
          'cash account requires reconciliation' ||
          'original cash account has insufficient funds' ||
          'collection account has dependent outflows' =>
            'receipts_cancel_blocked_cash',
          'customer credit has subsequent transactions' ||
          'customer credit has changed' => 'receipts_cancel_blocked_credit',
          _ => 'receipts_cancel_blocked_history',
        };
      }
      if (cause is FirebaseException && cause.code == 'failed-precondition') {
        return 'receipts_server_validation_error';
      }
      return switch (error.error) {
        ReceiptRepositoryError.unauthenticated => 'receipts_session_error',
        ReceiptRepositoryError.permissionDenied => 'receipts_permission_error',
        ReceiptRepositoryError.createDisabled =>
          'sales_rep_receipt_create_disabled',
        ReceiptRepositoryError.unavailable => 'receipts_offline_error',
        ReceiptRepositoryError.timeout => 'receipts_timeout_error',
        ReceiptRepositoryError.notFound => 'receipts_not_found',
        ReceiptRepositoryError.invalidData => 'receipts_invalid_data',
        ReceiptRepositoryError.unknown => fallback,
      };
    }
    return fallback;
  }
}
