import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:where_cargo/features/vehicle_sync/domain/models/vehicle.dart';
import 'package:where_cargo/features/vehicle_sync/domain/models/vehicle_catalog.dart';
import 'package:where_cargo/shared/services/user_data_repository.dart';
import 'package:where_cargo/shared/services/vehicle_service.dart';

void main() {
  final catalog = VehicleCatalog.fromJson(
    json.decode(File('assets/data/vehicle_catalog.json').readAsStringSync())
        as Map<String, dynamic>,
  );

  Vehicle dolphin({List<String>? connectors}) {
    final model = catalog.modelById('byd_dolphin')!;
    return Vehicle.fromCatalog(
      id: 'vehicle_1700000000000',
      name: 'Mi Dolphin',
      brand: catalog.brandById('byd')!,
      model: model,
      variant: model.variantById('60')!,
      year: 2024,
      currentBatteryPercent: 80,
      connectors: connectors,
      isPrimary: true,
    );
  }

  group('catálogo incluido en la app', () {
    test('ids únicos y referencias válidas', () {
      final brandIds = catalog.brands.map((b) => b.id).toList();
      expect(brandIds.toSet().length, brandIds.length);
      final modelIds = catalog.models.map((m) => m.id).toList();
      expect(modelIds.toSet().length, modelIds.length);

      final connectorIds = vehicleConnectorOptions.map((c) => c.id).toSet();
      for (final model in catalog.models) {
        expect(brandIds, contains(model.brandId), reason: model.id);
        expect(model.variants, isNotEmpty, reason: model.id);
        final variantIds = model.variants.map((v) => v.id).toList();
        expect(variantIds.toSet().length, variantIds.length, reason: model.id);
        for (final variant in model.variants) {
          expect(variant.batteryKwh, greaterThan(0));
          expect(variant.rangeKm, greaterThan(0));
          expect(connectorIds.containsAll(variant.connectors), isTrue,
              reason: '${model.id}/${variant.id}');
        }
      }
    });

    test('se puede guardar y volver a leer (copia en el teléfono)', () {
      final copy = VehicleCatalog.fromJson(
        json.decode(json.encode(catalog.toJson())) as Map<String, dynamic>,
      );
      expect(copy.version, catalog.version);
      expect(copy.models.length, catalog.models.length);
      expect(copy.variant('byd_dolphin', '60')?.batteryKwh, 60.4);
    });

    test('lee el formato de Firestore respetando el orden de versiones', () {
      final remote = VehicleCatalog.fromFirestore(
        version: 2,
        brands: {
          'byd': {'name': 'BYD', 'catalog_version': 2},
        },
        models: {
          'byd_dolphin': {
            'brand_id': 'byd',
            'name': 'Dolphin',
            'catalog_version': 2,
            'variants': {
              '60': {
                'name': '60.4 kWh', 'battery_kwh': 60.4, 'range_km': 427,
                'max_dc_kw': 88, 'max_ac_kw': 11,
                'connectors': ['ccs2', 'type2'], 'order': 1,
              },
              '45': {
                'name': '44.9 kWh', 'battery_kwh': 44.9, 'range_km': 340,
                'max_dc_kw': 60, 'max_ac_kw': 7,
                'connectors': ['ccs2', 'type2'], 'order': 0,
              },
            },
          },
        },
      );
      expect(remote.version, 2);
      expect(remote.brandById('byd')?.name, 'BYD');
      expect(remote.modelById('byd_dolphin')!.variants.map((v) => v.id),
          ['45', '60']);
      expect(remote.variant('byd_dolphin', '45')?.maxDcKw, 60);
    });

    test('match encuentra modelos escritos como texto', () {
      expect(catalog.match('BYD', 'Atto 3')?.id, 'byd_yuan_plus');
      expect(catalog.match('byd', 'Yuan Plus')?.id, 'byd_yuan_plus');
      expect(catalog.match('Tesla', 'Model 3')?.id, 'tesla_model_3');
      expect(catalog.match('Hyundai', 'Ioniq 5')?.id, 'hyundai_ioniq_5');
      expect(catalog.match('Otros', 'Otro modelo'), isNull);
    });
  });

  group('documento normalizado en Firestore', () {
    test('vehículo del catálogo guarda solo referencias', () {
      final doc = UserDataRepository.vehicleToDoc('uid1', dolphin(), catalog);

      expect(doc['user_id'], 'uid1');
      expect(doc['model_id'], 'byd_dolphin');
      expect(doc['variant_id'], '60');
      for (final key in ['brand', 'model', 'battery_capacity_kwh', 'custom', 'connectors']) {
        expect(doc.containsKey(key), isFalse, reason: key);
      }

      final back = UserDataRepository.vehicleFromDoc(doc, catalog)!;
      expect(back.fullModelName, 'BYD Dolphin 60.4 kWh');
      expect(back.batteryCapacityKwh, 60.4);
      expect(back.compatibleConnectors, ['ccs2', 'type2']);
      expect(back.currentBatteryPercent, 80);
      expect(back.isPrimary, isTrue);
      expect(back.createdAt, dolphin().createdAt);
    });

    test('conectores ajustados por el usuario se guardan aparte', () {
      final doc = UserDataRepository.vehicleToDoc(
        'uid1',
        dolphin(connectors: ['ccs2', 'type2', 'chademo']),
        catalog,
      );
      expect(doc['connectors'], ['ccs2', 'type2', 'chademo']);
      expect(
        UserDataRepository.vehicleFromDoc(doc, catalog)!.compatibleConnectors,
        ['ccs2', 'type2', 'chademo'],
      );
    });

    test('vehículo personalizado guarda sus datos en custom', () {
      final custom = Vehicle(
        id: 'vehicle_2',
        brand: 'Marca X',
        model: 'Modelo Y',
        year: 2023,
        batteryCapacityKwh: 50,
        currentBatteryPercent: 60,
        estimatedRangeKm: 300,
        compatibleConnectors: ['gbt_dc'],
      );
      final doc = UserDataRepository.vehicleToDoc('uid1', custom, catalog);
      expect(doc.containsKey('model_id'), isFalse);
      expect((doc['custom'] as Map)['brand'], 'Marca X');

      final back = UserDataRepository.vehicleFromDoc(doc, catalog)!;
      expect(back.isFromCatalog, isFalse);
      expect(back.fullModelName, 'Marca X Modelo Y');
      expect(back.estimatedRangeKm, 300);
      expect(back.currentRangeKm, 180);
    });

    test('modelo desconocido o documento antiguo se omite', () {
      final doc = UserDataRepository.vehicleToDoc('uid1', dolphin(), catalog)
        ..['model_id'] = 'no_existe';
      expect(UserDataRepository.vehicleFromDoc(doc, catalog), isNull);
      expect(
        UserDataRepository.vehicleFromDoc({'id': 'x', 'brand': 'BYD'}, catalog),
        isNull,
      );
    });
  });

  group('vehículos guardados antes del catálogo', () {
    test('se enlazan a la versión con batería más parecida', () {
      final legacy = Vehicle.fromJson({
        'id': 'vehicle_1690000000000',
        'brand': 'BYD',
        'model': 'Dolphin',
        'year': 2024,
        'battery_capacity_kwh': 60,
        'current_battery_percent': 50,
        'compatible_connectors': ['ccs2', 'nacs'],
        'is_primary': true,
      });
      expect(legacy.createdAt,
          DateTime.fromMillisecondsSinceEpoch(1690000000000));

      final linked = VehicleService.linkToCatalog(legacy, catalog);
      expect(linked.modelId, 'byd_dolphin');
      expect(linked.variantId, '60');
      expect(linked.compatibleConnectors, ['ccs2', 'tesla']);
      expect(linked.currentBatteryPercent, 50);
      expect(linked.createdAt, legacy.createdAt);
    });

    test('modelos que no están en el catálogo quedan personalizados', () {
      final legacy = Vehicle(
        id: 'vehicle_3',
        brand: 'Otros',
        model: 'Otro modelo',
        year: 2022,
        batteryCapacityKwh: 40,
        currentBatteryPercent: 100,
        compatibleConnectors: ['type2'],
      );
      expect(identical(VehicleService.linkToCatalog(legacy, catalog), legacy),
          isTrue);
    });
  });
}
