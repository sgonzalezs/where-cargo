import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/vehicle_sync/domain/models/vehicle.dart';
import '../../features/vehicle_sync/domain/models/vehicle_catalog.dart';
import 'user_data_repository.dart';
import 'vehicle_catalog_service.dart';

/// Servicio singleton para gestionar vehículos del usuario
/// Persiste los datos localmente usando SharedPreferences y, si hay sesión
/// iniciada, los sincroniza con Firestore.
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

  // Usuario con sesión iniciada (null = solo almacenamiento local)
  String? _uid;
  UserDataRepository? _remote;

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

        if (_linkVehicles(await VehicleCatalogService().load())) {
          await prefs.setString(
            _vehiclesKey,
            json.encode(_vehicles.map((v) => v.toJson()).toList()),
          );
        }
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
    _syncRemote((repo, uid) => repo.deleteVehicle(uid, vehicleId));
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
  Future<void> updateBatteryLevel(String vehicleId, double percent) async {
    final index = _vehicles.indexWhere((v) => v.id == vehicleId);
    if (index == -1) return;

    _vehicles[index] = _vehicles[index].copyWith(
      currentBatteryPercent: percent.clamp(0, 100),
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

  /// Guarda los vehículos en almacenamiento local y, con sesión, en Firestore
  Future<void> _saveVehicles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _vehicles.map((v) => v.toJson()).toList();
      await prefs.setString(_vehiclesKey, json.encode(jsonList));
    } catch (e) {
      debugPrint('Error saving vehicles: $e');
    }
    final snapshot = List.of(_vehicles);
    _syncRemote((repo, uid) => repo.saveVehicles(uid, snapshot));
  }

  /// Asocia los vehículos a la cuenta con sesión iniciada ([uid] null al
  /// cerrar sesión). Los vehículos que solo estaban en el teléfono se suben
  /// y los que solo estaban en la cuenta se descargan.
  Future<void> attachUser(String? uid) async {
    _uid = uid;
    if (uid == null) return;
    final repo = _remote ??= UserDataRepository();
    try {
      await loadVehicles();
      final remote = await repo.fetchVehicles(uid);
      if (_uid != uid) return; // cambió la sesión mientras tanto

      final localIds = _vehicles.map((v) => v.id).toSet();
      final downloaded = remote.where((v) => !localIds.contains(v.id));
      if (downloaded.isNotEmpty) {
        final hasPrimary = _vehicles.any((v) => v.isPrimary);
        _vehicles.addAll(
          hasPrimary
              ? downloaded.map((v) => v.copyWith(isPrimary: false))
              : downloaded,
        );
        notifyListeners();
      }
      await _saveVehicles();
    } catch (e) {
      debugPrint('[WhereCargo] Error sincronizando vehículos: $e');
    }
  }

  /// Ejecuta una escritura en Firestore si hay sesión. No se espera: Firestore
  /// la encola sin conexión y la envía cuando vuelve la red.
  void _syncRemote(
    Future<void> Function(UserDataRepository repo, String uid) write,
  ) {
    final uid = _uid;
    final repo = _remote;
    if (uid == null || repo == null) return;
    write(repo, uid).catchError((Object e) {
      debugPrint('[WhereCargo] Error sincronizando vehículos: $e');
    });
  }

  /// Enlaza al catálogo los vehículos personalizados cuyo modelo se agregó
  /// después (llamar cuando se descarga un catálogo nuevo).
  Future<void> relinkVehicles() async {
    await loadVehicles();
    if (!_linkVehicles(VehicleCatalogService().catalog)) return;
    notifyListeners();
    await _saveVehicles();
  }

  bool _linkVehicles(VehicleCatalog catalog) {
    final linked = _vehicles.map((v) => linkToCatalog(v, catalog)).toList();
    final changed =
        linked.indexed.any((e) => !identical(e.$2, _vehicles[e.$1]));
    if (changed) _vehicles = linked;
    return changed;
  }

  /// Vehículos sin modelo del catálogo (guardados antes de existir o como
  /// "Otro modelo"): si el modelo existe en el catálogo se enlaza a la versión con la batería
  /// más parecida y se conservan los conectores que eligió el usuario.
  @visibleForTesting
  static Vehicle linkToCatalog(Vehicle vehicle, VehicleCatalog catalog) {
    if (vehicle.modelId != null) return vehicle;
    final model = catalog.match(vehicle.brand, vehicle.model);
    final brand = model == null ? null : catalog.brandById(model.brandId);
    if (model == null || brand == null) return vehicle;
    return Vehicle.fromCatalog(
      id: vehicle.id,
      name: vehicle.name,
      brand: brand,
      model: model,
      variant: model.closestVariant(vehicle.batteryCapacityKwh),
      year: vehicle.year,
      currentBatteryPercent: vehicle.currentBatteryPercent,
      connectors: vehicle.compatibleConnectors
          .map((c) => c == 'nacs' ? 'tesla' : c)
          .toSet()
          .toList(),
      isPrimary: vehicle.isPrimary,
      createdAt: vehicle.createdAt,
    );
  }

  /// Limpia todos los vehículos
  Future<void> clearAll() async {
    _vehicles.clear();
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_vehiclesKey);
  }
}
