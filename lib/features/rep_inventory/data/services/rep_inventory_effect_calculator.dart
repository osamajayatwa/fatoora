import 'package:fatoora/features/rep_inventory/data/models/rep_inventory_enums.dart';

class RepInventoryEffect {
  const RepInventoryEffect({
    required this.warehouseAfter,
    required this.repAfter,
  });

  final double warehouseAfter;
  final double repAfter;
}

class RepInventoryEffectCalculator {
  const RepInventoryEffectCalculator._();

  static RepInventoryEffect transfer({
    required InventoryTransferType type,
    required double warehouseBefore,
    required double repBefore,
    required double quantity,
  }) {
    _validateBalance(warehouseBefore);
    _validateBalance(repBefore);
    final roundedQuantity = _round(quantity);
    if (roundedQuantity <= 0) {
      throw const FormatException('Quantity must be positive.');
    }
    if (type == InventoryTransferType.warehouseToRep) {
      if (warehouseBefore + 0.0005 < roundedQuantity) {
        throw const RepInventoryInsufficientWarehouseStock();
      }
      return RepInventoryEffect(
        warehouseAfter: _round(warehouseBefore - roundedQuantity),
        repAfter: _round(repBefore + roundedQuantity),
      );
    }
    if (repBefore + 0.0005 < roundedQuantity) {
      throw const RepInventoryInsufficientRepStock();
    }
    return RepInventoryEffect(
      warehouseAfter: _round(warehouseBefore + roundedQuantity),
      repAfter: _round(repBefore - roundedQuantity),
    );
  }

  static double invoiceSale({
    required double repBefore,
    required double quantity,
  }) {
    _validateBalance(repBefore);
    final roundedQuantity = _round(quantity);
    if (roundedQuantity <= 0 || repBefore + 0.0005 < roundedQuantity) {
      throw const RepInventoryInsufficientRepStock();
    }
    return _round(repBefore - roundedQuantity);
  }

  static double salesReturn({
    required double repBefore,
    required double quantity,
  }) {
    _validateBalance(repBefore);
    final roundedQuantity = _round(quantity);
    if (roundedQuantity <= 0) {
      throw const FormatException('Quantity must be positive.');
    }
    return _round(repBefore + roundedQuantity);
  }

  static void _validateBalance(double value) {
    if (!value.isFinite || value < 0) {
      throw const FormatException('Inventory balance is invalid.');
    }
  }

  static double _round(double value) => (value * 1000).roundToDouble() / 1000;
}

class RepInventoryInsufficientWarehouseStock implements Exception {
  const RepInventoryInsufficientWarehouseStock();
}

class RepInventoryInsufficientRepStock implements Exception {
  const RepInventoryInsufficientRepStock();
}
