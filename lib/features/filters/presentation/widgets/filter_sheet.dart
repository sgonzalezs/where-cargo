import 'package:flutter/material.dart';

import '../../../charging_stations/domain/enums/charging_enums.dart';
import '../../domain/models/station_filters.dart';
import '../../../../core/theme/app_colors.dart';

/// Widget de filtros para estaciones
class FilterSheet extends StatefulWidget {
  final StationFilters initialFilters;
  final ValueChanged<StationFilters> onApply;

  const FilterSheet({
    super.key,
    required this.initialFilters,
    required this.onApply,
  });

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late StationFilters _filters;

  @override
  void initState() {
    super.initState();
    _filters = widget.initialFilters;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(context),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCityFilter(context),
                  const SizedBox(height: 20),
                  _buildConnectorTypesFilter(context),
                  const SizedBox(height: 20),
                  _buildChargingTypeFilter(context),
                  const SizedBox(height: 20),
                  _buildChargingSpeedFilter(context),
                  const SizedBox(height: 20),
                  _buildQuickFilters(context),
                  const SizedBox(height: 20),
                  _buildDistanceFilter(context),
                  const SizedBox(height: 20),
                  _buildSortOption(context),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildActionButtons(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Text(
          'Filtros',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        if (_filters.hasActiveFilters)
          Container(
            margin: const EdgeInsets.only(left: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${_filters.activeFilterCount}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        const Spacer(),
        if (_filters.hasActiveFilters)
          TextButton(
            onPressed: () {
              setState(() {
                _filters = _filters.clear();
              });
            },
            child: const Text('Limpiar todo'),
          ),
      ],
    );
  }

  Widget _buildCityFilter(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ciudad',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ColombianCity.values.map((city) {
            final isSelected = _filters.city == city.displayName;
            return FilterChip(
              label: Text(city.displayName),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  _filters = _filters.copyWith(
                    city: selected ? city.displayName : null,
                    clearCity: !selected,
                  );
                });
              },
              selectedColor: AppColors.primary.withOpacity(0.2),
              checkmarkColor: AppColors.primary,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildConnectorTypesFilter(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tipo de Conector',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ConnectorType.values.map((type) {
            final isSelected = _filters.connectorTypes.contains(type);
            return FilterChip(
              label: Text(type.displayName),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  final newTypes = Set<ConnectorType>.from(
                    _filters.connectorTypes,
                  );
                  if (selected) {
                    newTypes.add(type);
                  } else {
                    newTypes.remove(type);
                  }
                  _filters = _filters.copyWith(connectorTypes: newTypes);
                });
              },
              selectedColor: AppColors.secondary.withOpacity(0.2),
              checkmarkColor: AppColors.secondary,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildChargingTypeFilter(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tipo de Carga',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: ChargingType.values.map((type) {
            final isSelected = _filters.chargingTypes.contains(type);
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(type.displayName),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      final newTypes = Set<ChargingType>.from(
                        _filters.chargingTypes,
                      );
                      if (selected) {
                        newTypes.add(type);
                      } else {
                        newTypes.remove(type);
                      }
                      _filters = _filters.copyWith(chargingTypes: newTypes);
                    });
                  },
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildChargingSpeedFilter(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Velocidad de Carga',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ChargingSpeed.values.map((speed) {
            final isSelected = _filters.chargingSpeeds.contains(speed);
            return FilterChip(
              label: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(speed.displayName),
                  Text(
                    '${speed.minPowerKw.toInt()}-${speed.maxPowerKw.toInt()} kW',
                    style: const TextStyle(fontSize: 10),
                  ),
                ],
              ),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  final newSpeeds = Set<ChargingSpeed>.from(
                    _filters.chargingSpeeds,
                  );
                  if (selected) {
                    newSpeeds.add(speed);
                  } else {
                    newSpeeds.remove(speed);
                  }
                  _filters = _filters.copyWith(chargingSpeeds: newSpeeds);
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildQuickFilters(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Filtros Rápidos',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(
              avatar: const Icon(Icons.money_off, size: 18),
              label: const Text('Gratis'),
              selected: _filters.isFree == true,
              onSelected: (selected) {
                setState(() {
                  _filters = _filters.copyWith(
                    isFree: selected ? true : null,
                    clearIsFree: !selected,
                  );
                });
              },
              selectedColor: AppColors.success.withOpacity(0.2),
            ),
            FilterChip(
              avatar: const Icon(Icons.check_circle, size: 18),
              label: const Text('Disponible'),
              selected: _filters.isAvailable == true,
              onSelected: (selected) {
                setState(() {
                  _filters = _filters.copyWith(
                    isAvailable: selected ? true : null,
                    clearIsAvailable: !selected,
                  );
                });
              },
              selectedColor: AppColors.stationAvailable.withOpacity(0.2),
            ),
            FilterChip(
              avatar: const Icon(Icons.access_time, size: 18),
              label: const Text('Abierto ahora'),
              selected: _filters.isOpenNow == true,
              onSelected: (selected) {
                setState(() {
                  _filters = _filters.copyWith(
                    isOpenNow: selected ? true : null,
                    clearIsOpenNow: !selected,
                  );
                });
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDistanceFilter(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Distancia máxima',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            Text(
              _filters.maxDistanceKm != null
                  ? '${_filters.maxDistanceKm!.toInt()} km'
                  : 'Sin límite',
              style: const TextStyle(color: AppColors.primary),
            ),
          ],
        ),
        Slider(
          value: _filters.maxDistanceKm ?? 50,
          min: 1,
          max: 50,
          divisions: 49,
          label: '${(_filters.maxDistanceKm ?? 50).toInt()} km',
          onChanged: (value) {
            setState(() {
              _filters = _filters.copyWith(
                maxDistanceKm: value < 50 ? value : null,
                clearMaxDistance: value >= 50,
              );
            });
          },
        ),
      ],
    );
  }

  Widget _buildSortOption(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ordenar por',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: SortOption.values.map((option) {
            final isSelected = _filters.sortBy == option;
            return ChoiceChip(
              label: Text(option.displayName),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _filters = _filters.copyWith(sortBy: option);
                  });
                }
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.maybePop(context),
            child: const Text('Cancelar'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: () {
              widget.onApply(_filters);
              Navigator.maybePop(context);
            },
            child: const Text('Aplicar filtros'),
          ),
        ),
      ],
    );
  }
}
