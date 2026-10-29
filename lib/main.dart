import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';
import 'firebase_options.dart';
import 'navigation/app_router.dart';
import 'shared/services/auth_service.dart';
import 'shared/services/notification_service.dart';
import 'shared/services/vehicle_catalog_service.dart';
import 'shared/services/vehicle_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await AuthService().initialize();

  // Catálogo de vehículos: si en Firestore hay una versión más nueva se
  // descarga en segundo plano y se enlazan los vehículos que ahora existan
  VehicleCatalogService().refresh().then((updated) {
    if (updated) VehicleService().relinkVehicles();
  });

  // Inicializar servicio de notificaciones y solicitar permisos
  await NotificationService().initialize();
  
  // Configurar orientación preferida
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  // Configurar estilo de la barra de estado
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  
  runApp(const WhereCargo());
}

/// Aplicación principal - Where Cargo
/// App para encontrar estaciones de carga de vehículos eléctricos en Colombia
class WhereCargo extends StatelessWidget {
  const WhereCargo({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      
      // Temas
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      
      // Navegación
      initialRoute: AppRouter.splash,
      onGenerateRoute: AppRouter.generateRoute,
    );
  }
}
