import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/features/items/data/repositories/item_repository.dart';

class ItemErrorMapper {
  const ItemErrorMapper._();

  static StatusRequest status(Object error) {
    if (error is! ItemRepositoryException) {
      return StatusRequest.serverfailure;
    }
    return switch (error.error) {
      ItemRepositoryError.unauthenticated ||
      ItemRepositoryError.permissionDenied => StatusRequest.unauthorized,
      ItemRepositoryError.unavailable => StatusRequest.offlinefailure,
      ItemRepositoryError.timeout => StatusRequest.timeout,
      ItemRepositoryError.notFound => StatusRequest.failure,
      ItemRepositoryError.invalidData ||
      ItemRepositoryError.unknown => StatusRequest.serverfailure,
    };
  }

  static String messageKey(Object error, {String? fallback}) {
    if (error is! ItemRepositoryException) {
      return fallback ?? 'items_action_error';
    }
    return switch (error.error) {
      ItemRepositoryError.unauthenticated => 'items_session_error',
      ItemRepositoryError.permissionDenied => 'items_permission_error',
      ItemRepositoryError.unavailable => 'items_offline_error',
      ItemRepositoryError.timeout => 'items_timeout_error',
      ItemRepositoryError.notFound => 'items_not_found_error',
      ItemRepositoryError.invalidData => 'items_invalid_data_error',
      ItemRepositoryError.unknown => fallback ?? 'items_action_error',
    };
  }
}
