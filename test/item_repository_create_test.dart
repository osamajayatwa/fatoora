import 'package:fatoora/features/items/data/repositories/item_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('new item inventory normalization', () {
    test('opening stock is the initial current stock', () {
      final values = normalizeNewItemInventory(
        trackStock: true,
        openingStock: 7.1254,
        minStock: 2.5,
      );

      expect(values.currentStock, 7.125);
      expect(values.openingStock, 7.125);
      expect(values.minStock, 2.5);
    });

    test('non-stock item cannot retain hidden inventory values', () {
      final values = normalizeNewItemInventory(
        trackStock: false,
        openingStock: 9,
        minStock: 3,
      );

      expect(values.currentStock, 0);
      expect(values.openingStock, 0);
      expect(values.minStock, 0);
    });

    test('invalid inventory values remain rejected', () {
      expect(
        () => normalizeNewItemInventory(
          trackStock: true,
          openingStock: -1,
          minStock: 0,
        ),
        throwsA(
          isA<ItemRepositoryException>().having(
            (error) => error.error,
            'error',
            ItemRepositoryError.invalidData,
          ),
        ),
      );
    });
  });

  test('repository exception includes its safe diagnostic category', () {
    const error = ItemRepositoryException(ItemRepositoryError.permissionDenied);

    expect(error.toString(), contains('permissionDenied'));
  });
}
