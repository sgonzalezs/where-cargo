import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/models/vehicle.dart';
import '../../domain/models/vehicle_catalog.dart';

/// Selector de marca → modelo → versión desde el catálogo, con la opción
/// "Otra marca"/"Otro modelo" para escribir las especificaciones a mano.
///
/// Debe ir dentro de un [Form]. El vehículo se arma con
/// [VehicleModelSelectorState.buildVehicle] usando un `GlobalKey`.
class VehicleModelSelector extends StatefulWidget {
  final VehicleCatalog catalog;
  final Vehicle? initialVehicle;

  /// Se llama al elegir una versión del catálogo (null al pasar a un modelo
  /// personalizado), para precargar sus conectores.
  final ValueChanged<VehicleVariant?>? onVariantChanged;

  const VehicleModelSelector({
    super.key,
    required this.catalog,
    this.initialVehicle,
    this.onVariantChanged,
  });

  @override
  State<VehicleModelSelector> createState() => VehicleModelSelectorState();
}

class VehicleModelSelectorState extends State<VehicleModelSelector> {
  static const String _other = '__other__';

  String? _brandId;
  String? _modelId;
  String? _variantId;

  final _customBrand = TextEditingController();
  final _customModel = TextEditingController();
  final _battery = TextEditingController();
  final _range = TextEditingController();
  final _maxPower = TextEditingController();

  VehicleCatalog get _catalog => widget.catalog;

  bool get _isCustom => _brandId == _other || _modelId == _other;

  VehicleModel? get _model =>
      _isCustom || _modelId == null ? null : _catalog.modelById(_modelId!);

  VehicleVariant? get _variant =>
      _variantId == null ? null : _model?.variantById(_variantId!);

  @override
  void initState() {
    super.initState();
    final v = widget.initialVehicle;
    if (v == null) return;
    final model = v.modelId == null ? null : _catalog.modelById(v.modelId!);
    if (model != null && model.variantById(v.variantId ?? '') != null) {
      _brandId = model.brandId;
      _modelId = model.id;
      _variantId = v.variantId;
      return;
    }
    // Vehículo personalizado: conserva la marca si existe en el catálogo
    final brand = _catalog.brands
        .where((b) => b.name.toLowerCase() == v.brand.toLowerCase())
        .firstOrNull;
    _brandId = brand?.id ?? _other;
    _modelId = _other;
    _customBrand.text = v.brand;
    _customModel.text = v.model;
    _battery.text = _format(v.batteryCapacityKwh);
    _range.text = _format(v.estimatedRangeKm);
    _maxPower.text = _format(v.maxChargingPowerKw);
  }

