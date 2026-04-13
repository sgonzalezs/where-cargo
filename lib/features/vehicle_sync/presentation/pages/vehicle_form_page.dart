import 'package:flutter/material.dart';

import '../../domain/models/vehicle.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/services/vehicle_service.dart';

/// Página para agregar o editar un vehículo
class VehicleFormPage extends StatefulWidget {
  final Vehicle? vehicle; // null si es nuevo

  const VehicleFormPage({super.key, this.vehicle});

  @override
  State<VehicleFormPage> createState() => _VehicleFormPageState();
}

class _VehicleFormPageState extends State<VehicleFormPage> {
  final _formKey = GlobalKey<FormState>();
  final VehicleService _vehicleService = VehicleService();

  // Controllers
  late TextEditingController _nameController;
  late TextEditingController _yearController;
  late TextEditingController _batteryCapacityController;
  late TextEditingController _currentBatteryController;
  late TextEditingController _rangeController;
  late TextEditingController _maxPowerController;

  // Valores seleccionados
  String? _selectedBrand;
  String? _selectedModel;
  Set<String> _selectedConnectors = {};

  bool _isSaving = false;

  bool get isEditing => widget.vehicle != null;

  // Marcas y modelos populares de EVs
  static const Map<String, List<String>> _brandsAndModels = {
    'Tesla': ['Model 3', 'Model Y', 'Model S', 'Model X', 'Cybertruck'],
    'BYD': ['Dolphin', 'Seal', 'Atto 3', 'Han', 'Tang'],
    'Chevrolet': ['Bolt EV', 'Bolt EUV', 'Equinox EV', 'Blazer EV'],
    'Nissan': ['Leaf', 'Ariya'],
    'Hyundai': ['Ioniq 5', 'Ioniq 6', 'Kona Electric'],
    'Kia': ['EV6', 'EV9', 'Niro EV'],
    'Ford': ['Mustang Mach-E', 'F-150 Lightning'],
    'Volkswagen': ['ID.4', 'ID.3', 'ID.Buzz'],
    'BMW': ['i4', 'iX', 'iX3', 'i7'],
    'Mercedes-Benz': ['EQS', 'EQE', 'EQB', 'EQA'],
    'Audi': ['e-tron', 'e-tron GT', 'Q4 e-tron', 'Q8 e-tron'],
    'Porsche': ['Taycan'],
    'Rivian': ['R1T', 'R1S'],
    'Renault': ['Zoe', 'Megane E-Tech'],
    'Peugeot': ['e-208', 'e-2008', 'e-308'],
    'Otro': ['Otro modelo'],
  };

  // Tipos de conectores
  static const List<Map<String, String>> _connectorTypes = [
    {'id': 'ccs2', 'name': 'CCS2 (Combo 2)', 'desc': 'Carga rápida DC'},
    {'id': 'ccs1', 'name': 'CCS1 (Combo 1)', 'desc': 'Carga rápida DC (US)'},
    {'id': 'chademo', 'name': 'CHAdeMO', 'desc': 'Carga rápida DC (Japón)'},
    {'id': 'type2', 'name': 'Type 2', 'desc': 'Carga AC estándar EU'},
    {'id': 'type1', 'name': 'Type 1 (J1772)', 'desc': 'Carga AC estándar US'},
    {'id': 'tesla', 'name': 'Tesla Supercharger', 'desc': 'Exclusivo Tesla'},
    {'id': 'nacs', 'name': 'NACS', 'desc': 'Nuevo estándar Tesla'},
  ];

  @override
  void initState() {
    super.initState();
    _initializeControllers();
  }

