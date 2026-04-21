import 'package:flutter/material.dart';

import '../../domain/models/charging_station.dart';
import '../../domain/enums/charging_enums.dart';
import '../../data/repositories/charging_stations_repository.dart';
import '../widgets/station_card.dart';
import 'station_detail_page.dart';
import '../../../filters/domain/models/station_filters.dart';
import '../../../filters/presentation/widgets/filter_sheet.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/services/location_service.dart';
import '../../../../shared/services/favorites_service.dart';

/// Página con lista de estaciones de carga
class StationsListPage extends StatefulWidget {
  const StationsListPage({super.key});

  @override
  State<StationsListPage> createState() => _StationsListPageState();
}

class _StationsListPageState extends State<StationsListPage> {
  final TextEditingController _searchController = TextEditingController();
  final ChargingStationsRepository _repository = ChargingStationsRepository();
  final LocationService _locationService = LocationService();
  final FavoritesService _favoritesService = FavoritesService();

  bool _isLoading = false;
  List<ChargingStation> _allStations = [];
  List<ChargingStation> _filteredStations = [];
  String? _errorMessage;
  StationFilters _filters = const StationFilters();

  @override
  void initState() {
    super.initState();
    _locationService.addListener(_onLocationChanged);
    _favoritesService.addListener(_onFavoritesChanged);
    _favoritesService.loadFavorites();
    _loadStations();
  }

  @override
  void dispose() {
    _locationService.removeListener(_onLocationChanged);
    _favoritesService.removeListener(_onFavoritesChanged);
    _searchController.dispose();
    _repository.dispose();
    super.dispose();
  }

  void _onFavoritesChanged() {
    if (mounted) setState(() {});
  }

  void _onLocationChanged() {
    // Cuando la ubicación cambia (por ejemplo desde el mapa), recargar
    if (mounted) {
      _recalculateDistancesAndReload();
    }
  }

  Future<void> _recalculateDistancesAndReload() async {
    final lat = _locationService.latitude;
    final lng = _locationService.longitude;

    if (_allStations.isNotEmpty) {
      final updatedStations = _repository.recalculateDistancesFrom(
        stations: _allStations,
        latitude: lat,
        longitude: lng,
      );
      setState(() {
        _allStations = updatedStations;
        _applyFilters();
      });
    } else {
      await _loadStations();
    }
  }

  Future<void> _loadStations() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final lat = _locationService.latitude;
      final lng = _locationService.longitude;

      final stations = await _repository.getNearbyStations(
        latitude: lat,
        longitude: lng,
        radiusKm: 30,
      );

      if (mounted) {
        setState(() {
          _allStations = stations;
          _filteredStations = _buildFilteredStations(stations: stations);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error al cargar estaciones: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredStations = _buildFilteredStations();
    });
  }

