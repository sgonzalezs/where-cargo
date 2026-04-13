import 'package:flutter/material.dart';

import '../../domain/enums/charging_enums.dart';
import '../../domain/models/charging_station.dart';
import '../../data/repositories/charging_stations_repository.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/services/favorites_service.dart';
import '../../../navigation_apps/presentation/widgets/navigation_options_sheet.dart';

/// Página de detalle de una estación de carga
class StationDetailPage extends StatefulWidget {
  final ChargingStation station;

  const StationDetailPage({
    super.key,
    required this.station,
  });

  @override
  State<StationDetailPage> createState() => _StationDetailPageState();
}

class _StationDetailPageState extends State<StationDetailPage> {
  final FavoritesService _favoritesService = FavoritesService();
  final ChargingStationsRepository _repository = ChargingStationsRepository();

  late ChargingStation _station;
  bool _isRefreshing = false;
  DateTime? _lastRefreshed;

  @override
  void initState() {
    super.initState();
    _station = widget.station;
    _favoritesService.addListener(_onFavoritesChanged);
    _favoritesService.loadFavorites();
    _refreshStationData();
  }

  @override
  void dispose() {
    _favoritesService.removeListener(_onFavoritesChanged);
    super.dispose();
  }

  void _onFavoritesChanged() {
    if (mounted) setState(() {});
  }