  void _initializeControllers() {
    final v = widget.vehicle;
    _nameController = TextEditingController(text: v?.name ?? '');
    _yearController = TextEditingController(text: v?.year.toString() ?? DateTime.now().year.toString());
    _batteryCapacityController = TextEditingController(text: v?.batteryCapacityKwh.toStringAsFixed(0) ?? '');
    _currentBatteryController = TextEditingController(text: v?.currentBatteryPercent.toStringAsFixed(0) ?? '100');
    _rangeController = TextEditingController(text: v?.estimatedRangeKm?.toStringAsFixed(0) ?? '');
    _maxPowerController = TextEditingController(text: v?.maxChargingPowerKw?.toStringAsFixed(0) ?? '');

    if (v != null) {
      _selectedBrand = v.brand;
      _selectedModel = v.model;
      _selectedConnectors = v.compatibleConnectors.toSet();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _yearController.dispose();
    _batteryCapacityController.dispose();
    _currentBatteryController.dispose();
    _rangeController.dispose();
    _maxPowerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Editar Vehículo' : 'Agregar Vehículo'),
        actions: [
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildBasicInfoSection(),
            const SizedBox(height: 24),
            _buildBatterySection(),
            const SizedBox(height: 24),
            _buildConnectorsSection(),
            const SizedBox(height: 32),
            _buildSaveButton(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildBasicInfoSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.electric_car, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Información del Vehículo',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Nombre (apodo)
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nombre / Apodo (opcional)',
                hintText: 'Ej: Mi Tesla, Auto del trabajo',
                prefixIcon: Icon(Icons.label_outline),
              ),
            ),
            const SizedBox(height: 16),

            // Marca
            DropdownButtonFormField<String>(
              value: _selectedBrand,
              decoration: const InputDecoration(
                labelText: 'Marca *',
                prefixIcon: Icon(Icons.business),
              ),
              items: _brandsAndModels.keys.map((brand) {
                return DropdownMenuItem(value: brand, child: Text(brand));
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedBrand = value;
                  _selectedModel = null; // Reset model
                });
              },
              validator: (value) => value == null ? 'Selecciona una marca' : null,
            ),
            const SizedBox(height: 16),

            // Modelo
            DropdownButtonFormField<String>(
              value: _selectedModel,
              decoration: const InputDecoration(
                labelText: 'Modelo *',
                prefixIcon: Icon(Icons.directions_car),
              ),
              items: (_brandsAndModels[_selectedBrand] ?? []).map((model) {
                return DropdownMenuItem(value: model, child: Text(model));
              }).toList(),
              onChanged: _selectedBrand == null ? null : (value) {
                setState(() => _selectedModel = value);
              },
              validator: (value) => value == null ? 'Selecciona un modelo' : null,
            ),
            const SizedBox(height: 16),

            // Año
            TextFormField(
              controller: _yearController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Año *',
                prefixIcon: Icon(Icons.calendar_today),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Ingresa el año';
                final year = int.tryParse(value);
                if (year == null || year < 2010 || year > DateTime.now().year + 1) {
                  return 'Año inválido';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBatterySection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.battery_charging_full, color: AppColors.success),
                const SizedBox(width: 8),
                Text(
                  'Batería y Autonomía',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Capacidad de batería
            TextFormField(
              controller: _batteryCapacityController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Capacidad de batería (kWh) *',
                hintText: 'Ej: 60',
                prefixIcon: Icon(Icons.battery_full),
                suffixText: 'kWh',
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Ingresa la capacidad';
                final capacity = double.tryParse(value);
                if (capacity == null || capacity <= 0 || capacity > 300) {
                  return 'Capacidad inválida';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Nivel de batería actual
            TextFormField(
              controller: _currentBatteryController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Nivel de batería actual (%)',
                hintText: 'Ej: 80',
                prefixIcon: Icon(Icons.battery_std),
                suffixText: '%',
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return null;
                final percent = double.tryParse(value);
                if (percent == null || percent < 0 || percent > 100) {
                  return 'Porcentaje inválido (0-100)';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Autonomía estimada
            TextFormField(
              controller: _rangeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Autonomía estimada (km)',
                hintText: 'Ej: 400',
                prefixIcon: Icon(Icons.route),
                suffixText: 'km',
              ),
            ),
            const SizedBox(height: 16),

            // Potencia máxima de carga
            TextFormField(
              controller: _maxPowerController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Potencia máxima de carga (kW)',
                hintText: 'Ej: 150',
                prefixIcon: Icon(Icons.flash_on),
                suffixText: 'kW',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectorsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.power, color: AppColors.secondary),
                const SizedBox(width: 8),
                Text(
                  'Conectores Compatibles',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Selecciona los tipos de conector que soporta tu vehículo',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 16),
            
            ...List.generate(_connectorTypes.length, (index) {
              final connector = _connectorTypes[index];
              final isSelected = _selectedConnectors.contains(connector['id']);
              
              return CheckboxListTile(
                value: isSelected,
                title: Text(connector['name']!),
                subtitle: Text(
                  connector['desc']!,
                  style: const TextStyle(fontSize: 12),
                ),
                secondary: Icon(
                  Icons.power,
                  color: isSelected ? AppColors.primary : AppColors.textSecondary,
                ),
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      _selectedConnectors.add(connector['id']!);
                    } else {
                      _selectedConnectors.remove(connector['id']!);
                    }
                  });
                },
              );
            }),

            if (_selectedConnectors.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '* Selecciona al menos un conector',
                  style: TextStyle(color: AppColors.error, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return ElevatedButton(
      onPressed: _isSaving ? null : _saveVehicle,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      child: _isSaving
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(isEditing ? 'Guardar Cambios' : 'Agregar Vehículo'),
    );
  }

  Future<void> _saveVehicle() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_selectedConnectors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona al menos un conector')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final vehicle = Vehicle(
        id: widget.vehicle?.id ?? 'vehicle_${DateTime.now().millisecondsSinceEpoch}',
        name: _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
        brand: _selectedBrand!,
        model: _selectedModel!,
        year: int.parse(_yearController.text),
        batteryCapacityKwh: double.parse(_batteryCapacityController.text),
        currentBatteryPercent: double.tryParse(_currentBatteryController.text) ?? 100,
        estimatedRangeKm: double.tryParse(_rangeController.text),
        compatibleConnectors: _selectedConnectors.toList(),
        maxChargingPowerKw: double.tryParse(_maxPowerController.text),
        isPrimary: widget.vehicle?.isPrimary ?? false,
      );

      if (isEditing) {
        await _vehicleService.updateVehicle(vehicle);
      } else {
        await _vehicleService.addVehicle(vehicle);
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEditing ? 'Vehículo actualizado' : 'Vehículo agregado'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar vehículo'),
        content: Text('¿Deseas eliminar "${widget.vehicle?.displayName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _vehicleService.removeVehicle(widget.vehicle!.id);
              if (mounted) {
                Navigator.pop(context, true);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Vehículo eliminado')),
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}
