import 'package:flutter/material.dart';

import '../../domain/enums/charging_enums.dart';
import '../../domain/models/charging_station.dart';
import '../../../../core/theme/app_colors.dart';

/// Card para mostrar información resumida de una estación
class StationCard extends StatelessWidget {
  final ChargingStation station;
  final VoidCallback? onTap;
  final VoidCallback? onFavoriteTap;
  final bool isFavorite;

  const StationCard({
    super.key,
    required this.station,
    this.onTap,
    this.onFavoriteTap,
    this.isFavorite = false,
  });

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
              const SizedBox(height: 12),
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

  Widget _buildAddress(BuildContext context) {
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
            '${station.address}, ${station.city}',
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
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
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
