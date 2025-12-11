import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:shnell/VehiculeDetail.dart';
import 'package:shnell/dots.dart'; // RotatingDotsIndicator
import 'package:shnell/model/destinationdata.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

// Helper model for the UI
class VehicleUiModel {
  final String id;
  final String name;
  final String imagePath;
  final double maxWeight;
  final String weightDisplay;
  
  // NEW: Smart Display Logic
  final bool isRecommended; 

  VehicleUiModel({
    required this.id,
    required this.name,
    required this.imagePath,
    required this.maxWeight,
    required this.weightDisplay,
    required this.isRecommended,
  });
}

class VehicleSelectionScreen extends StatefulWidget {
  final LatLng pickup;
  final List<DropOffData> dropOffDestination;
  final String pickup_name;
  
  // NEW: Filter list from previous screen
  final List<String>? filterVehicleIds; 
  // NEW: Pass service type ID forward
  final String? serviceTypeId;
  final double  priceMultiplier;

   VehicleSelectionScreen({
    super.key,
    required this.pickup,
    required this.dropOffDestination,
    required this.pickup_name,
    this.filterVehicleIds,
    this.serviceTypeId,
    required this.priceMultiplier,
    t
  });

  @override
  _VehicleSelectionScreenState createState() => _VehicleSelectionScreenState();
}

