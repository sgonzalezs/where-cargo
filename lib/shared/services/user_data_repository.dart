import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../features/vehicle_sync/domain/models/vehicle.dart';
import '../../features/vehicle_sync/domain/models/vehicle_catalog.dart';
import 'vehicle_catalog_service.dart';

/// Acceso a los datos del usuario en Firestore.
///
/// Estructura:
/// - `users/{uid}`: perfil y consentimiento
/// - `users/{uid}/vehicles/{vehicleId}`: vehículos registrados. Cada uno
///   guarda también `user_id` para poder consultarlos todos juntos
///   (`collectionGroup('vehicles')`) sin perder a qué usuario pertenecen,
///   y `model_id`/`variant_id` que referencian el catálogo.
/// - `vehicle_brands/{brandId}` y `vehicle_models/{modelId}`: catálogo de
///   solo lectura, publicado con `tool/seed_vehicle_catalog.mjs`.
///
/// Las reglas de Firestore (`firestore.rules`) solo permiten a cada usuario
/// leer y escribir sus propios documentos.
class UserDataRepository {
  UserDataRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _firestore.collection('users').doc(uid);

  CollectionReference<Map<String, dynamic>> _vehicles(String uid) =>
      _userDoc(uid).collection('vehicles');

  /// Crea o actualiza el perfil del usuario en cada inicio de sesión.
  Future<void> upsertUser(User user, {required bool statsConsent}) {
    return _userDoc(user.uid).set({
      'display_name': user.displayName,
      'email': user.email,
      'photo_url': user.photoURL,
      'platform': 'android',
      'created_at': user.metadata.creationTime,
      'last_login_at': FieldValue.serverTimestamp(),
      'stats_consent': statsConsent,
    }, SetOptions(merge: true));
  }

  /// Vehículos de la cuenta, con sus especificaciones resueltas desde el
  /// catálogo. Se omiten los que no se pueden leer (p. ej. un modelo que esta
  /// versión de la app todavía no conoce).
  Future<List<Vehicle>> fetchVehicles(String uid) async {
    final catalog = await VehicleCatalogService().load();
    final snapshot = await _vehicles(uid).get();
    final vehicles = <Vehicle>[];
    for (final doc in snapshot.docs) {
      final vehicle = vehicleFromDoc(doc.data(), catalog);
      if (vehicle != null) {
        vehicles.add(vehicle);
      } else {
        debugPrint('[WhereCargo] Vehículo ${doc.id} no válido, se omite');
      }
    }
    return vehicles;
  }

  /// Guarda los vehículos indicados reemplazando el documento completo, así
  /// no quedan campos de versiones anteriores.
  Future<void> saveVehicles(String uid, List<Vehicle> vehicles) async {
    final catalog = await VehicleCatalogService().load();
    final batch = _firestore.batch();
    for (final vehicle in vehicles) {
      batch.set(
        _vehicles(uid).doc(vehicle.id),
        {
          ...vehicleToDoc(uid, vehicle, catalog),
          'updated_at': FieldValue.serverTimestamp(),
        },
      );
    }
    await batch.commit();
  }

  Future<void> deleteVehicle(String uid, String vehicleId) =>
      _vehicles(uid).doc(vehicleId).delete();

  /// Elimina todos los datos del usuario (al eliminar la cuenta).
  Future<void> deleteUserData(String uid) async {
    final vehicles = await _vehicles(uid).get();
    final batch = _firestore.batch();
    for (final doc in vehicles.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(_userDoc(uid));
    await batch.commit();
  }

  /// Documento normalizado del vehículo: los del catálogo guardan solo
  /// `model_id`/`variant_id` (y `connectors` si el usuario cambió los de la
  /// versión); los personalizados guardan sus especificaciones en `custom`.
  @visibleForTesting
  static Map<String, dynamic> vehicleToDoc(
    String uid,
    Vehicle vehicle,
    VehicleCatalog catalog,
  ) {
    final variant = catalog.variant(vehicle.modelId, vehicle.variantId);
    return {
      'id': vehicle.id,
      'user_id': uid,
      'name': vehicle.name,
      'year': vehicle.year,
      'current_battery_percent': vehicle.currentBatteryPercent,
      'is_primary': vehicle.isPrimary,
      'created_at': Timestamp.fromDate(vehicle.createdAt),
      if (variant != null) ...{
        'model_id': vehicle.modelId,
        'variant_id': vehicle.variantId,
        if (!_sameConnectors(vehicle.compatibleConnectors, variant.connectors))
          'connectors': vehicle.compatibleConnectors,
      } else
        'custom': {
          'brand': vehicle.brand,
          'model': vehicle.model,
          'battery_capacity_kwh': vehicle.batteryCapacityKwh,
          'range_km': vehicle.estimatedRangeKm,
          'max_charging_power_kw': vehicle.maxChargingPowerKw,
          'connectors': vehicle.compatibleConnectors,
        },
    };
  }

  /// Inverso de [vehicleToDoc]. Devuelve null si el documento no es válido.
  @visibleForTesting
  static Vehicle? vehicleFromDoc(
    Map<String, dynamic> data,
    VehicleCatalog catalog,
  ) {
    try {
      final id = data['id'] as String;
      final name = data['name'] as String?;
      final year = data['year'] as int;
      final percent = (data['current_battery_percent'] as num).toDouble();
      final isPrimary = data['is_primary'] as bool? ?? false;
      final createdAt = (data['created_at'] as Timestamp?)?.toDate();

      final modelId = data['model_id'] as String?;
      if (modelId != null) {
        final model = catalog.modelById(modelId);
        final variant = model?.variantById(data['variant_id'] as String);
        final brand = model == null ? null : catalog.brandById(model.brandId);
        if (model == null || variant == null || brand == null) return null;
        return Vehicle.fromCatalog(
          id: id,
          name: name,
          brand: brand,
          model: model,
          variant: variant,
          year: year,
          currentBatteryPercent: percent,
          connectors: (data['connectors'] as List<dynamic>?)?.cast<String>(),
          isPrimary: isPrimary,
          createdAt: createdAt,
        );
      }

      final custom = data['custom'] as Map<String, dynamic>;
      return Vehicle(
        id: id,
        name: name,
        brand: custom['brand'] as String,
        model: custom['model'] as String,
        year: year,
        batteryCapacityKwh: (custom['battery_capacity_kwh'] as num).toDouble(),
        currentBatteryPercent: percent,
        estimatedRangeKm: (custom['range_km'] as num?)?.toDouble(),
        compatibleConnectors:
            (custom['connectors'] as List<dynamic>).cast<String>(),
        maxChargingPowerKw: (custom['max_charging_power_kw'] as num?)?.toDouble(),
        isPrimary: isPrimary,
        createdAt: createdAt,
      );
    } catch (e) {
      return null;
    }
  }

  static bool _sameConnectors(List<String> a, List<String> b) =>
      a.length == b.length && a.toSet().containsAll(b);
}
