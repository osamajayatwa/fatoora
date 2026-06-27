class JofotaraStatusSettingsModel {
  const JofotaraStatusSettingsModel({
    required this.enabled,
    required this.status,
  });

  static const JofotaraStatusSettingsModel defaults =
      JofotaraStatusSettingsModel(enabled: false, status: 'disabled');

  final bool enabled;
  final String status;

  factory JofotaraStatusSettingsModel.fromMap(Map<String, dynamic>? data) {
    final map = data ?? const <String, dynamic>{};
    final rawStatus = map['status'];
    return JofotaraStatusSettingsModel(
      enabled: false,
      status: rawStatus is String && rawStatus.trim().isNotEmpty
          ? rawStatus.trim().toLowerCase()
          : defaults.status,
    );
  }

  Map<String, dynamic> toMap() => {'enabled': false, 'status': status.trim()};

  JofotaraStatusSettingsModel copyWith({bool? enabled, String? status}) {
    return JofotaraStatusSettingsModel(
      enabled: false,
      status: status ?? this.status,
    );
  }
}