  List<ChargingStation> _buildFilteredStations({
    List<ChargingStation>? stations,
  }) {
    return _repository.filterStations(
      stations ?? _allStations,
      query: _filters.searchQuery,
      connectorTypes: _filters.connectorTypes.isNotEmpty
          ? _filters.connectorTypes
          : null,
      chargingTypes: _filters.chargingTypes.isNotEmpty
          ? _filters.chargingTypes
          : null,
      chargingSpeeds: _filters.chargingSpeeds.isNotEmpty
          ? _filters.chargingSpeeds
          : null,
      minPowerKw: _filters.minPowerKw,
      maxPowerKw: _filters.maxPowerKw,
      onlyAvailable: _filters.isAvailable,
      onlyFree: _filters.isFree,
      onlyOpenNow: _filters.isOpenNow,
      maxDistanceKm: _filters.maxDistanceKm,
      sortBy: _filters.sortBy,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Estaciones de Carga'),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: _hasActiveFilters,
              child: const Icon(Icons.filter_list),
            ),
            onPressed: _showFilters,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading
                ? null
                : () {
                    _repository.clearCache();
                    _loadStations();
                  },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildLocationBar(),
          _buildSearchBar(),
          _buildActiveFiltersChips(),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildLocationBar() {
    final isLocating = _locationService.isLocating;
    final locationLabel = _locationService.locationLabel;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.primary.withAlpha(15),
      child: Row(
        children: [
          Icon(
            Icons.location_on,
            size: 18,
            color: isLocating ? AppColors.textSecondary : AppColors.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: isLocating
                ? const Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Obteniendo ubicación...',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  )
                : Text(
                    locationLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
          TextButton.icon(
            onPressed: isLocating ? null : _showLocationOptions,
            icon: const Icon(Icons.edit_location_alt, size: 18),
            label: const Text('Cambiar'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }

  void _showLocationOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _LocationOptionsSheet(
        onUseCurrentLocation: () async {
          Navigator.pop(context);
          await _locationService.getCurrentLocation();
        },
        onSelectCity: (city, lat, lng) {
          Navigator.pop(context);
          _locationService.setCity(city, lat, lng);
        },
      ),
    );
  }

  bool get _hasActiveFilters =>
      _filters.copyWith(searchQuery: '').hasActiveFilters;

  bool get _hasSearchQuery => _filters.searchQuery?.isNotEmpty == true;

  bool get _hasSearchOrFilters => _hasSearchQuery || _hasActiveFilters;

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: AppColors.surface,
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Buscar por nombre, conector, carga o red...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _updateSearchQuery('');
                  },
                )
              : null,
          filled: true,
          fillColor: AppColors.background,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (value) {
          _updateSearchQuery(value);
        },
      ),
    );
  }

  void _updateSearchQuery(String value) {
    final query = value.trim();
    _filters = _filters.copyWith(searchQuery: query.isEmpty ? '' : query);
    _applyFilters();
  }