class _VehicleSelectionScreenState extends State<VehicleSelectionScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  bool _isLoading = true;
  List<VehicleUiModel> _lightVehicles = [];
  List<VehicleUiModel> _heavyVehicles = [];
  String? _selectedVehicleId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchVehiclesFromCloud();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // --- 1. CLOUD FETCHING LOGIC ---
  Future<void> _fetchVehiclesFromCloud() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('settings').doc('vehicles').get();
      
      if (doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;
        
        List<VehicleUiModel> tempLight = [];
        List<VehicleUiModel> tempHeavy = [];

        data.forEach((key, value) {
          if (value is Map<String, dynamic>) {
            double weight = (value['max_weight'] ?? 0).toDouble();
            String image = _getLocalImageForType(key);
            
            String weightStr = weight >= 1000 
                ? "${(weight / 1000).toStringAsFixed(1).replaceAll('.0', '')} T" 
                : "${weight.toStringAsFixed(0)} kg";

            // SMART FILTER LOGIC
            bool recommended = true;
            if (widget.filterVehicleIds != null && widget.filterVehicleIds!.isNotEmpty) {
              recommended = widget.filterVehicleIds!.contains(key);
            }

            final vehicle = VehicleUiModel(
              id: key,
              name: value['name'] ?? 'Unknown',
              imagePath: image,
              maxWeight: weight,
              weightDisplay: weightStr,
              isRecommended: recommended,
            );

            if (weight < 3500) {
              tempLight.add(vehicle);
            } else {
              tempHeavy.add(vehicle);
            }
          }
        });

        tempLight.sort((a, b) => a.maxWeight.compareTo(b.maxWeight));
        tempHeavy.sort((a, b) => a.maxWeight.compareTo(b.maxWeight));

        if (mounted) {
          setState(() {
            _lightVehicles = tempLight;
            _heavyVehicles = tempHeavy;
            
            // Auto-select logic: Pick first RECOMMENDED option
            try {
              if (_lightVehicles.any((v) => v.isRecommended)) {
                _selectedVehicleId = _lightVehicles.firstWhere((v) => v.isRecommended).id;
              } else if (_heavyVehicles.any((v) => v.isRecommended)) {
                _selectedVehicleId = _heavyVehicles.firstWhere((v) => v.isRecommended).id;
                _tabController.animateTo(1);
              } else {
                if (_lightVehicles.isNotEmpty) _selectedVehicleId = _lightVehicles.first.id;
              }
            } catch (e) { /* ignore */ }
            
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching vehicles: $e");
      if(mounted) setState(() => _isLoading = false);
    }
  }

  String _getLocalImageForType(String type) {
    switch (type) {
      case 'super_light': return "assets/super_light.png"; 
      case 'light': return "assets/light.png";
      case 'light_medium': return "assets/isuzu.png";
      case 'medium': return "assets/medium.png";
      case 'medium_heavy': return "assets/medium_heavy.png";
      case 'heavy': return "assets/heavy.png";
      case 'super_heavy': return "assets/super_heavy.png";
      default: return "assets/light.png"; 
    }
  }

  // --- UI BUILDING ---

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        body: const Center(child: RotatingDotsIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            _buildCustomHeader(context, colorScheme, l10n),
            const SizedBox(height: 16),
            _buildVehicleTabs(context, colorScheme, l10n),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildVehicleGrid(context, _lightVehicles, colorScheme),
                  _buildVehicleGrid(context, _heavyVehicles, colorScheme),
                ],
              ),
            ),
            _buildBottomButtons(context, colorScheme, l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomHeader(BuildContext context, ColorScheme colorScheme, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: colorScheme.surfaceContainerHighest,
            foregroundColor: colorScheme.onSurface,
            child: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
              tooltip: 'Back',
            ),
          ),
          Expanded(
            child: Text(
              l10n.vehicleType,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurface,
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

  Widget _buildVehicleTabs(BuildContext context, ColorScheme colorScheme, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: TabBar(
          controller: _tabController,
          indicator: BoxDecoration(
            color: colorScheme.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          labelColor: colorScheme.onPrimary,
          unselectedLabelColor: colorScheme.onSurfaceVariant,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          tabs: [
            Tab(text: l10n.lightVehicles),
            Tab(text: l10n.heavyVehicles),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleGrid(BuildContext context, List<VehicleUiModel> vehicles, ColorScheme colorScheme) {
    if (vehicles.isEmpty) {
      return Center(child: Text("No vehicles available", style: TextStyle(color: colorScheme.onSurfaceVariant)));
    }

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
          final vehicle = vehicles[index];
          final isSelected = _selectedVehicleId == vehicle.id;
          
          return GestureDetector(
            onTap: () {
              if (!vehicle.isRecommended) {
                HapticFeedback.lightImpact(); // Subtle feedback for warning
              } else {
                HapticFeedback.mediumImpact();
              }
              setState(() {
                _selectedVehicleId = vehicle.id;
              });
            },
            child: _buildVehicleCard(context, vehicle, isSelected, colorScheme),
          );
        },
      ),
    );
  }

  Widget _buildVehicleCard(BuildContext context, VehicleUiModel vehicle, bool isSelected, ColorScheme colorScheme) {
    // VISUAL LOGIC: Reduce opacity if not recommended
    final double opacity = vehicle.isRecommended ? 1.0 : 0.4;
    
    // Border logic: Orange if selected but not recommended
    Color borderColor = Colors.transparent;
    if (isSelected) {
      borderColor = vehicle.isRecommended ? colorScheme.primary : Colors.orange;
    }

    return Opacity(
      opacity: isSelected ? 1.0 : opacity, // Keep fully visible if selected
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 3),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withOpacity(isSelected ? 0.15 : 0.05),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Image.asset(
                      vehicle.imagePath,
                      fit: BoxFit.contain,
                      height: double.infinity,
                      errorBuilder: (ctx, err, stack) => Icon(Icons.local_shipping, size: 60, color: colorScheme.outline),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  vehicle.name,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.fitness_center_rounded, color: colorScheme.primary, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      vehicle.weightDisplay,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            
            // Warning Icon
            if (!vehicle.isRecommended && isSelected)
              const Positioned(
                top: 0,
                right: 0,
                child: Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
              )
          ],
        ),
      ),
    );
  }

  Widget _buildBottomButtons(BuildContext context, ColorScheme colorScheme, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 4,
              ),
              onPressed: _selectedVehicleId == null ? null : () {
                final allVehicles = [..._lightVehicles, ..._heavyVehicles];
                final selected = allVehicles.firstWhere((v) => v.id == _selectedVehicleId);

                // WARNING DIALOG if not recommended
                if (!selected.isRecommended) {
                  _showWarningDialog(context, selected);
                } else {
                  _navigateToDetail(context, selected);
                }
              },
              child: Text(
                l10n.continueButton,
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

  void _showWarningDialog(BuildContext context, VehicleUiModel selected) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Vehicle Warning"),
        content: Text("The ${selected.name} might not be suitable for your selected job type. Are you sure you want to proceed?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx), 
            child: const Text("Cancel")
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _navigateToDetail(context, selected);
            },
            child: const Text("Continue Anyway"),
          )
        ],
      ),
    );
  }

  void _navigateToDetail(BuildContext context, VehicleUiModel selected) {
    HapticFeedback.mediumImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VehicleDetailScreen(
          type: selected.id,
          image: selected.imagePath,
          pickupLocation: widget.pickup,
          dropOffDestination: widget.dropOffDestination,
          pickup_name: widget.pickup_name,
          serviceTypeId: widget.serviceTypeId,),
      ),
    );
  }
}