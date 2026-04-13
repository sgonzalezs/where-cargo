import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/services/onboarding_service.dart';
import '../../../../shared/services/vehicle_service.dart';
import '../../../vehicle_sync/domain/models/vehicle.dart';

/// Página de onboarding para usuarios nuevos
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pageController = PageController();
  final OnboardingService _onboardingService = OnboardingService();
  final VehicleService _vehicleService = VehicleService();

  int _currentPage = 0;
  final int _totalPages = 3;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _completeOnboarding({bool addedVehicle = false}) async {
    await _onboardingService.completeOnboarding();
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Botón de omitir en la esquina superior derecha
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TextButton(
                  onPressed: _completeOnboarding,
                  child: Text(
                    _currentPage == _totalPages - 1 ? '' : 'Omitir',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),

            // PageView con los slides
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                children: [
                  _WelcomeSlide(onNext: _nextPage),
                  _FeaturesSlide(onNext: _nextPage),
                  _VehicleSlide(
                    vehicleService: _vehicleService,
                    onComplete: _completeOnboarding,
                  ),
                ],
              ),
            ),

            // Indicadores de página
            Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _totalPages,
                  (index) => _buildDotIndicator(index == _currentPage),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDotIndicator(bool isActive) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: isActive ? 24 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: isActive ? AppColors.primary : AppColors.textSecondary.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

/// Slide de bienvenida
class _WelcomeSlide extends StatelessWidget {
  final VoidCallback onNext;

