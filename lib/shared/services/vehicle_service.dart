import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/vehicle_sync/domain/models/vehicle.dart';

/// Servicio singleton para gestionar vehículos del usuario
/// Persiste los datos localmente usando SharedPreferences
class VehicleService extends ChangeNotifier {
  // Singleton
  static final VehicleService _instance = VehicleService._internal();
  factory VehicleService() => _instance;
  VehicleService._internal();

  // Claves para SharedPreferences
  static const String _vehiclesKey = 'user_vehicles';

  // Cache en memoria
  List<Vehicle> _vehicles = [];
  bool _isLoaded = false;
  bool _isLoading = false;

  /// Lista de vehículos del usuario
  List<Vehicle> get vehicles => List.unmodifiable(_vehicles);

  /// Vehículo principal (primero marcado como primary, o el primero de la lista)
  Vehicle? get primaryVehicle {
    if (_vehicles.isEmpty) return null;
    return _vehicles.firstWhere(
      (v) => v.isPrimary,
      orElse: () => _vehicles.first,
    );
  }

  /// Indica si está cargando
  bool get isLoading => _isLoading;

  /// Indica si ya se cargaron los datos
  bool get isLoaded => _isLoaded;

  /// Indica si hay vehículos registrados
  bool get hasVehicles => _vehicles.isNotEmpty;

  /// Cantidad de vehículos
  int get count => _vehicles.length;

  /// Carga los vehículos desde almacenamiento local
  Future<void> loadVehicles() async {
    if (_isLoaded || _isLoading) return;

    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_vehiclesKey);

      if (jsonString != null && jsonString.isNotEmpty) {
        final List<dynamic> jsonList = json.decode(jsonString);
        _vehicles = jsonList
            .map((item) => Vehicle.fromJson(item as Map<String, dynamic>))
            .toList();
      }

      _isLoaded = true;
    } catch (e) {
      debugPrint('Error loading vehicles: $e');
      _vehicles = [];
      _isLoaded = true;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Agrega un nuevo vehículo
  Future<bool> addVehicle(Vehicle vehicle) async {
    // Si es el primer vehículo, marcarlo como primario
    final vehicleToAdd = _vehicles.isEmpty
        ? vehicle.copyWith(isPrimary: true)
        : vehicle;

    _vehicles.add(vehicleToAdd);
    notifyListeners();

    await _saveVehicles();
    return true;
  }

  /// Actualiza un vehículo existente
  Future<bool> updateVehicle(Vehicle vehicle) async {
    final index = _vehicles.indexWhere((v) => v.id == vehicle.id);
    if (index == -1) return false;

    _vehicles[index] = vehicle;
    notifyListeners();

    await _saveVehicles();
    return true;
  }

  /// Elimina un vehículo
  Future<bool> removeVehicle(String vehicleId) async {
    final index = _vehicles.indexWhere((v) => v.id == vehicleId);
    if (index == -1) return false;

    final wasRemoved = _vehicles.removeAt(index);
    
    // Si era el primario y quedan vehículos, hacer primario al primero
    if (wasRemoved.isPrimary && _vehicles.isNotEmpty) {
      _vehicles[0] = _vehicles[0].copyWith(isPrimary: true);
    }

    notifyListeners();
    await _saveVehicles();
    return true;
  }

  /// Establece un vehículo como primario
  Future<void> setPrimaryVehicle(String vehicleId) async {
    _vehicles = _vehicles.map((v) {
      return v.copyWith(isPrimary: v.id == vehicleId);
    }).toList();

    notifyListeners();
    await _saveVehicles();
  }

  /// Actualiza el nivel de batería de un vehículo
  Future<void> updateBatteryLevel(String vehicleId, double percent, {double? rangeKm}) async {
    final index = _vehicles.indexWhere((v) => v.id == vehicleId);
    if (index == -1) return;

    _vehicles[index] = _vehicles[index].copyWith(
      currentBatteryPercent: percent.clamp(0, 100),
      estimatedRangeKm: rangeKm,
    );

    notifyListeners();
    await _saveVehicles();
  }

  /// Obtiene un vehículo por ID
  Vehicle? getVehicleById(String vehicleId) {
    try {
      return _vehicles.firstWhere((v) => v.id == vehicleId);
    } catch (_) {
      return null;
    }
  }

  /// Guarda los vehículos en almacenamiento local
  Future<void> _saveVehicles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _vehicles.map((v) => v.toJson()).toList();
      await prefs.setString(_vehiclesKey, json.encode(jsonList));
    } catch (e) {
      debugPrint('Error saving vehicles: $e');
    }
  }

  /// Limpia todos los vehículos
  Future<void> clearAll() async {
    _vehicles.clear();
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_vehiclesKey);
  }
}
