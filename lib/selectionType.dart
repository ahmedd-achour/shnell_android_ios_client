
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:shnell/VehiculeDetail.dart';
import 'package:shnell/dots.dart';
import 'package:shnell/model/destinationdata.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class VehicleUiModel {
  final String id;
  final String name;
  final String imagePath;
  final double maxWeight;
  final String weightDisplay;
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
  final List<String>? filterVehicleIds;
  final String? serviceTypeId;
  final double priceMultiplier;

  const VehicleSelectionScreen({
    super.key,
    required this.pickup,
    required this.dropOffDestination,
    required this.pickup_name,
    this.filterVehicleIds,
    this.serviceTypeId,
    required this.priceMultiplier,
  });

  @override
  State<VehicleSelectionScreen> createState() => _VehicleSelectionScreenState();
}

class _VehicleSelectionScreenState extends State<VehicleSelectionScreen>
    with SingleTickerProviderStateMixin {
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

  Future<void> _fetchVehiclesFromCloud() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('vehicles')
          .get();

      if (!doc.exists || doc.data() == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final data = doc.data() as Map<String, dynamic>;
      List<VehicleUiModel> light = [];
      List<VehicleUiModel> heavy = [];

      data.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          final double weight = (value['max_weight'] ?? 0).toDouble();
          final String image = _getLocalImageForType(key);

          final String weightStr = weight >= 1000
              ? "${(weight / 1000).toStringAsFixed(1).replaceAll('.0', '')} T"
              : "${weight.toStringAsFixed(0)} kg";

          final bool isRecommended = widget.filterVehicleIds == null ||
              widget.filterVehicleIds!.isEmpty ||
              widget.filterVehicleIds!.contains(key);

          final vehicle = VehicleUiModel(
            id: key,
            name: value['name']?.toString() ?? 'Unknown',
            imagePath: image,
            maxWeight: weight,
            weightDisplay: weightStr,
            isRecommended: isRecommended,
          );

          if (weight < 3500) {
            light.add(vehicle);
          } else {
            heavy.add(vehicle);
          }
        }
      });

      light.sort((a, b) => a.maxWeight.compareTo(b.maxWeight));
      heavy.sort((a, b) => a.maxWeight.compareTo(b.maxWeight));

      if (mounted) {
        setState(() {
          _lightVehicles = light;
          _heavyVehicles = heavy;

          // Auto-select first recommended vehicle
          final all = [...light, ...heavy];
          final recommended = all.where((v) => v.isRecommended).toList();

          if (recommended.isNotEmpty) {
            _selectedVehicleId = recommended.first.id;
            if (heavy.contains(recommended.first)) {
              _tabController.animateTo(1);
            }
          }
          // If no recommended, leave unselected → button stays disabled

          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading vehicles: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getLocalImageForType(String type) {
    switch (type) {
      case 'super_light':
        return "assets/super_light.png";
      case 'light':
        return "assets/light.png";
      case 'light_medium':
        return "assets/isuzu.png";
      case 'medium':
        return "assets/medium.png";
      case 'medium_heavy':
        return "assets/medium_heavy.png";
      case 'heavy':
        return "assets/heavy.png";
      case 'super_heavy':
        return "assets/super_heavy.png";
      default:
        return "assets/light.png";
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
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
            _buildHeader(colorScheme, l10n),
            const SizedBox(height: 16),
            _buildTabs(colorScheme, l10n),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildGrid(_lightVehicles),
                  _buildGrid(_heavyVehicles),
                ],
              ),
            ),
            _buildBottomButton(colorScheme, l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: colorScheme.surfaceContainerHighest,
            child: IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: colorScheme.onSurface),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              l10n.vehicleType,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildTabs(ColorScheme colorScheme, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        child: TabBar(
          controller: _tabController,
          indicator: BoxDecoration(
            color: colorScheme.primary,
            borderRadius: BorderRadius.circular(16),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          labelColor: colorScheme.onPrimary,
          unselectedLabelColor: colorScheme.onSurfaceVariant,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          tabs: [
            Tab(text: l10n.lightVehicles),
            Tab(text: l10n.heavyVehicles),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(List<VehicleUiModel> vehicles) {
    if (vehicles.isEmpty) {
      return Center(
        child: Text(
          "No vehicles available",
          style: const TextStyle(fontSize: 16),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.78,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
      ),
      itemCount: vehicles.length,
      itemBuilder: (context, index) {
        final vehicle = vehicles[index];
        final isSelected = _selectedVehicleId == vehicle.id;

        return GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() => _selectedVehicleId = vehicle.id);
          },
          child: _buildVehicleCard(vehicle, isSelected),
        );
      },
    );
  }

  Widget _buildVehicleCard(VehicleUiModel vehicle, bool isSelected) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool isRecommended = vehicle.isRecommended;
    final bool showWarning = isSelected && !isRecommended;

    final double opacity = isSelected ? 1.0 : (isRecommended ? 1.0 : 0.45);
    final Color borderColor = isSelected
        ? (isRecommended ? colorScheme.primary : Colors.orange.shade600)
        : Colors.transparent;

    return Opacity(
      opacity: opacity,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: borderColor, width: isSelected ? 3.5 : 1.5),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? colorScheme.primary.withOpacity(0.3)
                  : Colors.black.withOpacity(0.06),
              blurRadius: isSelected ? 20 : 12,
              offset: Offset(0, isSelected ? 10 : 6),
            ),
          ],
        ),
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: Center(
                    child: Image.asset(
                      vehicle.imagePath,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.local_shipping_rounded,
                        size: 90,
                        color: colorScheme.outline,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  vehicle.name,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.fitness_center_rounded,
                        size: 20, color: colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      vehicle.weightDisplay,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // "Not suitable" label when not selected & not recommended
            if (!isSelected && !isRecommended)
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainer.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    AppLocalizations.of(context)!.notSuitable,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),

            // Warning badge when selected but not allowed
            if (showWarning)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.orange.shade600, width: 2.5),
                  ),
                  child: Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange.shade700,
                    size: 26,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomButton(ColorScheme colorScheme, AppLocalizations l10n) {
    final allVehicles = [..._lightVehicles, ..._heavyVehicles];
    final selectedVehicle = allVehicles
        .firstWhereOrNull((v) => v.id == _selectedVehicleId);

    final bool canProceed = selectedVehicle != null && selectedVehicle.isRecommended;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 34),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          width: double.infinity,
          child: FilledButton(
            onPressed: canProceed
                ? () {
                    HapticFeedback.mediumImpact();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VehicleDetailScreen(
                          type: selectedVehicle.id,
                          image: selectedVehicle.imagePath,
                          pickupLocation: widget.pickup,
                          dropOffDestination: widget.dropOffDestination,
                          pickup_name: widget.pickup_name,
                          serviceTypeId: widget.serviceTypeId,
                        ),
                      ),
                    );
                  }
                : (){

                },
            style: FilledButton.styleFrom(
              backgroundColor: canProceed
                  ? colorScheme.primary
                  : colorScheme.surfaceContainerHighest,
              foregroundColor: canProceed
                  ? colorScheme.onPrimary
                  : colorScheme.onSurfaceVariant,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: canProceed ? 8 : 0,
            ),
            child: Text(
              l10n.continueButton,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}