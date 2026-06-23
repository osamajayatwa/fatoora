class InvoiceCustomerSnapshot {
  const InvoiceCustomerSnapshot({
    required this.id,
    required this.name,
    required this.phone,
    required this.address,
    required this.taxNumber,
    required this.nationalNumber,
    required this.city,
  });

  final String id;
  final String name;
  final String phone;
  final String address;
  final String taxNumber;
  final String nationalNumber;
  final String city;

  factory InvoiceCustomerSnapshot.fromMap(Object? value) {
    final data = _asMap(value);
    return InvoiceCustomerSnapshot(
      id: _readString(data, 'id'),
      name: _readString(data, 'name'),
      phone: _readString(data, 'phone'),
      address: _readString(data, 'address'),
      taxNumber: _readString(data, 'taxNumber'),
      nationalNumber: _readString(data, 'nationalNumber'),
      city: _readString(data, 'city'),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'phone': phone,
    'address': address,
    'taxNumber': taxNumber,
    'nationalNumber': nationalNumber,
    'city': city,
  };

  InvoiceCustomerSnapshot copyWith({
    String? id,
    String? name,
    String? phone,
    String? address,
    String? taxNumber,
    String? nationalNumber,
    String? city,
  }) {
    return InvoiceCustomerSnapshot(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      taxNumber: taxNumber ?? this.taxNumber,
      nationalNumber: nationalNumber ?? this.nationalNumber,
      city: city ?? this.city,
    );
  }

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is! Map) return const {};
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  static String _readString(Map<String, dynamic> data, String key) {
    final value = data[key];
    return value is String ? value.trim() : '';
  }
}
