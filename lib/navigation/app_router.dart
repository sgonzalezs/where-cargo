import 'package:flutter/material.dart';

import '../features/charging_stations/presentation/pages/stations_list_page.dart';
import '../features/map/presentation/pages/map_page.dart';
import '../features/favorites/presentation/pages/favorites_page.dart';
import '../features/vehicle_sync/presentation/pages/vehicle_status_page.dart';
import '../core/theme/app_colors.dart';

/// Router principal de la aplicación
class AppRouter {
  static const String home = '/';
  static const String stationsList = '/stations';
  static const String stationDetail = '/stations/:id';
  static const String map = '/map';
  static const String favorites = '/favorites';
  static const String vehicle = '/vehicle';
  static const String settings = '/settings';
  static const String profile = '/profile';

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case home:
      case stationsList:
        return MaterialPageRoute(
          builder: (_) => const MainNavigationPage(),
        );
      case map:
        return MaterialPageRoute(
          builder: (_) => const MapPage(),
        );
      case favorites:
        return MaterialPageRoute(
          builder: (_) => const FavoritesPage(),
        );
      case vehicle:
        return MaterialPageRoute(
          builder: (_) => const VehicleStatusPage(),
        );
      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(
              child: Text('Ruta no encontrada: ${settings.name}'),
            ),
          ),
        );
    }
  }
}

/// Página principal con navegación inferior
class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    MapPage(),           // Mapa como pantalla principal
    StationsListPage(),  // Lista de estaciones
    FavoritesPage(),     // Favoritos
    VehicleStatusPage(), // Estado del vehículo
  ];

  final List<BottomNavigationBarItem> _navItems = const [
    BottomNavigationBarItem(
      icon: Icon(Icons.map_outlined),
      activeIcon: Icon(Icons.map),
      label: 'Mapa',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.ev_station_outlined),
      activeIcon: Icon(Icons.ev_station),
      label: 'Estaciones',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.favorite_outline),
      activeIcon: Icon(Icons.favorite),
      label: 'Favoritos',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.electric_car_outlined),
      activeIcon: Icon(Icons.electric_car),
      label: 'Mi Auto',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        items: _navItems,
      ),
    );
  }
}