  const _WelcomeSlide({required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Logo / Icono
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.ev_station,
              size: 80,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 48),

          // Título
          Text(
            'Where Cargo',
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
          ),
          const SizedBox(height: 16),

          // Subtítulo
          Text(
            'Encuentra estaciones de carga\npara vehículos eléctricos en Colombia',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
          ),
          const SizedBox(height: 64),

          // Botón siguiente
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onNext,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Comenzar'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Slide de funcionalidades
class _FeaturesSlide extends StatelessWidget {
  final VoidCallback onNext;

  const _FeaturesSlide({required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '¿Qué puedes hacer?',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 48),

          _FeatureItem(
            icon: Icons.map,
            color: AppColors.primary,
            title: 'Mapa interactivo',
            description: 'Visualiza estaciones cercanas en tiempo real',
          ),
          const SizedBox(height: 24),

          _FeatureItem(
            icon: Icons.favorite,
            color: AppColors.error,
            title: 'Guarda favoritos',
            description: 'Accede rápido a tus estaciones preferidas',
          ),
          const SizedBox(height: 24),

          _FeatureItem(
            icon: Icons.navigation,
            color: AppColors.secondary,
            title: 'Navega fácilmente',
            description: 'Obtén direcciones con Waze o Google Maps',
          ),
          const SizedBox(height: 24),

          _FeatureItem(
            icon: Icons.electric_car,
            color: AppColors.warning,
            title: 'Tu vehículo',
            description: 'Registra tu auto para recomendaciones personalizadas',
          ),

          const SizedBox(height: 48),

          // Botón siguiente
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onNext,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Siguiente'),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String description;

  const _FeatureItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Slide de vehículo (formulario simplificado)
class _VehicleSlide extends StatefulWidget {
  final VehicleService vehicleService;
  final Future<void> Function({bool addedVehicle}) onComplete;

  const _VehicleSlide({
    required this.vehicleService,
    required this.onComplete,
  });

  @override
  State<_VehicleSlide> createState() => _VehicleSlideState();
}

class _VehicleSlideState extends State<_VehicleSlide> {
  final _formKey = GlobalKey<FormState>();

  String? _selectedBrand;
  String? _selectedModel;
  final TextEditingController _batteryController = TextEditingController();
  final Set<String> _selectedConnectors = {};

  bool _isSaving = false;

  // Marcas y modelos populares
  static const Map<String, List<String>> _brandsAndModels = {
    'Tesla': ['Model 3', 'Model Y', 'Model S', 'Model X'],
    'BYD': ['Dolphin', 'Seal', 'Atto 3', 'Han'],
    'Chevrolet': ['Bolt EV', 'Bolt EUV', 'Equinox EV'],
    'Nissan': ['Leaf', 'Ariya'],
    'Hyundai': ['Ioniq 5', 'Ioniq 6', 'Kona Electric'],
    'Kia': ['EV6', 'EV9', 'Niro EV'],
    'Ford': ['Mustang Mach-E', 'F-150 Lightning'],
    'Volkswagen': ['ID.4', 'ID.3', 'ID.Buzz'],
    'BMW': ['i4', 'iX', 'iX3'],
    'Otro': ['Otro modelo'],
  };

  // Conectores más comunes
  static const List<Map<String, String>> _connectorTypes = [
    {'id': 'ccs2', 'name': 'CCS2'},
    {'id': 'type2', 'name': 'Type 2'},
    {'id': 'chademo', 'name': 'CHAdeMO'},
    {'id': 'tesla', 'name': 'Tesla'},
  ];

  @override
  void dispose() {
    _batteryController.dispose();
    super.dispose();
  }

  Future<void> _saveVehicle() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedConnectors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona al menos un conector')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final vehicle = Vehicle(
        id: 'vehicle_${DateTime.now().millisecondsSinceEpoch}',
        brand: _selectedBrand!,
        model: _selectedModel!,
        year: DateTime.now().year,
        batteryCapacityKwh: double.parse(_batteryController.text),
        currentBatteryPercent: 100,
        compatibleConnectors: _selectedConnectors.toList(),
        isPrimary: true,
      );

      await widget.vehicleService.loadVehicles();
      await widget.vehicleService.addVehicle(vehicle);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Vehículo registrado!')),
        );
        await widget.onComplete(addedVehicle: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            const SizedBox(height: 16),
            
            // Icono y título
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.electric_car,
                size: 40,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),

            Text(
              'Registra tu vehículo',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),

            Text(
              'Esto nos ayuda a mostrarte estaciones compatibles.\nPuedes omitir este paso y hacerlo después.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 32),

            // Marca
            DropdownButtonFormField<String>(
              value: _selectedBrand,
              decoration: const InputDecoration(
                labelText: 'Marca',
                prefixIcon: Icon(Icons.business),
                border: OutlineInputBorder(),
              ),
              items: _brandsAndModels.keys.map((brand) {
                return DropdownMenuItem(value: brand, child: Text(brand));
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedBrand = value;
                  _selectedModel = null;
                });
              },
              validator: (value) => value == null ? 'Selecciona una marca' : null,
            ),
            const SizedBox(height: 16),

            // Modelo
            DropdownButtonFormField<String>(
              value: _selectedModel,
              decoration: const InputDecoration(
                labelText: 'Modelo',
                prefixIcon: Icon(Icons.directions_car),
                border: OutlineInputBorder(),
              ),
              items: (_brandsAndModels[_selectedBrand] ?? []).map((model) {
                return DropdownMenuItem(value: model, child: Text(model));
              }).toList(),
              onChanged: _selectedBrand == null
                  ? null
                  : (value) => setState(() => _selectedModel = value),
              validator: (value) =>
                  value == null ? 'Selecciona un modelo' : null,
            ),
            const SizedBox(height: 16),

            // Capacidad de batería
            TextFormField(
              controller: _batteryController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Capacidad de batería (kWh)',
                hintText: 'Ej: 60',
                prefixIcon: Icon(Icons.battery_full),
                suffixText: 'kWh',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Ingresa la capacidad';
                }
                final capacity = double.tryParse(value);
                if (capacity == null || capacity <= 0) {
                  return 'Capacidad inválida';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),

            // Conectores
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Conectores compatibles',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            const SizedBox(height: 12),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _connectorTypes.map((connector) {
                final isSelected = _selectedConnectors.contains(connector['id']);
                return FilterChip(
                  label: Text(connector['name']!),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedConnectors.add(connector['id']!);
                      } else {
                        _selectedConnectors.remove(connector['id']!);
                      }
                    });
                  },
                  selectedColor: AppColors.primary.withValues(alpha: 0.2),
                  checkmarkColor: AppColors.primary,
                );
              }).toList(),
            ),
            const SizedBox(height: 32),

            // Botones
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveVehicle,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Guardar vehículo'),
              ),
            ),
            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _isSaving ? null : () => widget.onComplete(),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Omitir por ahora'),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
