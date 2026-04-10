import 'package:flutter/material.dart';

import '../../domain/models/charging_station.dart';
import '../../domain/enums/charging_enums.dart';
import '../../data/repositories/charging_stations_repository.dart';
import '../widgets/station_card.dart';
import 'station_detail_page.dart';
import '../../../../core/theme/app_colors.dart';

/// Página con lista de estaciones de carga
class StationsListPage extends StatefulWidget {
  const StationsListPage({super.key});

  @override
  State<StationsListPage> createState() => _StationsListPageState();
}

class _StationsListPageState extends State<StationsListPage> {
  final TextEditingController _searchController = TextEditingController();
  final ChargingStationsRepository _repository = ChargingStationsRepository();
  
  bool _isLoading = false;
  List<ChargingStation> _allStations = [];
  List<ChargingStation> _filteredStations = [];
  String? _errorMessage;
  
  // Filtros activos
  Set<ChargingType> _selectedChargingTypes = {};
  ChargingSpeed? _minSpeed;
  bool _onlyAvailable = false;
  bool _onlyFree = false;

  @override
  void initState() {
    super.initState();
    _loadStations();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _repository.dispose();
    super.dispose();
  }

  Future<void> _loadStations() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Cargar estaciones desde Open Charge Map - Medellín
      final stations = await _repository.getNearbyStations(
        latitude: 6.2442,
        longitude: -75.5812,
        radiusKm: 30,
      );
      
      if (mounted) {
        setState(() {
          _allStations = stations;
          _applyFilters();
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
    var filtered = List<ChargingStation>.from(_allStations);
    
    // Filtro de búsqueda por texto
    final query = _searchController.text.toLowerCase().trim();
    if (query.isNotEmpty) {
      filtered = filtered.where((station) =>
          station.name.toLowerCase().contains(query) ||
          station.address.toLowerCase().contains(query) ||
          (station.networkName?.toLowerCase().contains(query) ?? false) ||
          station.city.toLowerCase().contains(query)
      ).toList();
    }
    
    // Aplicar filtros del repositorio
    filtered = _repository.filterStations(
      filtered,
      chargingTypes: _selectedChargingTypes.isNotEmpty ? _selectedChargingTypes : null,
      minSpeed: _minSpeed,
      onlyAvailable: _onlyAvailable ? true : null,
      onlyFree: _onlyFree ? true : null,
    );
    
    setState(() {
      _filteredStations = filtered;
    });
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
            onPressed: _isLoading ? null : () {
              _repository.clearCache();
              _loadStations();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildActiveFiltersChips(),
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }
  
  bool get _hasActiveFilters =>
      _selectedChargingTypes.isNotEmpty ||
      _minSpeed != null ||
      _onlyAvailable ||
      _onlyFree;

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: AppColors.surface,
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Buscar por nombre, dirección o red...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _applyFilters();
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
          _applyFilters();
        },
      ),
    );
  }

  Widget _buildActiveFiltersChips() {
    if (!_hasActiveFilters) return const SizedBox.shrink();
    
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          if (_onlyAvailable)
            _buildFilterChip('Disponibles', () {
              setState(() => _onlyAvailable = false);
              _applyFilters();
            }),
          if (_onlyFree)
            _buildFilterChip('Gratis', () {
              setState(() => _onlyFree = false);
              _applyFilters();
            }),
          if (_selectedChargingTypes.contains(ChargingType.dc))
            _buildFilterChip('Carga DC', () {
              setState(() => _selectedChargingTypes.remove(ChargingType.dc));
              _applyFilters();
            }),
          if (_selectedChargingTypes.contains(ChargingType.ac))
            _buildFilterChip('Carga AC', () {
              setState(() => _selectedChargingTypes.remove(ChargingType.ac));
              _applyFilters();
            }),
          if (_minSpeed != null)
            _buildFilterChip(_minSpeed!.displayName, () {
              setState(() => _minSpeed = null);
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
    setState(() {
      _selectedChargingTypes.clear();
      _minSpeed = null;
      _onlyAvailable = false;
      _onlyFree = false;
    });
    _applyFilters();
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
              const Icon(
                Icons.error_outline,
                size: 64,
                color: AppColors.error,
              ),
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
              _searchController.text.isNotEmpty || _hasActiveFilters
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
                  isFavorite: false, // TODO: Implementar favoritos
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

  void _toggleFavorite(ChargingStation station) {
    // TODO: Implementar toggle de favoritos
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${station.name} agregado a favoritos'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showFilters() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _FiltersSheet(
        selectedChargingTypes: _selectedChargingTypes,
        minSpeed: _minSpeed,
        onlyAvailable: _onlyAvailable,
        onlyFree: _onlyFree,
        availableNetworks: _repository.getAvailableNetworks(),
        onApply: (chargingTypes, minSpeed, onlyAvailable, onlyFree) {
          setState(() {
            _selectedChargingTypes = chargingTypes;
            _minSpeed = minSpeed;
            _onlyAvailable = onlyAvailable;
            _onlyFree = onlyFree;
          });
          _applyFilters();
          Navigator.pop(context);
        },
      ),
    );
  }
}

