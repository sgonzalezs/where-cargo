import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/charging_stations/domain/models/charging_station.dart';
import '../../features/favorites/domain/models/favorite_station.dart';

/// Servicio singleton para gestionar estaciones favoritas
/// Persiste los datos localmente usando SharedPreferences
class FavoritesService extends ChangeNotifier {
  // Singleton
  static final FavoritesService _instance = FavoritesService._internal();
  factory FavoritesService() => _instance;
  FavoritesService._internal();

  // Claves para SharedPreferences
  static const String _favoritesKey = 'favorites_data';

  // Cache en memoria
  List<FavoriteStation> _favorites = [];
  bool _isLoaded = false;
  bool _isLoading = false;

  /// Lista de favoritos actual
  List<FavoriteStation> get favorites => List.unmodifiable(_favorites);

  /// Obtiene los IDs de las estaciones favoritas
  Set<String> get favoriteIds => _favorites.map((f) => f.stationId).toSet();

  /// Verifica si una estación está en favoritos
  bool isFavorite(String stationId) => favoriteIds.contains(stationId);

  /// Indica si está cargando
  bool get isLoading => _isLoading;

  /// Indica si ya se cargaron los datos
  bool get isLoaded => _isLoaded;

  /// Cantidad de favoritos
  int get count => _favorites.length;

  /// Carga los favoritos desde almacenamiento local
  Future<void> loadFavorites() async {
    if (_isLoaded || _isLoading) return;

    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_favoritesKey);

      if (jsonString != null && jsonString.isNotEmpty) {
        final List<dynamic> jsonList = json.decode(jsonString);
        _favorites = jsonList
            .map((item) => FavoriteStation.fromJson(item as Map<String, dynamic>))
            .toList();
      }

      _isLoaded = true;
    } catch (e) {
      debugPrint('Error loading favorites: $e');
      _favorites = [];
      _isLoaded = true;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Agrega una estación a favoritos
  Future<bool> addFavorite(ChargingStation station, {String? notes}) async {
    // Verificar si ya existe
    if (isFavorite(station.id)) {
      return false;
    }

    final favorite = FavoriteStation(
      id: 'fav_${station.id}_${DateTime.now().millisecondsSinceEpoch}',
      stationId: station.id,
      addedAt: DateTime.now(),
      notes: notes,
      station: station,
    );

    _favorites.insert(0, favorite); // Agregar al inicio
    notifyListeners();

    await _saveFavorites();
    return true;
  }

  /// Elimina una estación de favoritos por ID de estación
  Future<bool> removeFavorite(String stationId) async {
    final index = _favorites.indexWhere((f) => f.stationId == stationId);
    if (index == -1) return false;

    _favorites.removeAt(index);
    notifyListeners();

    await _saveFavorites();
    return true;
  }

  /// Elimina un favorito específico
  Future<bool> removeFavoriteById(String favoriteId) async {
    final index = _favorites.indexWhere((f) => f.id == favoriteId);
    if (index == -1) return false;

    _favorites.removeAt(index);
    notifyListeners();

    await _saveFavorites();
    return true;
  }

  /// Alterna el estado de favorito de una estación
  Future<bool> toggleFavorite(ChargingStation station) async {
    if (isFavorite(station.id)) {
      await removeFavorite(station.id);
      return false; // Ya no es favorito
    } else {
      await addFavorite(station);
      return true; // Ahora es favorito
    }
  }

  /// Actualiza las notas de un favorito
  Future<void> updateNotes(String stationId, String? notes) async {
    final index = _favorites.indexWhere((f) => f.stationId == stationId);
    if (index == -1) return;

    _favorites[index] = _favorites[index].copyWith(notes: notes);
    notifyListeners();

    await _saveFavorites();
  }

  /// Actualiza los datos de una estación en favoritos
  /// Útil cuando se obtienen datos frescos del API
  void updateStationData(ChargingStation station) {
    final index = _favorites.indexWhere((f) => f.stationId == station.id);
    if (index == -1) return;

    _favorites[index] = _favorites[index].copyWith(station: station);
    notifyListeners();
    
    // Guardar asíncronamente sin bloquear
    _saveFavorites();
  }

  /// Guarda los favoritos en almacenamiento local
  Future<void> _saveFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _favorites.map((f) => f.toJson()).toList();
      await prefs.setString(_favoritesKey, json.encode(jsonList));
    } catch (e) {
      debugPrint('Error saving favorites: $e');
    }
  }

  /// Limpia todos los favoritos
  Future<void> clearAll() async {
    _favorites.clear();
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_favoritesKey);
  }

  /// Ordena los favoritos por fecha (más reciente primero)
  void sortByDate({bool ascending = false}) {
    _favorites.sort((a, b) => ascending
        ? a.addedAt.compareTo(b.addedAt)
        : b.addedAt.compareTo(a.addedAt));
    notifyListeners();
  }

  /// Ordena los favoritos por nombre
  void sortByName({bool ascending = true}) {
    _favorites.sort((a, b) {
      final nameA = a.station?.name ?? '';
      final nameB = b.station?.name ?? '';
      return ascending ? nameA.compareTo(nameB) : nameB.compareTo(nameA);
    });
    notifyListeners();
  }

  /// Ordena los favoritos por distancia
  void sortByDistance() {
    _favorites.sort((a, b) {
      final distA = a.station?.distanceKm ?? double.infinity;
      final distB = b.station?.distanceKm ?? double.infinity;
      return distA.compareTo(distB);
    });
    notifyListeners();
  }
}