  Widget _buildActiveFiltersChips() {
    if (!_hasSearchOrFilters) return const SizedBox.shrink();

    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          if (_hasSearchQuery)
            _buildFilterChip('"${_filters.searchQuery}"', () {
              _searchController.clear();
              _updateSearchQuery('');
            }),
          if (_filters.isAvailable == true)
            _buildFilterChip('Disponibles', () {
              _filters = _filters.copyWith(clearIsAvailable: true);
              _applyFilters();
            }),
          if (_filters.isFree == true)
            _buildFilterChip('Gratis', () {
              _filters = _filters.copyWith(clearIsFree: true);
              _applyFilters();
            }),
          if (_filters.isOpenNow == true)
            _buildFilterChip('Abierto ahora', () {
              _filters = _filters.copyWith(clearIsOpenNow: true);
              _applyFilters();
            }),
          for (final chargingType in _filters.chargingTypes)
            _buildFilterChip('Carga ${chargingType.displayName}', () {
              final updatedTypes = Set<ChargingType>.from(
                _filters.chargingTypes,
              )..remove(chargingType);
              _filters = _filters.copyWith(chargingTypes: updatedTypes);
              _applyFilters();
            }),
          for (final connectorType in _filters.connectorTypes)
            _buildFilterChip(connectorType.displayName, () {
              final updatedTypes = Set<ConnectorType>.from(
                _filters.connectorTypes,
              )..remove(connectorType);
              _filters = _filters.copyWith(connectorTypes: updatedTypes);
              _applyFilters();
            }),
          for (final speed in _filters.chargingSpeeds)
            _buildFilterChip(speed.displayName, () {
              final updatedSpeeds = Set<ChargingSpeed>.from(
                _filters.chargingSpeeds,
              )..remove(speed);
              _filters = _filters.copyWith(chargingSpeeds: updatedSpeeds);
              _applyFilters();
            }),
          if (_filters.maxDistanceKm != null)
            _buildFilterChip('Hasta ${_filters.maxDistanceKm!.toInt()} km', () {
              _filters = _filters.copyWith(clearMaxDistance: true);
              _applyFilters();
            }),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _clearAllFilters,
            child: const Text('Limpiar todos'),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, VoidCallback onRemove) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Chip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        deleteIcon: const Icon(Icons.close, size: 16),
        onDeleted: onRemove,
        backgroundColor: AppColors.primary.withAlpha(30),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  void _clearAllFilters() {
    _searchController.clear();
    setState(() {
      _filters = const StationFilters();
      _filteredStations = _buildFilteredStations(stations: _allStations);
    });
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Cargando estaciones de Open Charge Map...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: AppColors.error),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadStations,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_filteredStations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.ev_station,
              size: 64,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              _hasSearchOrFilters
                  ? 'No se encontraron estaciones con estos filtros'
                  : 'No se encontraron estaciones',
              style: const TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            if (_hasActiveFilters) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: _clearAllFilters,
                child: const Text('Limpiar filtros'),
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      children: [
        // Contador de resultados
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                '${_filteredStations.length} estaciones encontradas',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              // Indicador de fuente de datos
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_done, size: 14, color: AppColors.primary),
                    SizedBox(width: 4),
                    Text(
                      'Open Charge Map',
                      style: TextStyle(fontSize: 11, color: AppColors.primary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              _repository.clearCache();
              await _loadStations();
            },
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 16),
              itemCount: _filteredStations.length,
              itemBuilder: (context, index) {
                final station = _filteredStations[index];
                return StationCard(
                  station: station,
                  onTap: () => _navigateToDetail(station),
                  onFavoriteTap: () => _toggleFavorite(station),
                  isFavorite: _favoritesService.isFavorite(station.id),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  void _navigateToDetail(ChargingStation station) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StationDetailPage(station: station),
      ),
    );
  }

  void _toggleFavorite(ChargingStation station) async {
    final wasAdded = await _favoritesService.toggleFavorite(station);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasAdded
                ? '${station.name} agregado a favoritos'
                : '${station.name} eliminado de favoritos',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showFilters() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.85,
          child: FilterSheet(
            initialFilters: _filters,
            onApply: (filters) {
              setState(() {
                _filters = filters.copyWith(
                  searchQuery: _searchController.text.trim(),
                );
                _filteredStations = _buildFilteredStations();
              });
            },
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet para seleccionar ubicación
class _LocationOptionsSheet extends StatelessWidget {
  final VoidCallback onUseCurrentLocation;
  final Function(String city, double lat, double lng) onSelectCity;

  const _LocationOptionsSheet({
    required this.onUseCurrentLocation,
    required this.onSelectCity,
  });

  // Ciudades principales de Colombia con cargadores
  static const List<Map<String, dynamic>> _cities = [
    {'name': 'Medellín', 'lat': 6.2442, 'lng': -75.5812},
    {'name': 'Bogotá', 'lat': 4.6097, 'lng': -74.0817},
    {'name': 'Cali', 'lat': 3.4516, 'lng': -76.5320},
    {'name': 'Barranquilla', 'lat': 10.9685, 'lng': -74.7813},
    {'name': 'Cartagena', 'lat': 10.3910, 'lng': -75.4794},
    {'name': 'Bucaramanga', 'lat': 7.1254, 'lng': -73.1198},
    {'name': 'Pereira', 'lat': 4.8087, 'lng': -75.6906},
    {'name': 'Santa Marta', 'lat': 11.2408, 'lng': -74.1990},
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
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

          // Header
          Text(
            'Seleccionar ubicación',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Las estaciones se cargarán en un radio de 30km',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const Divider(height: 24),

          // Usar ubicación actual
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.my_location, color: AppColors.primary),
            ),
            title: const Text('Usar mi ubicación actual'),
            subtitle: const Text('GPS del dispositivo'),
            trailing: const Icon(Icons.chevron_right),
            onTap: onUseCurrentLocation,
          ),

          const Divider(height: 24),
          const Text(
            'O selecciona una ciudad:',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),

          // Lista de ciudades
          SizedBox(
            height: 200,
            child: ListView.builder(
              itemCount: _cities.length,
              itemBuilder: (context, index) {
                final city = _cities[index];
                return ListTile(
                  leading: const Icon(
                    Icons.location_city,
                    color: AppColors.textSecondary,
                  ),
                  title: Text(city['name'] as String),
                  dense: true,
                  onTap: () => onSelectCity(
                    city['name'] as String,
                    city['lat'] as double,
                    city['lng'] as double,
                  ),
                );
              },
            ),
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}
