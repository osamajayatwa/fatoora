import 'package:fatoora/features/inventory/data/models/stock_movement_model.dart';
import 'package:fatoora/features/items/data/models/item_model.dart';

class InventoryDashboardSnapshot {
  const InventoryDashboardSnapshot({
    required this.trackedItemCount,
    required this.totalStockQuantity,
    required this.lowStockCount,
    required this.outOfStockCount,
    required this.inventoryValue,
    required this.recentMovements,
    required this.lowStockItems,
  });

  const InventoryDashboardSnapshot.empty()
    : trackedItemCount = 0,
      totalStockQuantity = 0,
      lowStockCount = 0,
      outOfStockCount = 0,
      inventoryValue = 0,
      recentMovements = const [],
      lowStockItems = const [];

  final int trackedItemCount;
  final double totalStockQuantity;
  final int lowStockCount;
  final int outOfStockCount;
  final double inventoryValue;
  final List<StockMovementModel> recentMovements;
  final List<ItemModel> lowStockItems;
}
