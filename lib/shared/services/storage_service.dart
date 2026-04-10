import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Servicio de almacenamiento local
/// TODO: Implementar con shared_preferences o hive
class StorageService {
  // Singleton
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  // Almacenamiento en memoria (temporal - reemplazar con implementación real)
  final Map<String, String> _storage = {};

  /// Guarda un string
  Future<void> setString(String key, String value) async {
    _storage[key] = value;
    if (kDebugMode) {
      print('StorageService: Saved $key');
    }
  }

  /// Obtiene un string
  Future<String?> getString(String key) async {
    return _storage[key];
  }

  /// Guarda un mapa como JSON
  Future<void> setJson(String key, Map<String, dynamic> value) async {
    _storage[key] = jsonEncode(value);
  }

  /// Obtiene un mapa desde JSON
  Future<Map<String, dynamic>?> getJson(String key) async {
    final value = _storage[key];
    if (value == null) return null;
    return jsonDecode(value) as Map<String, dynamic>;
  }

  /// Guarda una lista como JSON
  Future<void> setList(String key, List<dynamic> value) async {
    _storage[key] = jsonEncode(value);
  }

  /// Obtiene una lista desde JSON
  Future<List<dynamic>?> getList(String key) async {
    final value = _storage[key];
    if (value == null) return null;
    return jsonDecode(value) as List<dynamic>;
  }

  /// Guarda un bool
  Future<void> setBool(String key, bool value) async {
    _storage[key] = value.toString();
  }

  /// Obtiene un bool
  Future<bool?> getBool(String key) async {
    final value = _storage[key];
    if (value == null) return null;
    return value == 'true';
  }

  /// Guarda un int
  Future<void> setInt(String key, int value) async {
    _storage[key] = value.toString();
  }

  /// Obtiene un int
  Future<int?> getInt(String key) async {
    final value = _storage[key];
    if (value == null) return null;
    return int.tryParse(value);
  }

  /// Guarda un double
  Future<void> setDouble(String key, double value) async {
    _storage[key] = value.toString();
  }

  /// Obtiene un double
  Future<double?> getDouble(String key) async {
    final value = _storage[key];
    if (value == null) return null;
    return double.tryParse(value);
  }

  /// Elimina un valor
  Future<void> remove(String key) async {
    _storage.remove(key);
  }

  /// Verifica si existe una clave
  Future<bool> containsKey(String key) async {
    return _storage.containsKey(key);
  }

  /// Limpia todo el almacenamiento
  Future<void> clear() async {
    _storage.clear();
  }

  /// Obtiene todas las claves
  Future<Set<String>> getKeys() async {
    return _storage.keys.toSet();
  }
}

/// Claves de almacenamiento
class StorageKeys {
  StorageKeys._();

  static const String authToken = 'auth_token';
  static const String userId = 'user_id';
  static const String userProfile = 'user_profile';
  static const String favorites = 'favorites';
  static const String recentSearches = 'recent_searches';
  static const String vehicleData = 'vehicle_data';
  static const String lastLocation = 'last_location';
  static const String settings = 'settings';
  static const String onboardingComplete = 'onboarding_complete';
  static const String cachedStations = 'cached_stations';
  static const String lastSync = 'last_sync';
}
