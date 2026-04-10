import 'package:flutter/material.dart';

import '../../../charging_stations/domain/models/charging_station.dart';
import '../../../charging_stations/presentation/widgets/station_card.dart';
import '../../../charging_stations/presentation/pages/station_detail_page.dart';
import '../../domain/models/favorite_station.dart';
import '../../../../core/theme/app_colors.dart';

/// Página de estaciones favoritas
class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  bool _isLoading = true;
  List<FavoriteStation> _favorites = [];

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    setState(() => _isLoading = true);

    // TODO: Cargar desde repositorio
    await Future.delayed(const Duration(seconds: 1));

    setState(() {
      _favorites = _getMockFavorites();
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Favoritos'),
        actions: [
          if (_favorites.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.sort),
              onPressed: _showSortOptions,
            ),
        ],
      ),
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_favorites.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _loadFavorites,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        itemCount: _favorites.length,
        itemBuilder: (context, index) {
          final favorite = _favorites[index];
          if (favorite.station == null) return const SizedBox.shrink();

          return Dismissible(
            key: Key(favorite.id),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              color: AppColors.error,
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            confirmDismiss: (direction) => _confirmRemove(favorite),
            onDismissed: (direction) => _removeFavorite(favorite),
            child: StationCard(
              station: favorite.station!,
              isFavorite: true,
              onTap: () => _navigateToDetail(favorite.station!),
              onFavoriteTap: () => _removeFavorite(favorite),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.favorite_border,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No tienes favoritos',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Agrega estaciones a favoritos para\nacceder a ellas rápidamente',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              // TODO: Navegar a lista/mapa de estaciones
              Navigator.pop(context);
            },
            icon: const Icon(Icons.search),
            label: const Text('Buscar Estaciones'),
          ),
        ],
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

  Future<bool> _confirmRemove(FavoriteStation favorite) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar de favoritos'),
        content: Text(
          '¿Deseas eliminar "${favorite.station?.name}" de tus favoritos?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    ) ?? false;
  }

  void _removeFavorite(FavoriteStation favorite) {
    setState(() {
      _favorites.removeWhere((f) => f.id == favorite.id);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${favorite.station?.name} eliminado de favoritos'),
        action: SnackBarAction(
          label: 'Deshacer',
          onPressed: () {
            setState(() {
              _favorites.add(favorite);
            });
          },
        ),
      ),
    );
  }

  void _showSortOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ordenar por',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.access_time),
              title: const Text('Fecha de agregado'),
              onTap: () {
                setState(() {
                  _favorites.sort((a, b) => b.addedAt.compareTo(a.addedAt));
                });
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.sort_by_alpha),
              title: const Text('Nombre'),
              onTap: () {
                setState(() {
                  _favorites.sort((a, b) =>
                      (a.station?.name ?? '').compareTo(b.station?.name ?? ''));
                });
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.location_on),
              title: const Text('Distancia'),
              onTap: () {
                setState(() {
                  _favorites.sort((a, b) =>
                      (a.station?.distanceKm ?? 999)
                          .compareTo(b.station?.distanceKm ?? 999));
                });
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  List<FavoriteStation> _getMockFavorites() {
    return [
      FavoriteStation(
        id: 'f1',
        stationId: '1',
        addedAt: DateTime.now().subtract(const Duration(days: 5)),
        station: ChargingStation.fromJson({
          'id': '1',
          'name': 'Celsia Solar - Centro Comercial Andino',
          'address': 'Cra. 11 #82-71',
          'city': 'Bogotá',
          'country': 'Colombia',
          'latitude': 4.6667,
          'longitude': -74.0527,
          'status': 'available',
          'payment_type': 'paid',
          'network_name': 'Celsia Solar',
          'connectors': [
            {'id': 'c1', 'type': 'ccs2', 'charging_type': 'dc', 'power_kw': 50, 'status': 'available'},
          ],
          'rating': 4.5,
          'distance_km': 2.3,
        }),
      ),
      FavoriteStation(
        id: 'f2',
        stationId: '2',
        addedAt: DateTime.now().subtract(const Duration(days: 2)),
        station: ChargingStation.fromJson({
          'id': '2',
          'name': 'Enel X - Parque 93',
          'address': 'Cra. 13 #93A-20',
          'city': 'Bogotá',
          'country': 'Colombia',
          'latitude': 4.6782,
          'longitude': -74.0486,
          'status': 'available',
          'payment_type': 'paid',
          'network_name': 'Enel X',
          'connectors': [
            {'id': 'c2', 'type': 'ccs2', 'charging_type': 'dc', 'power_kw': 150, 'status': 'available'},
          ],
          'rating': 4.8,
          'distance_km': 3.1,
        }),
      ),
    ];
  }
}
