import 'package:fatoora/core/class/statusrequest.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fatoora/features/customers/data/repositories/customer_repository.dart';

class CustomerErrorMapper {
  const CustomerErrorMapper._();

  static StatusRequest status(Object error) {
    if (error is! CustomerRepositoryException) {
      return StatusRequest.serverfailure;
    }
    return switch (error.error) {
      CustomerRepositoryError.unauthenticated ||
      CustomerRepositoryError.profileMissing ||
      CustomerRepositoryError.permissionDenied ||
      CustomerRepositoryError.createDisabled => StatusRequest.unauthorized,
      CustomerRepositoryError.unavailable => StatusRequest.offlinefailure,
      CustomerRepositoryError.timeout => StatusRequest.timeout,
      CustomerRepositoryError.notFound ||
      CustomerRepositoryError.duplicatePhone ||
      CustomerRepositoryError.openingBalanceExists ||
      CustomerRepositoryError.inactiveCustomer => StatusRequest.failure,
      CustomerRepositoryError.invalidData ||
      CustomerRepositoryError.unknown => StatusRequest.serverfailure,
    };
  }

  static String messageKey(Object error, {String? fallback}) {
    if (error is! CustomerRepositoryException) {
      return fallback ?? 'customers_action_error';
    }
    final cause = error.cause;
    if (cause is FirebaseFunctionsException &&
        cause.details is Map &&
        (cause.details as Map)['reason'] == 'customer-assignment-review') {
      return 'customers_assignment_review';
    }
    if (cause is FirebaseFunctionsException &&
        cause.details is Map &&
        (cause.details as Map)['reason'] == 'customer-assignment-stale') {
      return 'customers_assignment_stale';
    }
    return switch (error.error) {
      CustomerRepositoryError.unauthenticated => 'customers_session_error',
      CustomerRepositoryError.profileMissing => 'customers_profile_missing',
      CustomerRepositoryError.permissionDenied => 'customers_permission_error',
      CustomerRepositoryError.createDisabled =>
        'sales_rep_customer_create_disabled',
      CustomerRepositoryError.unavailable => 'customers_offline_error',
      CustomerRepositoryError.timeout => 'customers_timeout_error',
      CustomerRepositoryError.notFound => 'customers_not_found',
      CustomerRepositoryError.duplicatePhone => 'customers_duplicate_phone',
      CustomerRepositoryError.openingBalanceExists =>
        'customers_opening_balance_exists',
      CustomerRepositoryError.inactiveCustomer =>
        'customers_opening_balance_inactive',
      CustomerRepositoryError.invalidData => 'customers_invalid_data',
      CustomerRepositoryError.unknown => fallback ?? 'customers_action_error',
    };
  }
}
