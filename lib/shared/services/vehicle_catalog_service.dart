import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/vehicle_sync/domain/models/vehicle_catalog.dart';

/// Catálogo de vehículos.
///
/// [load] devuelve la copia más reciente disponible sin red: la descargada
/// antes (SharedPreferences) o la incluida en la app
/// (`assets/data/vehicle_catalog.json`). [refresh] consulta la versión en
/// Firestore (`catalog_meta/vehicles`, 1 lectura) y solo si es más nueva
/// descarga marcas y modelos.
class VehicleCatalogService {
  static final VehicleCatalogService _instance = VehicleCatalogService._internal();
  factory VehicleCatalogService() => _instance;
  VehicleCatalogService._internal();

  static const String assetPath = 'assets/data/vehicle_catalog.json';
  static const String _cacheKey = 'vehicle_catalog_cache';

  VehicleCatalog _catalog = VehicleCatalog.empty;
  Future<VehicleCatalog>? _loading;

  /// Catálogo ya cargado (vacío si aún no se llamó a [load]).
  VehicleCatalog get catalog => _catalog;

  Future<VehicleCatalog> load() => _loading ??= _loadLocal();

  Future<VehicleCatalog> _loadLocal() async {
    final bundled = VehicleCatalog.fromJson(
      json.decode(await rootBundle.loadString(assetPath)) as Map<String, dynamic>,
    );
    VehicleCatalog? cached;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw != null) {
        cached = VehicleCatalog.fromJson(json.decode(raw) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('[WhereCargo] Catálogo guardado no válido: $e');
    }
    // Una actualización de la app puede traer un catálogo más nuevo que el
    // descargado antes
    return _catalog =
        cached != null && cached.version > bundled.version ? cached : bundled;
  }

  /// Descarga el catálogo de Firestore si hay una versión más nueva.
  /// Devuelve true si el catálogo cambió.
  Future<bool> refresh({FirebaseFirestore? firestore}) async {
    final current = await load();
    final db = firestore ?? FirebaseFirestore.instance;
    try {
      final meta = await db.collection('catalog_meta').doc('vehicles').get();
      final version = meta.data()?['version'] as int?;
      if (version == null || version <= current.version) return false;

      final results = await Future.wait([
        db.collection('vehicle_brands').get(),
        db.collection('vehicle_models').get(),
      ]);
      final remote = VehicleCatalog.fromFirestore(
        version: version,
        brands: {for (final d in results[0].docs) d.id: d.data()},
        models: {for (final d in results[1].docs) d.id: d.data()},
      );
      if (remote.models.isEmpty) return false;

      _catalog = remote;
      _loading = Future.value(remote);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, json.encode(remote.toJson()));
      debugPrint('[WhereCargo] Catálogo de vehículos actualizado a v$version');
      return true;
    } catch (e) {
      // Sin red o datos inválidos: se sigue con la copia local
      debugPrint('[WhereCargo] No se pudo actualizar el catálogo: $e');
      return false;
    }
  }

  /// Reemplaza el catálogo (solo pruebas).
  @visibleForTesting
  set catalog(VehicleCatalog value) {
    _catalog = value;
    _loading = Future.value(value);
  }
}
