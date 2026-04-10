import 'package:flutter/material.dart';

import '../../domain/models/vehicle.dart';
import '../../../../core/theme/app_colors.dart';

/// Página de estado del vehículo
class VehicleStatusPage extends StatefulWidget {
  const VehicleStatusPage({super.key});

  @override
  State<VehicleStatusPage> createState() => _VehicleStatusPageState();
}

class _VehicleStatusPageState extends State<VehicleStatusPage> {
  Vehicle? _vehicle;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVehicle();
  }

  Future<void> _loadVehicle() async {
    setState(() => _isLoading = true);

    // TODO: Cargar desde repositorio
    await Future.delayed(const Duration(seconds: 1));

    setState(() {
      _vehicle = _getMockVehicle();
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Vehículo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadVehicle,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              // TODO: Configuración del vehículo
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _vehicle == null
              ? _buildNoVehicle()
              : _buildVehicleInfo(),
    );
  }

  Widget _buildNoVehicle() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.electric_car,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No tienes vehículos registrados',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Agrega tu vehículo eléctrico para ver\ninformación personalizada',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              // TODO: Agregar vehículo
            },
            icon: const Icon(Icons.add),
            label: const Text('Agregar Vehículo'),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleInfo() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildVehicleCard(),
          const SizedBox(height: 24),
          _buildBatteryStatus(),
          const SizedBox(height: 24),
          _buildRangeInfo(),
          const SizedBox(height: 24),
          _buildCompatibleConnectors(),
          const SizedBox(height: 24),
          _buildChargingTips(),
        ],
      ),
    );
  }

  Widget _buildVehicleCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 100,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: _vehicle?.imageUrl != null
                  ? Image.network(
                      _vehicle!.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.electric_car,
                        size: 48,
                        color: AppColors.primary,
                      ),
                    )
                  : const Icon(
                      Icons.electric_car,
                      size: 48,
                      color: AppColors.primary,
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_vehicle?.name != null)
                    Text(
                      _vehicle!.name!,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  Text(
                    '${_vehicle!.brand} ${_vehicle!.model}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  Text(
                    '${_vehicle!.year}',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () {
                // TODO: Editar vehículo
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBatteryStatus() {
    final batteryPercent = _vehicle!.currentBatteryPercent;
    final batteryColor = batteryPercent > 50
        ? AppColors.success
        : batteryPercent > 20
            ? AppColors.warning
            : AppColors.error;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.battery_charging_full,
                  color: batteryColor,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Text(
                  'Estado de Batería',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${batteryPercent.toStringAsFixed(0)}%',
                        style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: batteryColor,
                            ),
                      ),
                      Text(
                        '${_vehicle!.currentBatteryKwh.toStringAsFixed(1)} / ${_vehicle!.batteryCapacityKwh.toStringAsFixed(0)} kWh',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 100,
                  height: 100,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: batteryPercent / 100,
                        strokeWidth: 10,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation(batteryColor),
                      ),
                      Icon(
                        Icons.bolt,
                        size: 40,
                        color: batteryColor,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: batteryPercent / 100,
                minHeight: 12,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation(batteryColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRangeInfo() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.route, color: AppColors.secondary),
                const SizedBox(width: 8),
                Text(
                  'Autonomía Estimada',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildRangeItem(
                  icon: Icons.directions_car,
                  label: 'Actual',
                  value: '${_vehicle!.estimatedRangeKm?.toStringAsFixed(0) ?? "--"} km',
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: Colors.grey[300],
                ),
                _buildRangeItem(
                  icon: Icons.battery_full,
                  label: 'Carga completa',
                  value: '${(_vehicle!.estimatedRangeKm ?? 0 / _vehicle!.currentBatteryPercent * 100).toStringAsFixed(0)} km',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRangeItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, color: AppColors.textSecondary),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ],
    );
  }

  Widget _buildCompatibleConnectors() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.power, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Conectores Compatibles',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _vehicle!.compatibleConnectors.map((connector) {
                return Chip(
                  avatar: const Icon(Icons.check_circle, size: 18),
                  label: Text(connector),
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                );
              }).toList(),
            ),
            if (_vehicle!.maxChargingPowerKw != null) ...[
              const SizedBox(height: 12),
              Text(
                'Potencia máxima de carga: ${_vehicle!.maxChargingPowerKw!.toStringAsFixed(0)} kW',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChargingTips() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lightbulb, color: Colors.amber),
                const SizedBox(width: 8),
                Text(
                  'Consejos de Carga',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildTipItem(
              'Mantén la batería entre 20% y 80% para mayor durabilidad',
            ),
            _buildTipItem(
              'Usa carga rápida DC solo cuando sea necesario',
            ),
            _buildTipItem(
              'Precalienta la batería antes de cargar en clima frío',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTipItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check, size: 16, color: AppColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Vehicle _getMockVehicle() {
    return Vehicle.fromJson({
      'id': 'v1',
      'name': 'Mi Tesla',
      'brand': 'Tesla',
      'model': 'Model 3 Long Range',
      'year': 2023,
      'battery_capacity_kwh': 82,
      'current_battery_percent': 65,
      'estimated_range_km': 380,
      'compatible_connectors': ['Type 2', 'CCS2', 'Tesla Supercharger'],
      'max_charging_power_kw': 250,
      'is_primary': true,
    });
  }
}
