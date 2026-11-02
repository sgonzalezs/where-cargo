import 'package:flutter/material.dart';

import '../../domain/models/vehicle.dart';
import '../../domain/models/vehicle_catalog.dart' show VehicleCatalog;
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/services/vehicle_catalog_service.dart';
import '../../../../shared/services/vehicle_service.dart';
import '../widgets/vehicle_model_selector.dart';

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

  final _selectorKey = GlobalKey<VehicleModelSelectorState>();

  // Controllers
  late TextEditingController _nameController;
  late TextEditingController _yearController;

  VehicleCatalog? _catalog;

  bool _isSaving = false;

  bool get isEditing => widget.vehicle != null;

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    VehicleCatalogService().load().then((catalog) {
      if (mounted) setState(() => _catalog = catalog);
    });
  }

  void _initializeControllers() {
    final v = widget.vehicle;
    _nameController = TextEditingController(text: v?.name ?? '');
    _yearController = TextEditingController(
      text: v?.year.toString() ?? DateTime.now().year.toString(),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _yearController.dispose();
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
      body: _catalog == null
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              // Column y no ListView: el ListView destruye las secciones que
              // salen de pantalla y se perdería el estado del selector.
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildBasicInfoSection(),
                    const SizedBox(height: 32),
                    _buildSaveButton(),
                    const SizedBox(height: 16),
                  ],
                ),
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

            VehicleModelSelector(
              key: _selectorKey,
              catalog: _catalog!,
              initialVehicle: widget.vehicle,
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
                if (year == null ||
                    year < 2010 ||
                    year > DateTime.now().year + 1) {
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

    setState(() => _isSaving = true);

    try {
      final vehicle = _selectorKey.currentState!.buildVehicle(
        id:
            widget.vehicle?.id ??
            'vehicle_${DateTime.now().millisecondsSinceEpoch}',
        name: _nameController.text.trim().isEmpty
            ? null
            : _nameController.text.trim(),
        year: int.parse(_yearController.text),
        currentBatteryPercent: widget.vehicle?.currentBatteryPercent ?? 100,
        isPrimary: widget.vehicle?.isPrimary ?? false,
        createdAt: widget.vehicle?.createdAt,
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
            content: Text(
              isEditing ? 'Vehículo actualizado' : 'Vehículo agregado',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar vehículo'),
        content: Text('¿Deseas eliminar "${widget.vehicle?.displayName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _vehicleService.removeVehicle(widget.vehicle!.id);
              // Usar el context de la página: el del diálogo ya se cerró
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
