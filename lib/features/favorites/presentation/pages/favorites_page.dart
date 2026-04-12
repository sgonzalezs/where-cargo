import 'package:flutter/material.dart';

import '../../../charging_stations/domain/models/charging_station.dart';
import '../../../charging_stations/presentation/widgets/station_card.dart';
import '../../../charging_stations/presentation/pages/station_detail_page.dart';
import '../../domain/models/favorite_station.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/services/favorites_service.dart';

/// Página de estaciones favoritas
class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  final FavoritesService _favoritesService = FavoritesService();

  @override
  void initState() {
    super.initState();
    _favoritesService.addListener(_onFavoritesChanged);
    _loadFavorites();
  }

  @override
  void dispose() {
    _favoritesService.removeListener(_onFavoritesChanged);
    super.dispose();
  }

  void _onFavoritesChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadFavorites() async {
    await _favoritesService.loadFavorites();
  }

  @override
  Widget build(BuildContext context) {
    final favorites = _favoritesService.favorites;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Favoritos'),
        actions: [
          if (favorites.isNotEmpty)
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
    if (_favoritesService.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final favorites = _favoritesService.favorites;
    
    if (favorites.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _loadFavorites,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        itemCount: favorites.length,
        itemBuilder: (context, index) {
          final favorite = favorites[index];
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

  void _removeFavorite(FavoriteStation favorite) async {
    final stationName = favorite.station?.name ?? 'Estación';
    
    await _favoritesService.removeFavoriteById(favorite.id);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$stationName eliminado de favoritos'),
          action: SnackBarAction(
            label: 'Deshacer',
            onPressed: () async {
              if (favorite.station != null) {
                await _favoritesService.addFavorite(favorite.station!);
              }
            },
          ),
        ),
      );
    }
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
                _favoritesService.sortByDate();
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.sort_by_alpha),
              title: const Text('Nombre'),
              onTap: () {
                _favoritesService.sortByName();
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.location_on),
              title: const Text('Distancia'),
              onTap: () {
                _favoritesService.sortByDistance();
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}
