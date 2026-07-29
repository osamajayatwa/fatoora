import 'package:fatoora/features/customers/controllers/customer_error_mapper.dart';
import 'package:fatoora/features/customers/data/models/customer_opening_balance.dart';
import 'package:fatoora/features/customers/data/repositories/customer_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CustomerOpeningBalanceType', () {
    test('customer owes creates a positive three-decimal balance effect', () {
      expect(
        CustomerOpeningBalanceType.customerOwes.balanceEffect(1500.1234),
        1500.123,
      );
    });

    test('customer credit creates a negative three-decimal balance effect', () {
      expect(
        CustomerOpeningBalanceType.customerCredit.balanceEffect(75.5555),
        -75.556,
      );
    });
  });

  test('duplicate opening balance has a typed localized domain error', () {
    const error = OpeningBalanceAlreadyExistsException();

    expect(error, isA<CustomerRepositoryException>());
    expect(error.error, CustomerRepositoryError.openingBalanceExists);
    expect(
      CustomerErrorMapper.messageKey(error),
      'customers_opening_balance_exists',
    );
  });
}
