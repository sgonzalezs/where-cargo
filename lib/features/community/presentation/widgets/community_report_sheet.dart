import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/services/community_service.dart';
import '../../../../shared/services/vehicle_service.dart';
import '../../../charging_stations/domain/enums/charging_enums.dart';
import '../../../charging_stations/domain/models/charging_station.dart';
import '../../domain/models/community_station.dart';

/// Hoja para reportar el estado de una estación. Se abre solo cuando ya se
/// verificó la sesión y la cercanía a la estación.
class CommunityReportSheet extends StatefulWidget {
  final ChargingStation station;

  const CommunityReportSheet({super.key, required this.station});

  /// Devuelve true si se envió el reporte.
  static Future<bool> show(
    BuildContext context,
    ChargingStation station,
  ) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => CommunityReportSheet(station: station),
    );
    return sent ?? false;
  }

  @override
  State<CommunityReportSheet> createState() => _CommunityReportSheetState();
}

class _CommunityReportSheetState extends State<CommunityReportSheet> {
  /// Tipos que se pueden reportar, en el orden en que se muestran.
  static const List<ConnectorType> _types = [
    ConnectorType.ccs2,
    ConnectorType.type2,
    ConnectorType.gbtDc,
    ConnectorType.gbtAc,
    ConnectorType.chademo,
    ConnectorType.ccs1,
    ConnectorType.type1,
    ConnectorType.tesla,
  ];

  CommunityStatus? _status;
  final Map<ConnectorType, CommunityPowerLevel> _connectors = {};
  final Set<CommunityTag> _tags = {};
  bool? _isFree;
  final _price = TextEditingController();
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    // Preselecciona el conector del vehículo que la estación tenga (o, si la
    // estación no tiene datos, los del vehículo)
    final vehicle = VehicleService().primaryVehicle;
    final stationTypes = widget.station.connectorTypes;
    for (final id in vehicle?.compatibleConnectors ?? const <String>[]) {
      final type = ConnectorType.fromString(id);
      if (!_types.contains(type)) continue;
      if (stationTypes.contains(type) || !widget.station.hasCompleteData) {
        _connectors[type] = _defaultPower(type);
      }
    }
  }

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  static List<CommunityPowerLevel> _levelsFor(ConnectorType type) {
    final isAc = const {
      ConnectorType.type1,
      ConnectorType.type2,
      ConnectorType.gbtAc,
    }.contains(type);
    final isDc = const {
      ConnectorType.ccs1,
      ConnectorType.ccs2,
      ConnectorType.chademo,
      ConnectorType.gbtDc,
    }.contains(type);
    return CommunityPowerLevel.values
        .where(
          (p) =>
              (!isAc || p.chargingType == ChargingType.ac) &&
              (!isDc || p.chargingType == ChargingType.dc),
        )
        .toList();
  }

  /// Potencia sugerida: la que informa la fuente para ese conector, o la
  /// más común.
  CommunityPowerLevel _defaultPower(ConnectorType type) {
    final levels = _levelsFor(type);
    final known = widget.station.connectors
        .where((c) => c.type == type && c.powerKw > 0)
        .map((c) => c.powerKw)
        .firstOrNull;
    if (known == null) {
      return levels.firstWhere(
        (p) => p == CommunityPowerLevel.ac7 || p == CommunityPowerLevel.dc60,
        orElse: () => levels.first,
      );
    }
    return levels.reduce(
      (a, b) =>
          (a.representativeKw - known).abs() <=
              (b.representativeKw - known).abs()
          ? a
          : b,
    );
  }

  Future<void> _send() async {
    final status = _status;
    if (status == null) return;
    setState(() => _isSending = true);
    try {
      await CommunityService().submitReport(
        widget.station,
        CommunityReport(
          status: status,
          connectors: {
            for (final e in _connectors.entries)
              CommunityConnector(e.key, e.value),
          },
          tags: _tags,
          isFree: _isFree,
          pricePerKwh: _isFree == false
              ? double.tryParse(_price.text.replaceAll('.', ''))
              : null,
          vehicleModelId: VehicleService().primaryVehicle?.modelId,
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } on CommunityException catch (e) {
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Reportar estado',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              widget.station.name,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),

            Text('¿Pudiste cargar? *', style: title),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _statusChip(
                  CommunityStatus.working,
                  Icons.check_circle,
                  AppColors.success,
                  'Sí, funciona',
                ),
                _statusChip(
                  CommunityStatus.partial,
                  Icons.warning_amber_rounded,
                  AppColors.warning,
                  'Parcialmente',
                ),
                _statusChip(
                  CommunityStatus.notWorking,
                  Icons.cancel,
                  AppColors.error,
                  'No funciona',
                ),
              ],
            ),
            const SizedBox(height: 20),

            Text('¿Qué conectores tiene?', style: title),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final type in _types)
                  FilterChip(
                    label: Text(type.displayName),
                    selected: _connectors.containsKey(type),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _connectors[type] = _defaultPower(type);
                      } else {
                        _connectors.remove(type);
                      }
                    }),
                  ),
              ],
            ),
            for (final type in _types.where(_connectors.containsKey)) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<CommunityPowerLevel>(
                initialValue: _connectors[type],
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Potencia ${type.displayName}',
                  prefixIcon: const Icon(Icons.flash_on),
                  isDense: true,
                ),
                items: [
                  for (final level in _levelsFor(type))
                    DropdownMenuItem(value: level, child: Text(level.label)),
                ],
                onChanged: (level) {
                  if (level != null) setState(() => _connectors[type] = level);
                },
              ),
            ],
            const SizedBox(height: 20),

            Text('Detalles (opcional)', style: title),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in CommunityTag.values)
                  FilterChip(
                    label: Text(tag.label),
                    selected: _tags.contains(tag),
                    onSelected: (selected) => setState(() {
                      selected ? _tags.add(tag) : _tags.remove(tag);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 20),

            Text('¿Es gratis?', style: title),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Gratis'),
                  selected: _isFree == true,
                  onSelected: (s) => setState(() => _isFree = s ? true : null),
                ),
                ChoiceChip(
                  label: const Text('De pago'),
                  selected: _isFree == false,
                  onSelected: (s) => setState(() => _isFree = s ? false : null),
                ),
              ],
            ),
            if (_isFree == false) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _price,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                decoration: const InputDecoration(
                  labelText: 'Precio por kWh (opcional)',
                  prefixText: '\$ ',
                  suffixText: 'COP/kWh',
                  isDense: true,
                ),
              ),
            ],
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _status == null || _isSending ? null : _send,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _isSending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Enviar reporte'),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tu reporte es anónimo para los demás conductores.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(
    CommunityStatus status,
    IconData icon,
    Color color,
    String label,
  ) {
    final selected = _status == status;
    return ChoiceChip(
      avatar: Icon(icon, size: 18, color: selected ? Colors.white : color),
      label: Text(label),
      selected: selected,
      selectedColor: color,
      labelStyle: TextStyle(color: selected ? Colors.white : null),
      showCheckmark: false,
      onSelected: (_) => setState(() => _status = status),
    );
  }
}