  /// Refresca los datos de la estación desde la API
  Future<void> _refreshStationData() async {
    if (_isRefreshing) return;
    
    setState(() => _isRefreshing = true);
    
    try {
      final refreshed = await _repository.refreshStation(_station);
      if (mounted && refreshed != null) {
        setState(() {
          _station = refreshed;
          _lastRefreshed = DateTime.now();
        });
      }
    } catch (e) {
      // Silenciosamente manejar el error, mantener datos originales
      debugPrint('Error refrescando estación: $e');
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  ChargingStation get station => _station;

  void _toggleFavorite() async {
    final wasAdded = await _favoritesService.toggleFavorite(_station);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasAdded
                ? '${_station.name} agregado a favoritos'
                : '${_station.name} eliminado de favoritos',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                const Divider(),
                _buildConnectorsSection(context),
                const Divider(),
                _buildLocationSection(context),
                const Divider(),
                _buildScheduleSection(context),
                if (station.amenities != null &&
                    station.amenities!.isNotEmpty) ...[
                  const Divider(),
                  _buildAmenitiesSection(context),
                ],
                const SizedBox(height: 100), // Espacio para el botón flotante
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _buildActionButtons(context),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: station.images?.isNotEmpty == true ? 200 : 0,
      pinned: true,
      flexibleSpace: FlexibleSpaceBar(
        title: Text(
          station.name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(color: Colors.black54, blurRadius: 4),
            ],
          ),
        ),
        background: station.images?.isNotEmpty == true
            ? Image.network(
                station.images!.first,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: AppColors.primary,
                  child: const Icon(
                    Icons.ev_station,
                    size: 80,
                    color: Colors.white54,
                  ),
                ),
              )
            : Container(
                color: AppColors.primary,
                child: const Icon(
                  Icons.ev_station,
                  size: 80,
                  color: Colors.white54,
                ),
              ),
      ),
      actions: [
        IconButton(
          icon: Icon(
            _favoritesService.isFavorite(station.id)
                ? Icons.favorite
                : Icons.favorite_border,
            color: _favoritesService.isFavorite(station.id)
                ? Colors.red
                : null,
          ),
          onPressed: _toggleFavorite,
        ),
        IconButton(
          icon: const Icon(Icons.share),
          onPressed: () {
            // TODO: Implementar compartir
          },
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner de estado de actualización
          _buildRefreshStatusBanner(),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildStatusBadge(context),
              const SizedBox(width: 8),
              if (station.isFree)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success.withAlpha(25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Gratis',
                    style: TextStyle(
                      color: AppColors.success,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const Spacer(),
              if (station.rating != null)
                Row(
                  children: [
                    const Icon(Icons.star, color: Colors.amber),
                    const SizedBox(width: 4),
                    Text(
                      station.rating!.toStringAsFixed(1),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    if (station.reviewCount != null)
                      Text(
                        ' (${station.reviewCount} reseñas)',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (station.networkName != null) ...[
            Text(
              'Red: ${station.networkName}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 8),
          ],
          if (station.description != null) ...[
            Text(
              station.description!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRefreshStatusBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _isRefreshing 
            ? AppColors.primary.withAlpha(25) 
            : AppColors.success.withAlpha(25),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          if (_isRefreshing) ...[
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            const Text(
              'Verificando disponibilidad...',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ] else ...[
            Icon(
              Icons.check_circle,
              size: 16,
              color: AppColors.success,
            ),
            const SizedBox(width: 8),
            Text(
              _getLastUpdateText(),
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const Spacer(),
            GestureDetector(
              onTap: _refreshStationData,
              child: const Icon(
                Icons.refresh,
                size: 18,
                color: AppColors.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getLastUpdateText() {
    if (_lastRefreshed != null) {
      return 'Verificado hace ${_formatTimeDifference(_lastRefreshed!)}';
    }
    if (station.lastUpdated != null) {
      return 'Última actualización: ${_formatDate(station.lastUpdated!)}';
    }
    return 'Datos verificados';
  }

  String _formatTimeDifference(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'unos segundos';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays} días';
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inDays == 0) return 'hoy';
    if (diff.inDays == 1) return 'ayer';
    if (diff.inDays < 7) return 'hace ${diff.inDays} días';
    if (diff.inDays < 30) return 'hace ${(diff.inDays / 7).floor()} semanas';
    return 'hace ${(diff.inDays / 30).floor()} meses';
  }

  Widget _buildStatusBadge(BuildContext context) {
    // Determinar color y texto basado en el estado
    final Color color;
    final String statusText;
    final IconData statusIcon;
    
    if (station.status == StationStatus.offline) {
      color = AppColors.error;
      statusText = 'Fuera de servicio';
      statusIcon = Icons.power_off;
    } else if (station.hasAvailableConnectors) {
      color = AppColors.stationAvailable;
      statusText = station.availabilityText;
      statusIcon = Icons.check_circle;
    } else {
      color = AppColors.stationOccupied;
      statusText = station.availabilityText;
      statusIcon = Icons.access_time;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            statusText,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectorsSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Conectores',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          ...station.connectors.map(
            (connector) => _buildConnectorTile(context, connector),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectorTile(BuildContext context, connector) {
    final isAvailable = connector.status == ConnectorStatus.available;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isAvailable
            ? AppColors.stationAvailable.withOpacity(0.05)
            : Colors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isAvailable ? AppColors.stationAvailable : Colors.grey,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isAvailable
                  ? AppColors.stationAvailable.withOpacity(0.1)
                  : Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.power,
              color: isAvailable ? AppColors.stationAvailable : Colors.grey,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connector.type.displayName,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Text(
                  '${connector.powerKw.toStringAsFixed(0)} kW • ${connector.chargingType.displayName}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                connector.status.displayName,
                style: TextStyle(
                  color: isAvailable ? AppColors.stationAvailable : Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (connector.pricePerKwh != null)
                Text(
                  '\$${connector.pricePerKwh?.toStringAsFixed(0)}/kWh',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ubicación',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.location_on, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(station.address),
                    Text(
                      '${station.city}, ${station.country}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (station.distanceKm != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.directions_car, color: AppColors.secondary),
                const SizedBox(width: 8),
                Text(
                  'A ${station.distanceKm!.toStringAsFixed(1)} km de tu ubicación',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ],
          // TODO: Agregar mapa pequeño aquí
        ],
      ),
    );
  }

  Widget _buildScheduleSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Horario',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: station.isOpen
                      ? AppColors.success.withOpacity(0.1)
                      : AppColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  station.isOpen ? 'Abierto ahora' : 'Cerrado',
                  style: TextStyle(
                    color: station.isOpen ? AppColors.success : AppColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (station.operatingSchedule?.is24x7 == true)
            const Row(
              children: [
                Icon(Icons.access_time, color: AppColors.success),
                SizedBox(width: 8),
                Text('Abierto 24 horas, 7 días a la semana'),
              ],
            )
          else if (station.operatingSchedule != null)
            ...station.operatingSchedule!.hours.map(
              (hours) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 80,
                      child: Text(
                        hours.dayName,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                    Text(
                      hours.displayHours,
                      style: TextStyle(
                        color: hours.isClosed
                            ? AppColors.error
                            : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAmenitiesSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Servicios',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: station.amenities!
                .map((amenity) => Chip(
                      label: Text(amenity),
                      backgroundColor: AppColors.surface,
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _showNavigationOptions(context),
              icon: const Icon(Icons.directions),
              label: const Text('Navegar'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: () {
              // TODO: Implementar llamada
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.surface,
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            ),
            child: const Icon(Icons.phone),
          ),
        ],
      ),
    );
  }

  void _showNavigationOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => NavigationOptionsSheet(
        destinationLat: station.latitude,
        destinationLng: station.longitude,
        destinationName: station.name,
      ),
    );
  }
}
