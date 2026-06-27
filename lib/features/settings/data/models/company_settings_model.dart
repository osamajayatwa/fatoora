class CompanySettingsModel {
  const CompanySettingsModel({
    required this.name,
    required this.country,
    required this.email,
    required this.website,
    required this.phone,
    required this.address,
    required this.logoEnabled,
  });

  static const CompanySettingsModel defaults = CompanySettingsModel(
    name: 'Jayatwa Trading Establishment',
    country: 'Jordan',
    email: 'jtrdest@gmail.com',
    website: 'www.fujikaindustries.com',
    phone: '',
    address: '',
    logoEnabled: true,
  );

  final String name;
  final String country;
  final String email;
  final String website;
  final String phone;
  final String address;
  final bool logoEnabled;

  factory CompanySettingsModel.fromMap(Map<String, dynamic>? data) {
    final map = data ?? const <String, dynamic>{};
    return CompanySettingsModel(
      name: _string(map['name'], defaults.name),
      country: _string(map['country'], defaults.country),
      email: _string(map['email'], defaults.email),
      website: _string(map['website'], defaults.website),
      phone: _string(map['phone'], defaults.phone),
      address: _string(map['address'], defaults.address),
      logoEnabled: _bool(map['logoEnabled'], defaults.logoEnabled),
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name.trim(),
    'country': country.trim(),
    'email': email.trim(),
    'website': website.trim(),
    'phone': phone.trim(),
    'address': address.trim(),
    'logoEnabled': logoEnabled,
  };

  CompanySettingsModel copyWith({
    String? name,
    String? country,
    String? email,
    String? website,
    String? phone,
    String? address,
    bool? logoEnabled,
  }) {
    return CompanySettingsModel(
      name: name ?? this.name,
      country: country ?? this.country,
      email: email ?? this.email,
      website: website ?? this.website,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      logoEnabled: logoEnabled ?? this.logoEnabled,
    );
  }

  static String _string(Object? value, String fallback) =>
      value is String ? value.trim() : fallback;

  static bool _bool(Object? value, bool fallback) =>
      value is bool ? value : fallback;
}
