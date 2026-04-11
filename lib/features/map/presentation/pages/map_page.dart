import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../../../charging_stations/domain/models/charging_station.dart';
import '../../../charging_stations/data/repositories/charging_stations_repository.dart';
import '../../../charging_stations/presentation/pages/station_detail_page.dart';
import '../../../../core/theme/app_colors.dart';
import '../widgets/marker_generator.dart';

/// Página del mapa con estaciones de carga
class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  // Controlador de Google Maps
  final Completer<GoogleMapController> _mapController = Completer();
  
  // Repositorio de estaciones
  final ChargingStationsRepository _repository = ChargingStationsRepository();
  
  // Estado
  bool _isLoading = true;
  bool _isLocating = false;
  bool _isSelectingLocation = false;  // Modo de selección de ubicación
  String? _errorMessage;
  List<ChargingStation> _stations = [];
  ChargingStation? _selectedStation;
  Set<Marker> _markers = {};
  Position? _currentPosition;
  LatLng? _userLocation;  // Ubicación seleccionada manualmente
  
  // Posición inicial: Medellín, Colombia
  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(6.2442, -75.5812),
    zoom: 13.0,
  );

  @override
  void initState() {
    super.initState();
    _initializeMap();
  }

  Future<void> _initializeMap() async {
    // Obtener ubicación actual y cargar estaciones cercanas
    await _getCurrentLocation();
    await _loadStations();
  }

  /// Obtiene la ubicación actual del usuario
  Future<void> _getCurrentLocation() async {
    setState(() => _isLocating = true);
    
    try {
      // Verificar si el servicio de ubicación está habilitado
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showLocationError('El servicio de ubicación está desactivado');
        // Usar ubicación por defecto (Medellín)
        return;
      }

      // Verificar permisos
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showLocationError('Permiso de ubicación denegado');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showLocationError('Permiso de ubicación denegado permanentemente');
        return;
      }

      // Obtener ubicación actual con timeout
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      if (mounted) {
        setState(() {
          _currentPosition = position;
        });

        // Mover cámara a la ubicación actual
        final controller = await _mapController.future;
        await controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(position.latitude, position.longitude),
              zoom: 14.0,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error obteniendo ubicación: $e');
      // Se usará la ubicación por defecto
    } finally {
      if (mounted) {
        setState(() => _isLocating = false);
      }
    }
  }

  void _showLocationError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          action: SnackBarAction(
            label: 'Configuración',
            onPressed: () => Geolocator.openLocationSettings(),
          ),
        ),
      );
    }
  }

  /// Carga las estaciones de carga desde Open Charge Map API
  Future<void> _loadStations() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Usar ubicación actual o Medellín como fallback
      final double lat = _currentPosition?.latitude ?? 6.2442;
      final double lng = _currentPosition?.longitude ?? -75.5812;
      
      final stations = await _repository.getNearbyStations(
        latitude: lat,
        longitude: lng,
        radiusKm: 30,
      );
      
      if (mounted) {
        // Crear marcadores personalizados de forma asíncrona
        final markers = await _createMarkersAsync(stations);
        
        setState(() {
          _stations = stations;
          _markers = markers;
          _isLoading = false;
        });
        
        if (stations.isEmpty) {
          _showMessage('No se encontraron estaciones en esta zona');
        } else {
          _showMessage('${stations.length} estaciones encontradas');
        }
      }
    } catch (e) {
      debugPrint('Error cargando estaciones: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Error al cargar estaciones';
          _isLoading = false;
        });
        _showMessage('Error: $e');
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Recarga las estaciones
  Future<void> _refreshStations() async {
    _repository.clearCache();
    MarkerGenerator.clearCache();
    await _loadStations();
  }

  /// Combina los marcadores de estaciones con el marcador de ubicación del usuario
  Set<Marker> get _allMarkers {
    final markers = Set<Marker>.from(_markers);
    
    // Agregar marcador de ubicación del usuario si existe
    if (_userLocation != null) {
      markers.add(Marker(
        markerId: const MarkerId('user_location'),
        position: _userLocation!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        anchor: const Offset(0.5, 0.5),
        infoWindow: const InfoWindow(title: 'Mi ubicación'),
        zIndexInt: 999, // Siempre encima de otros marcadores
      ));
    }
    
    return markers;
  }

  /// Maneja el toque en el mapa
  void _onMapTapped(LatLng position) {
    if (_isSelectingLocation) {
      // Establecer ubicación seleccionada
      _setUserLocation(position);
    } else {
      // Cerrar preview al tocar el mapa
      if (_selectedStation != null) {
        setState(() => _selectedStation = null);
      }
    }
  }

  /// Activa/desactiva el modo de selección de ubicación
  void _toggleLocationSelection() {
    setState(() {
      _isSelectingLocation = !_isSelectingLocation;
      if (_isSelectingLocation) {
        _selectedStation = null; // Cerrar preview si está abierto
        _showMessage('Toca el mapa para establecer tu ubicación');
      }
    });
  }

  /// Establece la ubicación del usuario manualmente
  Future<void> _setUserLocation(LatLng position) async {
    setState(() {
      _userLocation = position;
      _isSelectingLocation = false;
      _currentPosition = Position(
        latitude: position.latitude,
        longitude: position.longitude,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
    });
    
    _showMessage('Ubicación actualizada. Cargando estaciones cercanas...');
    
    // Recargar estaciones desde la nueva ubicación
    await _loadStations();
  }

  /// Widget del banner de selección de ubicación
  Widget _buildLocationSelectionBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(40),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.touch_app, color: Colors.white),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Toca el mapa para establecer tu ubicación',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => setState(() => _isSelectingLocation = false),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  /// Crea los marcadores personalizados para el mapa (asíncrono)
  Future<Set<Marker>> _createMarkersAsync(List<ChargingStation> stations) async {
    final markers = <Marker>{};
    
    for (final station in stations) {
      final icon = await MarkerGenerator.generateStationMarker(station);
      
      markers.add(Marker(
        markerId: MarkerId(station.id),
        position: LatLng(station.latitude, station.longitude),
        icon: icon,
        anchor: const Offset(0.5, 1.0),
        infoWindow: InfoWindow(
          title: station.name,
          snippet: '${station.availabilityText} • ${station.maxPowerKw.toInt()} kW',
        ),
        onTap: () => _selectStation(station),
      ));
    }
    
    return markers;
  }

  /// Crea los marcadores para el mapa (versión simple de respaldo)
  Set<Marker> _createMarkers(List<ChargingStation> stations) {
    return stations.map((station) {
      return Marker(
        markerId: MarkerId(station.id),
        position: LatLng(station.latitude, station.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          station.hasAvailableConnectors
              ? BitmapDescriptor.hueGreen
              : BitmapDescriptor.hueOrange,
        ),
        infoWindow: InfoWindow(
          title: station.name,
          snippet: '${station.availabilityText} • ${station.maxPowerKw.toInt()} kW',
        ),
        onTap: () => _selectStation(station),
      );
    }).toSet();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Google Maps
          GoogleMap(
            initialCameraPosition: _initialPosition,
            onMapCreated: (controller) {
              _mapController.complete(controller);
            },
            markers: _allMarkers,
            // Desactivado para simulador (muestra California)
            // myLocationEnabled: true,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: true,
            onTap: _onMapTapped,
          ),

          // Banner de modo selección de ubicación
          if (_isSelectingLocation)
            Positioned(
              top: MediaQuery.of(context).padding.top + 80,
              left: 16,
              right: 16,
              child: _buildLocationSelectionBanner(),
            ),

          // Barra de búsqueda superior
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 16,
            child: _buildSearchBar(),
          ),

          // Card de estación seleccionada
          if (_selectedStation != null)
            Positioned(
              bottom: 24,
              left: 16,
              right: 16,
              child: _buildStationPreview(_selectedStation!),
            ),

          // Botones flotantes (ubicación y zoom)
          Positioned(
            bottom: _selectedStation != null ? 200 : 24,
            right: 16,
            child: Column(
              children: [
                // Botón de recargar
                FloatingActionButton.small(
                  heroTag: 'refresh',
                  onPressed: _isLoading ? null : _refreshStations,
                  backgroundColor: Colors.white,
                  child: const Icon(Icons.refresh, color: AppColors.primary),
                ),
                const SizedBox(height: 8),
                // Botón de lista
                FloatingActionButton.small(
                  heroTag: 'list',
                  onPressed: _showStationsList,
                  backgroundColor: Colors.white,
                  child: const Icon(Icons.list, color: AppColors.primary),
                ),
                const SizedBox(height: 8),
                // Botón de ubicación actual
                FloatingActionButton(
                  heroTag: 'location',
                  onPressed: _isLocating ? null : _centerOnUserLocation,
                  child: _isLocating
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.my_location),
                ),
                const SizedBox(height: 8),
                // Botón para seleccionar ubicación manualmente
                FloatingActionButton.small(
                  heroTag: 'select_location',
                  onPressed: _toggleLocationSelection,
                  backgroundColor: _isSelectingLocation ? AppColors.primary : Colors.white,
                  child: Icon(
                    Icons.add_location_alt,
                    color: _isSelectingLocation ? Colors.white : AppColors.primary,
                  ),
                ),
              ],
            ),
          ),

          // Indicador de carga inicial o error
          if (_isLoading || _errorMessage != null)
            Container(
              color: Colors.black26,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isLoading) ...[
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          const Text('Cargando estaciones de Open Charge Map...'),
                        ] else if (_errorMessage != null) ...[
                          const Icon(Icons.error_outline, size: 48, color: Colors.red),
                          const SizedBox(height: 16),
                          Text(_errorMessage!),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _refreshStations,
                            child: const Text('Reintentar'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Buscar estaciones cerca de...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.filter_list),
                onPressed: _showFilters,
              ),
            ],
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
        onSubmitted: (value) {
          // TODO: Implementar búsqueda
        },
      ),
    );
  }

  Widget _buildStationPreview(ChargingStation station) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _navigateToDetail(station),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: station.hasAvailableConnectors
                        ? AppColors.stationAvailable.withOpacity(0.1)
                        : AppColors.stationOccupied.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.ev_station,
                    color: station.hasAvailableConnectors
                        ? AppColors.stationAvailable
                        : AppColors.stationOccupied,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        station.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        station.address,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _buildInfoChip(
                            Icons.electrical_services,
                            '${station.maxPowerKw.toInt()} kW',
                          ),
                          const SizedBox(width: 8),
                          _buildInfoChip(
                            Icons.power,
                            station.availabilityText,
                          ),
                          if (station.distanceKm != null) ...[
                            const SizedBox(width: 8),
                            _buildInfoChip(
                              Icons.navigation,
                              '${station.distanceKm!.toStringAsFixed(1)} km',
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.directions),
                      color: AppColors.primary,
                      onPressed: () => _navigateToStation(station),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      color: AppColors.textSecondary,
                      onPressed: () {
                        setState(() => _selectedStation = null);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }

  void _selectStation(ChargingStation station) async {
    setState(() {
      _selectedStation = station;
    });

    // Centrar mapa en la estación seleccionada
    final controller = await _mapController.future;
    controller.animateCamera(
      CameraUpdate.newLatLng(
        LatLng(station.latitude, station.longitude),
      ),
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

  void _navigateToStation(ChargingStation station) {
    // TODO: Integrar con NavigationService para abrir Waze/Google Maps
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Navegando a ${station.name}'),
        action: SnackBarAction(
          label: 'Abrir',
          onPressed: () {
            // TODO: Abrir navegación externa
          },
        ),
      ),
    );
  }

  Future<void> _centerOnUserLocation() async {
    setState(() => _isLocating = true);
    
    try {
      // En modo simulador, centrar en Medellín
      // Para dispositivo real, descomentar el código de Geolocator:
      /*
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _currentPosition = position;
      });
      */

      final controller = await _mapController.future;
      controller.animateCamera(
        CameraUpdate.newCameraPosition(
          // Medellín - ubicación simulada para pruebas
          const CameraPosition(
            target: LatLng(6.2442, -75.5812),
            zoom: 15.0,
          ),
        ),
      );
    } catch (e) {
      _showLocationError('No se pudo obtener tu ubicación');
    } finally {
      setState(() => _isLocating = false);
    }
  }

  void _showFilters() {
    // TODO: Implementar filtros
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Filtros próximamente')),
    );
  }

  void _showStationsList() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(
                      'Estaciones cercanas',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const Spacer(),
                    Text(
                      '${_stations.length} encontradas',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: _stations.length,
                  itemBuilder: (context, index) {
                    final station = _stations[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: station.hasAvailableConnectors
                            ? AppColors.stationAvailable
                            : AppColors.stationOccupied,
                        child: const Icon(Icons.ev_station, color: Colors.white),
                      ),
                      title: Text(station.name),
                      subtitle: Text(station.address),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${station.maxPowerKw.toInt()} kW',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            station.availabilityText,
                            style: TextStyle(
                              fontSize: 12,
                              color: station.hasAvailableConnectors
                                  ? AppColors.stationAvailable
                                  : AppColors.stationOccupied,
                            ),
                          ),
                        ],
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _selectStation(station);
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _repository.dispose();
    super.dispose();
  }
}
