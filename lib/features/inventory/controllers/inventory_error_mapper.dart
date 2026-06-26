import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/features/inventory/data/repositories/inventory_repository.dart';

class InventoryErrorMapper {
  const InventoryErrorMapper._();

  static StatusRequest status(Object error) {
    if (error is! InventoryRepositoryException) {
      return StatusRequest.serverfailure;
    }
    return switch (error.error) {
      InventoryRepositoryError.unauthenticated ||
      InventoryRepositoryError.permissionDenied => StatusRequest.unauthorized,
      InventoryRepositoryError.unavailable => StatusRequest.offlinefailure,
      InventoryRepositoryError.timeout => StatusRequest.timeout,
      InventoryRepositoryError.notFound ||
      InventoryRepositoryError.insufficientStock => StatusRequest.failure,
      InventoryRepositoryError.invalidData ||
      InventoryRepositoryError.unknown => StatusRequest.serverfailure,
    };
  }

  static String messageKey(Object error, {String? fallback}) {
    if (error is! InventoryRepositoryException) {
      return fallback ?? 'inventory_action_error';
    }
    return switch (error.error) {
      InventoryRepositoryError.unauthenticated => 'inventory_session_error',
      InventoryRepositoryError.permissionDenied => 'inventory_permission_error',
      InventoryRepositoryError.unavailable => 'inventory_offline_error',
      InventoryRepositoryError.timeout => 'inventory_timeout_error',
      InventoryRepositoryError.notFound => 'inventory_item_not_found',
      InventoryRepositoryError.invalidData => 'inventory_invalid_data',
      InventoryRepositoryError.insufficientStock => 'stock_not_enough_simple',
      InventoryRepositoryError.unknown => fallback ?? 'inventory_action_error',
    };
  }
}
