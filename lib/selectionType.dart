import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:shnell/VehiculeDetail.dart';
import 'package:shnell/model/destinationdata.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart'; // Import the localization class

class VehicleSelectionScreen extends StatefulWidget {
  final LatLng pickup;
  final List<DropOffData> dropOffDestination;
  final String pickup_name;

  const VehicleSelectionScreen({
    super.key,
    required this.pickup,
    required this.dropOffDestination,
    required this.pickup_name,
  });

  @override
  _VehicleSelectionScreenState createState() => _VehicleSelectionScreenState();
}

class _VehicleSelectionScreenState extends State<VehicleSelectionScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedVehicleIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // --- VEHICLE DATA ---
  // Using localization keys for dynamic strings
  final List<Map<String, dynamic>> lightVehicles = [
    // on va ajouter les motos lors que lapplication avoir au moin 100 utilisateur actifs / jour
    // on va ajouter le type moto , et invester entre 10k$ - 30k$ pour cetter categorie seul
    // tout les autre categorie vont coster 2k$ 15k$, entre la marketing frais de lapplication et les papiers juridique etc ..
    /*{
      "typeKey": "moto",
      "typeCode": "super_light",
      "image": "assets/super_light.png",
      "weight": "100 kg",
      "exampleKey": "idealForSmallVolumes",
      "tagKey": "fastestTag"
    },*/
    {
      "typeKey": "smallUtility",
      "typeCode": "light",
      "image": "assets/light.png",
      "weight": "500 kg",
      "exampleKey": "idealForAppliances",
      "tagKey": "mostEconomicalTag"
    },
    {
      "typeKey": "van",
      "typeCode": "light_medium",
      "image": "assets/isuzu.png",
      "weight": "1.5 T",
      "exampleKey": "perfectForMaterials",
      "tagKey": "mostPopularTag"
    },
  ];

  final List<Map<String, dynamic>> heavyVehicles = [
    {
      "typeKey": "van35T",
      "typeCode": "medium",
      "image": "assets/medium.png",
      "weight": "3.5 T",
      "exampleKey": "forFullStudioMove",
      "tagKey": "mostEfficientTag"
    },
    {
      "typeKey": "largeVan",
      "typeCode": "medium_heavy",
      "image": "assets/medium_heavy.png",
      "weight": "7.5 T",
      "exampleKey": "forLargerMoves",
      "tagKey": "bestValueTag"
    },
    {
      "typeKey": "heavyTruck",
      "typeCode": "heavy",
      "image": "assets/heavy.png",
      "weight": "12 T",
      "exampleKey": "forLargeVolumes",
      "tagKey": "heavyCapacityTag"
    },
    {
      "typeKey": "superHeavyTruck",
      "typeCode": "super_heavy",
      "image": "assets/super_heavy.png",
      "weight": "33 T",
      "exampleKey": "forExceptionalTransports",
      "tagKey": "maximumCapacityTag"
    },
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final primaryAmber = const Color(0xFFFFBF00);
    final l10n = AppLocalizations.of(context)!; // Get the localization instance

    return Scaffold(
      backgroundColor: colorScheme.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildCustomHeader(context, primaryAmber, l10n),
            const SizedBox(height: 16),
            _buildVehicleTabs(context, primaryAmber, l10n),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildVehicleGrid(context, lightVehicles, primaryAmber, l10n),
                  _buildVehicleGrid(context, heavyVehicles, primaryAmber, l10n),
                ],
              ),
            ),
            _buildBottomButtons(context, primaryAmber, l10n),
          ],
        ),
      ),
    );
  }

  // Header with back button and title
  Widget _buildCustomHeader(BuildContext context, Color primaryAmber, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_ios, color: primaryAmber, size: 24),
            onPressed: () => Navigator.of(context).pop(),
            style: IconButton.styleFrom(
              backgroundColor: primaryAmber.withOpacity(0.1),
              padding: const EdgeInsets.all(12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          Expanded(
            child: Text(
              l10n.vehicleType, // Use localized key
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onBackground,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  // Vehicle type tabs
  Widget _buildVehicleTabs(BuildContext context, Color primaryAmber, AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: TabBar(
          controller: _tabController,
          indicator: BoxDecoration(
            color: primaryAmber,
            borderRadius: BorderRadius.circular(12),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          labelColor: Colors.white,
          unselectedLabelColor: colorScheme.onSurface.withOpacity(0.7),
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          tabs: [
            Tab(text: l10n.lightVehicles), // Use localized key
            Tab(text: l10n.heavyVehicles), // Use localized key
          ],
          onTap: (index) {
            setState(() {
              _selectedVehicleIndex = index == 0 ? 0 : lightVehicles.length;
            });
          },
        ),
      ),
    );
  }

  // Vehicle grid view
  Widget _buildVehicleGrid(BuildContext context, List<Map<String, dynamic>> vehicles, Color primaryAmber, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.75,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: vehicles.length,
        itemBuilder: (context, index) {
          final adjustedIndex = (_tabController.index == 0) ? index : index + lightVehicles.length;
          final isSelected = _selectedVehicleIndex == adjustedIndex;
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedVehicleIndex = adjustedIndex;
              });
              HapticFeedback.mediumImpact();
            },
            child: _buildVehicleCard(context, vehicles[index], isSelected, primaryAmber, l10n),
          );
        },
      ),
    );
  }

  Widget _buildVehicleCard(BuildContext context, Map<String, dynamic> vehicle, bool isSelected, Color primaryAmber, AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: isSelected ? Border.all(color: primaryAmber, width: 3) : null,
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(isSelected ? 0.2 : 0.05),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Image.asset(
                    vehicle['image'],
                    fit: BoxFit.contain,
                    height: double.infinity,
                  ),
                ),
            
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _getLocalizedType(vehicle['typeKey'], l10n), // Dynamically get the localized type
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.fitness_center_rounded, color: primaryAmber, size: 16),
              const SizedBox(width: 4),
              Text(
                l10n.weightUpTo(vehicle['weight']), // Use parameterized key for weight
                style: TextStyle(
                  color: colorScheme.onSurface.withOpacity(0.8),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Bottom buttons
  Widget _buildBottomButtons(BuildContext context, Color primaryAmber, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryAmber,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 4,
                shadowColor: primaryAmber.withOpacity(0.4),
              ),
              onPressed: () {
                HapticFeedback.mediumImpact();
                final allVehicles = [...lightVehicles, ...heavyVehicles];
                final selectedVehicle = allVehicles[_selectedVehicleIndex];
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VehicleDetailScreen(
                      type: selectedVehicle['typeCode'],
                      image: selectedVehicle['image'],
                      pickupLocation: widget.pickup,
                      dropOffDestination: widget.dropOffDestination,
                      pickup_name: widget.pickup_name,
                    ),
                  ),
                );
              },
              child: Text(
                l10n.continueButton, // Use localized key
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  // Helper methods to get localized strings
  String _getLocalizedType(String key, AppLocalizations l10n) {
    switch (key) {
      case 'moto': return l10n.moto;
      case 'smallUtility': return l10n.smallUtility;
      case 'van': return l10n.van;
      case 'van35T': return l10n.van35T;
      case 'largeVan': return l10n.largeVan;
      case 'heavyTruck': return l10n.heavyTruck;
      case 'superHeavyTruck': return l10n.superHeavyTruck;
      default: return '';
    }
  }


}