/// Bottom sheet de filtros
class _FiltersSheet extends StatefulWidget {
  final Set<ChargingType> selectedChargingTypes;
  final ChargingSpeed? minSpeed;
  final bool onlyAvailable;
  final bool onlyFree;
  final Set<String> availableNetworks;
  final Function(Set<ChargingType>, ChargingSpeed?, bool, bool) onApply;

  const _FiltersSheet({
    required this.selectedChargingTypes,
    required this.minSpeed,
    required this.onlyAvailable,
    required this.onlyFree,
    required this.availableNetworks,
    required this.onApply,
  });

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late Set<ChargingType> _chargingTypes;
  ChargingSpeed? _minSpeed;
  late bool _onlyAvailable;
  late bool _onlyFree;

  @override
  void initState() {
    super.initState();
    _chargingTypes = Set.from(widget.selectedChargingTypes);
    _minSpeed = widget.minSpeed;
    _onlyAvailable = widget.onlyAvailable;
    _onlyFree = widget.onlyFree;
  }

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
          Row(
            children: [
              Text(
                'Filtros',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  setState(() {
                    _chargingTypes.clear();
                    _minSpeed = null;
                    _onlyAvailable = false;
                    _onlyFree = false;
                  });
                },
                child: const Text('Limpiar'),
              ),
            ],
          ),
          const Divider(),
          
          // Disponibilidad
          const SizedBox(height: 8),
          const Text('Disponibilidad', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              FilterChip(
                label: const Text('Solo disponibles'),
                selected: _onlyAvailable,
                onSelected: (value) => setState(() => _onlyAvailable = value),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Solo gratis'),
                selected: _onlyFree,
                onSelected: (value) => setState(() => _onlyFree = value),
              ),
            ],
          ),
          
          // Tipo de carga
          const SizedBox(height: 16),
          const Text('Tipo de carga', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              FilterChip(
                label: const Text('DC (Rápida)'),
                selected: _chargingTypes.contains(ChargingType.dc),
                onSelected: (value) {
                  setState(() {
                    if (value) {
                      _chargingTypes.add(ChargingType.dc);
                    } else {
                      _chargingTypes.remove(ChargingType.dc);
                    }
                  });
                },
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('AC (Normal)'),
                selected: _chargingTypes.contains(ChargingType.ac),
                onSelected: (value) {
                  setState(() {
                    if (value) {
                      _chargingTypes.add(ChargingType.ac);
                    } else {
                      _chargingTypes.remove(ChargingType.ac);
                    }
                  });
                },
              ),
            ],
          ),
          
          // Velocidad mínima
          const SizedBox(height: 16),
          const Text('Velocidad mínima', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: ChargingSpeed.values.map((speed) {
              return ChoiceChip(
                label: Text(speed.displayName),
                selected: _minSpeed == speed,
                onSelected: (value) {
                  setState(() => _minSpeed = value ? speed : null);
                },
              );
            }).toList(),
          ),
          
          // Redes disponibles
          if (widget.availableNetworks.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Redes disponibles: ${widget.availableNetworks.length}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: widget.availableNetworks.take(6).map((network) {
                return Chip(
                  label: Text(network, style: const TextStyle(fontSize: 12)),
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
          ],
          
          const SizedBox(height: 24),
          
          // Botón aplicar
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                widget.onApply(_chargingTypes, _minSpeed, _onlyAvailable, _onlyFree);
              },
              child: const Text('Aplicar filtros'),
            ),
          ),
          
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}
