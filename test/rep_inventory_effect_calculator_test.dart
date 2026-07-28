import 'package:fatoora/features/rep_inventory/data/models/rep_inventory_enums.dart';
import 'package:fatoora/features/rep_inventory/data/services/rep_inventory_effect_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('representative inventory effects', () {
    test('warehouse delivery preserves the combined physical quantity', () {
      final effect = RepInventoryEffectCalculator.transfer(
        type: InventoryTransferType.warehouseToRep,
        warehouseBefore: 20,
        repBefore: 3,
        quantity: 4.125,
      );

      expect(effect.warehouseAfter, 15.875);
      expect(effect.repAfter, 7.125);
      expect(effect.warehouseAfter + effect.repAfter, 23);
    });

    test('representative return restores warehouse custody', () {
      final effect = RepInventoryEffectCalculator.transfer(
        type: InventoryTransferType.repToWarehouse,
        warehouseBefore: 10,
        repBefore: 5,
        quantity: 2,
      );

      expect(effect.warehouseAfter, 12);
      expect(effect.repAfter, 3);
    });

    test('delivery rejects insufficient warehouse stock', () {
      expect(
        () => RepInventoryEffectCalculator.transfer(
          type: InventoryTransferType.warehouseToRep,
          warehouseBefore: 1,
          repBefore: 0,
          quantity: 2,
        ),
        throwsA(isA<RepInventoryInsufficientWarehouseStock>()),
      );
    });

    test('return and invoice reject insufficient representative stock', () {
      expect(
        () => RepInventoryEffectCalculator.transfer(
          type: InventoryTransferType.repToWarehouse,
          warehouseBefore: 4,
          repBefore: 1,
          quantity: 2,
        ),
        throwsA(isA<RepInventoryInsufficientRepStock>()),
      );
      expect(
        () =>
            RepInventoryEffectCalculator.invoiceSale(repBefore: 1, quantity: 2),
        throwsA(isA<RepInventoryInsufficientRepStock>()),
      );
    });

    test('invoice sale and sales return reverse each other', () {
      final afterSale = RepInventoryEffectCalculator.invoiceSale(
        repBefore: 8.333,
        quantity: 2.111,
      );
      final afterReturn = RepInventoryEffectCalculator.salesReturn(
        repBefore: afterSale,
        quantity: 2.111,
      );

      expect(afterSale, 6.222);
      expect(afterReturn, 8.333);
    });

    test('all effects use the project three-decimal precision', () {
      final effect = RepInventoryEffectCalculator.transfer(
        type: InventoryTransferType.warehouseToRep,
        warehouseBefore: 5,
        repBefore: 0,
        quantity: 1.23456,
      );

      expect(effect.warehouseAfter, 3.765);
      expect(effect.repAfter, 1.235);
    });

    test('zero, negative, and invalid balances are rejected', () {
      expect(
        () =>
            RepInventoryEffectCalculator.salesReturn(repBefore: 1, quantity: 0),
        throwsFormatException,
      );
      expect(
        () => RepInventoryEffectCalculator.invoiceSale(
          repBefore: -1,
          quantity: 1,
        ),
        throwsFormatException,
      );
    });
  });
}