  static String _format(double? value) {
    if (value == null) return '';
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  @override
  void dispose() {
    _customBrand.dispose();
    _customModel.dispose();
    _battery.dispose();
    _range.dispose();
    _maxPower.dispose();
    super.dispose();
  }

  void _selectBrand(String? brandId) {
    setState(() {
      _brandId = brandId;
      _modelId = brandId == _other ? _other : null;
      _variantId = null;
    });
    widget.onVariantChanged?.call(null);
  }

  void _selectModel(String? modelId) {
    final model = modelId == null || modelId == _other
        ? null
        : _catalog.modelById(modelId);
    setState(() {
      _modelId = modelId;
      _variantId = model != null && model.variants.length == 1
          ? model.variants.first.id
          : null;
    });
    widget.onVariantChanged?.call(_variant);
  }

  void _selectVariant(String? variantId) {
    setState(() => _variantId = variantId);
    widget.onVariantChanged?.call(_variant);
  }

  /// Arma el vehículo con la selección actual. Llamar solo después de
  /// validar el formulario.
  Vehicle buildVehicle({
    required String id,
    String? name,
    required int year,
    required double currentBatteryPercent,
    required List<String> connectors,
    bool isPrimary = false,
    DateTime? createdAt,
  }) {
    final model = _model;
    final variant = _variant;
    if (model != null && variant != null) {
      return Vehicle.fromCatalog(
        id: id,
        name: name,
        brand: _catalog.brandById(model.brandId)!,
        model: model,
        variant: variant,
        year: year,
        currentBatteryPercent: currentBatteryPercent,
        connectors: connectors,
        isPrimary: isPrimary,
        createdAt: createdAt,
      );
    }
    final brand = _brandId == _other ? null : _catalog.brandById(_brandId!);
    return Vehicle(
      id: id,
      name: name,
      brand: brand?.name ?? _customBrand.text.trim(),
      model: _customModel.text.trim(),
      year: year,
      batteryCapacityKwh: double.parse(_battery.text.replaceAll(',', '.')),
      currentBatteryPercent: currentBatteryPercent,
      estimatedRangeKm: double.tryParse(_range.text),
      compatibleConnectors: connectors,
      maxChargingPowerKw: double.tryParse(_maxPower.text),
      isPrimary: isPrimary,
      createdAt: createdAt,
    );
  }

  @override
  Widget build(BuildContext context) {
    final brands = [..._catalog.brands]..sort((a, b) => a.name.compareTo(b.name));
    final models = _brandId == null || _brandId == _other
        ? <VehicleModel>[]
        : _catalog.modelsOf(_brandId!);
    final model = _model;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _brandId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Marca *',
            prefixIcon: Icon(Icons.business),
          ),
          items: [
            for (final brand in brands)
              DropdownMenuItem(value: brand.id, child: Text(brand.name)),
            const DropdownMenuItem(value: _other, child: Text('Otra marca')),
          ],
          onChanged: _selectBrand,
          validator: (value) => value == null ? 'Selecciona una marca' : null,
        ),
        if (_brandId == _other) ...[
          const SizedBox(height: 16),
          _textField(_customBrand, 'Marca *', Icons.edit, required: true),
        ],
        if (_brandId != null && _brandId != _other) ...[
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            // La key fuerza a reiniciar el valor al cambiar de marca
            key: ValueKey('model_$_brandId'),
            initialValue: _modelId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Modelo *',
              prefixIcon: Icon(Icons.directions_car),
            ),
            items: [
              for (final m in models)
                DropdownMenuItem(value: m.id, child: Text(m.name)),
              const DropdownMenuItem(value: _other, child: Text('Otro modelo')),
            ],
            onChanged: _selectModel,
            validator: (value) => value == null ? 'Selecciona un modelo' : null,
          ),
        ],
        if (_isCustom) ...[
          const SizedBox(height: 16),
          _textField(_customModel, 'Modelo *', Icons.directions_car,
              required: true),
        ],
        if (model != null && model.variants.length > 1) ...[
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey('variant_$_modelId'),
            initialValue: _variantId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Versión *',
              prefixIcon: Icon(Icons.tune),
            ),
            items: [
              for (final v in model.variants)
                DropdownMenuItem(value: v.id, child: Text(v.name)),
            ],
            onChanged: _selectVariant,
            validator: (value) => value == null ? 'Selecciona la versión' : null,
          ),
        ],
        if (_variant != null) ...[
          const SizedBox(height: 16),
          _VariantSpecs(variant: _variant!),
        ],
        if (_isCustom) ..._buildCustomSpecs(),
      ],
    );
  }

  List<Widget> _buildCustomSpecs() {
    return [
      const SizedBox(height: 16),
      _textField(
        _battery,
        'Capacidad de batería (kWh) *',
        Icons.battery_full,
        suffix: 'kWh',
        decimal: true,
        validator: (value) {
          final capacity = double.tryParse((value ?? '').replaceAll(',', '.'));
          if (capacity == null || capacity <= 0 || capacity > 300) {
            return 'Capacidad inválida';
          }
          return null;
        },
      ),
      const SizedBox(height: 16),
      _textField(
        _range,
        'Autonomía con carga completa (km)',
        Icons.route,
        suffix: 'km',
        validator: (value) {
          if (value == null || value.isEmpty) return null;
          final range = int.tryParse(value);
          return range == null || range <= 0 || range > 2000
              ? 'Autonomía inválida'
              : null;
        },
      ),
      const SizedBox(height: 16),
      _textField(
        _maxPower,
        'Potencia máxima de carga DC (kW)',
        Icons.flash_on,
        suffix: 'kW',
        validator: (value) {
          if (value == null || value.isEmpty) return null;
          final power = int.tryParse(value);
          return power == null || power <= 0 || power > 500
              ? 'Potencia inválida'
              : null;
        },
      ),
    ];
  }

  Widget _textField(
    TextEditingController controller,
    String label,
    IconData icon, {
    String? suffix,
    bool decimal = false,
    bool required = false,
    FormFieldValidator<String>? validator,
  }) {
    final isNumber = suffix != null;
    return TextFormField(
      controller: controller,
      keyboardType: isNumber
          ? TextInputType.numberWithOptions(decimal: decimal)
          : TextInputType.text,
      textCapitalization:
          isNumber ? TextCapitalization.none : TextCapitalization.words,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixText: suffix,
      ),
      validator: validator ??
          (required
              ? (value) => (value == null || value.trim().isEmpty)
                  ? 'Campo obligatorio'
                  : null
              : null),
    );
  }
}

/// Resumen de las especificaciones de la versión elegida.
class _VariantSpecs extends StatelessWidget {
  final VehicleVariant variant;

  const _VariantSpecs({required this.variant});

  @override
  Widget build(BuildContext context) {
    String fmt(double v) =>
        v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _spec(Icons.battery_full, '${fmt(variant.batteryKwh)} kWh'),
              _spec(Icons.route, '${fmt(variant.rangeKm)} km'),
              _spec(Icons.flash_on, 'DC ${fmt(variant.maxDcKw)} kW'),
              _spec(Icons.power, 'AC ${fmt(variant.maxAcKw)} kW'),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Datos de referencia del fabricante.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _spec(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}
