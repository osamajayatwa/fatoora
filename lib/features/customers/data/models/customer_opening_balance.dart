enum CustomerOpeningBalanceType {
  customerOwes('customer_owes'),
  customerCredit('customer_credit');

  const CustomerOpeningBalanceType(this.value);

  final String value;

  static CustomerOpeningBalanceType? fromValue(String value) {
    for (final type in CustomerOpeningBalanceType.values) {
      if (type.value == value) return type;
    }
    return null;
  }

  double balanceEffect(double amount) {
    final rounded = (amount * 1000).roundToDouble() / 1000;
    return this == CustomerOpeningBalanceType.customerOwes ? rounded : -rounded;
  }
}
