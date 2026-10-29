/// Catálogo de vehículos eléctricos: marcas, modelos y versiones con sus
/// especificaciones oficiales. Los vehículos del usuario solo guardan la
/// referencia (`model_id` + `variant_id`).
///
/// La fuente es `assets/data/vehicle_catalog.json`; `tool/seed_vehicle_catalog.mjs`
/// la publica en Firestore (`vehicle_brands`, `vehicle_models` y la versión en
/// `catalog_meta/vehicles`). La app trae el JSON como respaldo y descarga el
/// catálogo de Firestore cuando hay una versión más nueva.
class VehicleCatalog {
  final int version;
  final List<VehicleBrand> brands;
  final List<VehicleModel> models;

  const VehicleCatalog({
    required this.version,
    required this.brands,
    required this.models,
  });

  static const empty = VehicleCatalog(version: 0, brands: [], models: []);

  factory VehicleCatalog.fromJson(Map<String, dynamic> json) {
    return VehicleCatalog(
      version: json['version'] as int,
      brands: (json['brands'] as List<dynamic>)
          .map((b) => VehicleBrand.fromJson(b as Map<String, dynamic>))
          .toList(),
      models: (json['models'] as List<dynamic>)
          .map((m) => VehicleModel.fromJson(m as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Catálogo leído de Firestore: documentos por id; las versiones de cada
  /// modelo vienen como mapa `{id: {..., order}}`.
  factory VehicleCatalog.fromFirestore({
    required int version,
    required Map<String, Map<String, dynamic>> brands,
    required Map<String, Map<String, dynamic>> models,
  }) {
    return VehicleCatalog(
      version: version,
      brands: brands.entries
          .map((e) => VehicleBrand(id: e.key, name: e.value['name'] as String))
          .toList(),
      models: models.entries.map((e) {
        final variants = (e.value['variants'] as Map<String, dynamic>)
            .entries
            .map((v) => MapEntry(v.key, v.value as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => (a.value['order'] as num? ?? 0)
              .compareTo(b.value['order'] as num? ?? 0));
        return VehicleModel(
          id: e.key,
          brandId: e.value['brand_id'] as String,
          name: e.value['name'] as String,
          variants: variants
              .map((v) => VehicleVariant.fromJson({...v.value, 'id': v.key}))
              .toList(),
        );
      }).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'brands': brands.map((b) => b.toJson()).toList(),
        'models': models.map((m) => m.toJson()).toList(),
      };

  VehicleBrand? brandById(String id) {
    for (final brand in brands) {
      if (brand.id == id) return brand;
    }
    return null;
  }

  VehicleModel? modelById(String id) {
    for (final model in models) {
      if (model.id == id) return model;
    }
    return null;
  }

  List<VehicleModel> modelsOf(String brandId) =>
      models.where((m) => m.brandId == brandId).toList();

  VehicleVariant? variant(String? modelId, String? variantId) {
    if (modelId == null || variantId == null) return null;
    return modelById(modelId)?.variantById(variantId);
  }

  /// Busca el modelo que corresponde a una marca y modelo escritos como
  /// texto (vehículos guardados antes del catálogo). Compara sin mayúsculas
  /// ni signos y acepta nombres alternativos entre paréntesis, p. ej.
  /// "Atto 3" encuentra "Yuan Plus (Atto 3)".
  VehicleModel? match(String brandName, String modelName) {
    final brandKey = _normalize(brandName);
    final modelKey = _normalize(modelName);
    if (brandKey.isEmpty || modelKey.isEmpty) return null;
    for (final model in models) {
      final brand = brandById(model.brandId);
      if (brand == null || _normalize(brand.name) != brandKey) continue;
      final names = model.name
          .split(RegExp(r'[()]'))
          .map(_normalize)
          .where((n) => n.isNotEmpty);
      if (names.contains(modelKey)) return model;
    }
    return null;
  }

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

class VehicleBrand {
  final String id;
  final String name;

  const VehicleBrand({required this.id, required this.name});

  factory VehicleBrand.fromJson(Map<String, dynamic> json) {
    return VehicleBrand(id: json['id'] as String, name: json['name'] as String);
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

class VehicleModel {
  final String id;
  final String brandId;
  final String name;
  final List<VehicleVariant> variants;

  const VehicleModel({
    required this.id,
    required this.brandId,
    required this.name,
    required this.variants,
  });

  factory VehicleModel.fromJson(Map<String, dynamic> json) {
    return VehicleModel(
      id: json['id'] as String,
      brandId: json['brand_id'] as String,
      name: json['name'] as String,
      variants: (json['variants'] as List<dynamic>)
          .map((v) => VehicleVariant.fromJson(v as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'brand_id': brandId,
        'name': name,
        'variants': variants.map((v) => v.toJson()).toList(),
      };

  VehicleVariant? variantById(String id) {
    for (final variant in variants) {
      if (variant.id == id) return variant;
    }
    return null;
  }

  /// Versión con la batería más parecida a [batteryKwh].
  VehicleVariant closestVariant(double batteryKwh) {
    return variants.reduce((a, b) =>
        (a.batteryKwh - batteryKwh).abs() <= (b.batteryKwh - batteryKwh).abs()
            ? a
            : b);
  }
}

class VehicleVariant {
  final String id;
  final String name;
  final double batteryKwh;
  final double rangeKm;
  final double maxDcKw;
  final double maxAcKw;
  final List<String> connectors;

  const VehicleVariant({
    required this.id,
    required this.name,
    required this.batteryKwh,
    required this.rangeKm,
    required this.maxDcKw,
    required this.maxAcKw,
    required this.connectors,
  });

  factory VehicleVariant.fromJson(Map<String, dynamic> json) {
    return VehicleVariant(
      id: json['id'] as String,
      name: json['name'] as String,
      batteryKwh: (json['battery_kwh'] as num).toDouble(),
      rangeKm: (json['range_km'] as num).toDouble(),
      maxDcKw: (json['max_dc_kw'] as num).toDouble(),
      maxAcKw: (json['max_ac_kw'] as num).toDouble(),
      connectors: (json['connectors'] as List<dynamic>).cast<String>(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'battery_kwh': batteryKwh,
        'range_km': rangeKm,
        'max_dc_kw': maxDcKw,
        'max_ac_kw': maxAcKw,
        'connectors': connectors,
      };
}

/// Conector que se puede asignar a un vehículo. Los ids coinciden con
/// `ConnectorType.apiValue` de las estaciones para calcular compatibilidad.
class VehicleConnectorOption {
  final String id;
  final String name;
  final String description;

  const VehicleConnectorOption(this.id, this.name, this.description);
}

const List<VehicleConnectorOption> vehicleConnectorOptions = [
  VehicleConnectorOption('ccs2', 'CCS2 (Combo 2)', 'Carga rápida DC'),
  VehicleConnectorOption('type2', 'Type 2 (Mennekes)', 'Carga AC'),
  VehicleConnectorOption('ccs1', 'CCS1 (Combo 1)', 'Carga rápida DC (EE. UU.)'),
  VehicleConnectorOption('type1', 'Type 1 (J1772)', 'Carga AC (EE. UU.)'),
  VehicleConnectorOption('chademo', 'CHAdeMO', 'Carga rápida DC (Japón)'),
  VehicleConnectorOption('tesla', 'Tesla (NACS)', 'Conector propio de Tesla'),
  VehicleConnectorOption('gbt_dc', 'GB/T DC', 'Carga rápida DC (China)'),
  VehicleConnectorOption('gbt_ac', 'GB/T AC', 'Carga AC (China)'),
];
