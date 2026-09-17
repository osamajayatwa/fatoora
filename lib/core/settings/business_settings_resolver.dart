import 'package:fatoora/features/settings/data/models/app_settings_model.dart';
import 'package:fatoora/features/settings/data/models/user_preferences_model.dart';
import 'package:fatoora/features/settings/data/repositories/settings_repository.dart';

class BusinessSettingsResolver {
  BusinessSettingsResolver({
    required SettingsRepository repository,
    Duration cacheTtl = const Duration(minutes: 2),
  }) : _appSettingsLoader = repository.getAppSettings,
       _userPreferencesLoader = repository.getUserPreferences,
       _cacheOwner = repository,
       _cacheTtl = cacheTtl;

  BusinessSettingsResolver.withLoaders({
    required Future<AppSettingsModel> Function(String companyId)
    appSettingsLoader,
    required Future<UserPreferencesModel> Function(String uid)
    userPreferencesLoader,
    Duration cacheTtl = const Duration(minutes: 2),
  }) : _appSettingsLoader = appSettingsLoader,
       _userPreferencesLoader = userPreferencesLoader,
       _cacheOwner = appSettingsLoader,
       _cacheTtl = cacheTtl;

  final Future<AppSettingsModel> Function(String companyId) _appSettingsLoader;
  final Future<UserPreferencesModel> Function(String uid)
  _userPreferencesLoader;
  final Object _cacheOwner;
  final Duration _cacheTtl;
  static final Map<_SettingsCacheKey, _CachedAppSettings> _appSettingsCache =
      {};
  static final Map<_SettingsCacheKey, Future<AppSettingsModel>>
  _appSettingsInFlight = {};
  static final Map<_SettingsCacheKey, _CachedUserPreferences>
  _preferencesCache = {};
  static final Map<_SettingsCacheKey, Future<UserPreferencesModel>>
  _preferencesInFlight = {};

  static void invalidateAppSettings([String? companyId]) {
    if (companyId == null) {
      _appSettingsCache.clear();
      _appSettingsInFlight.clear();
      return;
    }
    _appSettingsCache.removeWhere((key, _) => key.id == companyId);
    _appSettingsInFlight.removeWhere((key, _) => key.id == companyId);
  }

  static void invalidateUserPreferences([String? uid]) {
    if (uid == null) {
      _preferencesCache.clear();
      _preferencesInFlight.clear();
      return;
    }
    _preferencesCache.removeWhere((key, _) => key.id == uid);
    _preferencesInFlight.removeWhere((key, _) => key.id == uid);
  }

  Future<AppSettingsModel> loadAppSettings(String companyId) async {
    final companyKey = companyId.trim();
    final key = _SettingsCacheKey(_cacheOwner, companyKey);
    final cached = _appSettingsCache[key];
    if (cached != null &&
        DateTime.now().difference(cached.loadedAt) < _cacheTtl) {
      return cached.settings;
    }
    final pending = _appSettingsInFlight[key];
    if (pending != null) return pending;
    final load = _loadAppSettings(companyKey);
    _appSettingsInFlight[key] = load;
    try {
      final settings = await load;
      _appSettingsCache[key] = _CachedAppSettings(settings, DateTime.now());
      return settings;
    } finally {
      _appSettingsInFlight.remove(key);
    }
  }

  Future<UserPreferencesModel> loadUserPreferences(String uid) async {
    final userKey = uid.trim();
    if (userKey.isEmpty) return UserPreferencesModel.defaults;
    final key = _SettingsCacheKey(_cacheOwner, userKey);
    final cached = _preferencesCache[key];
    if (cached != null &&
        DateTime.now().difference(cached.loadedAt) < _cacheTtl) {
      return cached.preferences;
    }
    final pending = _preferencesInFlight[key];
    if (pending != null) return pending;
    final load = _loadUserPreferences(userKey);
    _preferencesInFlight[key] = load;
    try {
      final preferences = await load;
      _preferencesCache[key] = _CachedUserPreferences(
        preferences,
        DateTime.now(),
      );
      return preferences;
    } finally {
      _preferencesInFlight.remove(key);
    }
  }

  Future<AppSettingsModel> _loadAppSettings(String companyId) async {
    try {
      return await _appSettingsLoader(
        companyId,
      ).timeout(const Duration(seconds: 5));
    } catch (_) {
      return AppSettingsModel.defaults;
    }
  }

  Future<UserPreferencesModel> _loadUserPreferences(String uid) async {
    try {
      return await _userPreferencesLoader(
        uid,
      ).timeout(const Duration(seconds: 5));
    } catch (_) {
      return UserPreferencesModel.defaults;
    }
  }
}

class _SettingsCacheKey {
  const _SettingsCacheKey(this.owner, this.id);

  final Object owner;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is _SettingsCacheKey &&
      identical(other.owner, owner) &&
      other.id == id;

  @override
  int get hashCode => Object.hash(identityHashCode(owner), id);
}

class _CachedAppSettings {
  const _CachedAppSettings(this.settings, this.loadedAt);

  final AppSettingsModel settings;
  final DateTime loadedAt;
}

class _CachedUserPreferences {
  const _CachedUserPreferences(this.preferences, this.loadedAt);

  final UserPreferencesModel preferences;
  final DateTime loadedAt;
}
