import 'package:flutter/material.dart';

import '../../domain/enums/charging_enums.dart';
import '../../domain/models/charging_station.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/services/address_resolver_service.dart';

/// Card para mostrar información resumida de una estación
class StationCard extends StatefulWidget {
  final ChargingStation station;
  final VoidCallback? onTap;
  final VoidCallback? onFavoriteTap;
  final bool isFavorite;
  final bool compatibleWithVehicle;

  const StationCard({
    super.key,
    required this.station,
    this.onTap,
    this.onFavoriteTap,
    this.isFavorite = false,
    this.compatibleWithVehicle = false,
  });

  @override
  State<StationCard> createState() => _StationCardState();
}

class _StationCardState extends State<StationCard> {
  String? _resolvedAddress;
  bool _addressResolved = false; // true cuando la resolución terminó (con o sin resultado)

  ChargingStation get station => widget.station;
  bool get isFavorite => widget.isFavorite;
  bool get compatibleWithVehicle => widget.compatibleWithVehicle;
  VoidCallback? get onTap => widget.onTap;
  VoidCallback? get onFavoriteTap => widget.onFavoriteTap;

  @override
  void initState() {
    super.initState();
    _resolveAddressIfNeeded();
  }

  @override
  void didUpdateWidget(StationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.station.id != widget.station.id) {
      _resolvedAddress = null;
      _resolveAddressIfNeeded();
    }
  }

  Future<void> _resolveAddressIfNeeded() async {
    final resolved = await AddressResolverService().resolve(
      stationId: station.id,
      latitude: station.latitude,
      longitude: station.longitude,
      currentAddress: station.address,
    );
    if (mounted) {
      setState(() {
        _resolvedAddress = resolved;
        _addressResolved = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              const SizedBox(height: 12),
              _buildAddress(context),
              if (_addressDisplayText != null) const SizedBox(height: 12),
              _buildConnectorInfo(context),
              const SizedBox(height: 12),
              _buildFooter(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                station.name,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (station.networkName != null) ...[
                const SizedBox(height: 2),
                Text(
                  station.networkName!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
              if (!station.hasCompleteData) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: Colors.amber.shade700, width: 0.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.info_outline,
                          size: 11, color: Colors.amber.shade800),
                      const SizedBox(width: 3),
                      Text(
                        'Datos limitados',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.amber.shade900,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        _buildStatusBadge(context),
        if (onFavoriteTap != null) ...[
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              isFavorite ? Icons.favorite : Icons.favorite_border,
              color: isFavorite ? Colors.red : AppColors.textSecondary,
            ),
            onPressed: onFavoriteTap,
            constraints: const BoxConstraints(),
            padding: EdgeInsets.zero,
          ),
        ],
      ],
    );
  }

  Widget _buildStatusBadge(BuildContext context) {
    final color = _getStatusColor();
    final text = station.hasAvailableConnectors
        ? station.availabilityText
        : station.status.displayName;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Color _getStatusColor() {
    if (station.hasAvailableConnectors) {
      return AppColors.stationAvailable;
    }
    switch (station.status) {
      case StationStatus.available:
        return AppColors.stationAvailable;
      case StationStatus.occupied:
        return AppColors.stationOccupied;
      case StationStatus.offline:
        return AppColors.stationOffline;
      case StationStatus.maintenance:
        return AppColors.stationMaintenance;
      case StationStatus.unknown:
        return AppColors.textSecondary;
    }
  }

  static const String _unavailable = 'Dirección no disponible';

  /// La dirección que se muestra: preferencia al resultado resuelto,
  /// luego a la dirección original si es válida, null si no hay nada útil.
  String? get _addressDisplayText {
    // Mientras se resuelve y la dirección original es inválida — no mostrar nada
    final original = station.address;
    final hasValidOriginal =
        original.isNotEmpty && original != _unavailable;

    if (_resolvedAddress != null) return _resolvedAddress;
    if (!_addressResolved && !hasValidOriginal) return null; // cargando
    if (hasValidOriginal) return original;
    if (_addressResolved && _resolvedAddress == null) return null; // sin resultado
    return null;
  }

  Widget _buildAddress(BuildContext context) {
    final text = _addressDisplayText;
    if (text == null) {
      // Mientras resuelve: solo mostrar la distancia si la hay
      if (station.distanceKm == null) return const SizedBox.shrink();
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const Icon(Icons.location_on_outlined,
              size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            _formatDistance(station.distanceKm!),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      );
    }
    return Row(
      children: [
        const Icon(
          Icons.location_on_outlined,
          size: 16,
          color: AppColors.textSecondary,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            station.city.isNotEmpty ? '$text, ${station.city}' : text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (station.distanceKm != null) ...[
          const SizedBox(width: 8),
          Text(
            _formatDistance(station.distanceKm!),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ],
    );
  }

  String _formatDistance(double km) {
    if (km < 1) {
      return '${(km * 1000).round()} m';
    }
    return '${km.toStringAsFixed(1)} km';
  }

  Widget _buildConnectorInfo(BuildContext context) {
    // Si la estación no tiene datos verificados de conectores, no mostramos
    // chips con "0 kW" ni "Conector no especificado" — sería ruido.
    if (!station.hasCompleteData) {
      return _buildInfoChip(
        context,
        icon: Icons.help_outline,
        label: 'Conectores sin verificar',
        color: Colors.amber.shade800,
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (compatibleWithVehicle)
          _buildInfoChip(
            context,
            icon: Icons.star,
            label: 'Compatible con tu vehículo',
            color: const Color(0xFFFFB300),
          ),
        _buildInfoChip(
          context,
          icon: Icons.electrical_services,
          label: '${station.maxPowerKw.toStringAsFixed(0)} kW',
          color: AppColors.secondary,
        ),
        ...station.connectorTypes.take(3).map(
              (type) => _buildInfoChip(
                context,
                icon: Icons.power,
                label: type.displayName,
                color: _getConnectorColor(type),
              ),
            ),
        if (station.isFree)
          _buildInfoChip(
            context,
            icon: Icons.money_off,
            label: 'Gratis',
            color: AppColors.success,
          ),
      ],
    );
  }

  Widget _buildInfoChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Color _getConnectorColor(ConnectorType type) {
    switch (type) {
      case ConnectorType.type1:
        return AppColors.connectorType1;
      case ConnectorType.type2:
        return AppColors.connectorType2;
      case ConnectorType.ccs1:
      case ConnectorType.ccs2:
        return AppColors.connectorCCS;
      case ConnectorType.chademo:
        return AppColors.connectorCHAdeMO;
      case ConnectorType.tesla:
      case ConnectorType.teslaDestination:
        return AppColors.connectorTesla;
      default:
        return AppColors.textSecondary;
    }
  }

  Widget _buildFooter(BuildContext context) {
    return Row(
      children: [
        if (station.rating != null) ...[
          const Icon(Icons.star, size: 16, color: Colors.amber),
          const SizedBox(width: 4),
          Text(
            station.rating!.toStringAsFixed(1),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          if (station.reviewCount != null) ...[
            Text(
              ' (${station.reviewCount})',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
          const SizedBox(width: 16),
        ],
        Icon(
          station.isOpen ? Icons.access_time : Icons.access_time_filled,
          size: 16,
          color: station.isOpen ? AppColors.success : AppColors.error,
        ),
        const SizedBox(width: 4),
        Text(
          station.operatingSchedule?.is24x7 == true
              ? '24/7'
              : (station.isOpen ? 'Abierto' : 'Cerrado'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: station.isOpen ? AppColors.success : AppColors.error,
                fontWeight: FontWeight.w500,
              ),
        ),
        const Spacer(),
        Icon(
          Icons.chevron_right,
          color: AppColors.textSecondary,
        ),
      ],
    );
  }
}
