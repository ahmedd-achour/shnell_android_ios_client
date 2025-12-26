import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:shnell/dots.dart'; 
import 'package:shnell/model/destinationdata.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:shnell/selectionType.dart';

// --- MODEL ---
class ServiceTypeUiModel {
  final String id;
  final String title;
  final String subtitle;
  final String iconAsset;
  final List<String> allowedVehicles;
  final double priceMultiplier; 

  ServiceTypeUiModel({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.iconAsset,
    required this.allowedVehicles,
    required this.priceMultiplier,
  });

  factory ServiceTypeUiModel.fromMap(Map<String, dynamic> map) {
    return ServiceTypeUiModel(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      subtitle: map['subtitle'] ?? '',
      iconAsset: map['icon_asset'] ?? 'assets/box.png',
      // Parse multiplier (default to 1.0 if missing)
      priceMultiplier: (map['price_multiplier'] ?? 1.0).toDouble(),
      allowedVehicles: List<String>.from(map['allowed_vehicles'] ?? []),
    );
  }
}

// --- SCREEN ---
class ServiceTypeSelectionScreen extends StatefulWidget {
  final LatLng pickup;
  final List<DropOffData> dropOffDestination;
  final String pickupName;

  const ServiceTypeSelectionScreen({
    super.key,
    required this.pickup,
    required this.dropOffDestination,
    required this.pickupName,
  });

  @override
  State<ServiceTypeSelectionScreen> createState() => _ServiceTypeSelectionScreenState();
}

class _ServiceTypeSelectionScreenState extends State<ServiceTypeSelectionScreen> {
  bool _isLoading = true;
  List<ServiceTypeUiModel> _serviceTypes = [];
  String? _selectedTypeId;

  @override
  void initState() {
    super.initState();
    _fetchServiceTypes();
  }

  Future<void> _fetchServiceTypes() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('settings').doc('service_types').get();
      
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        if (data['types'] is List) {
          final List<dynamic> rawList = data['types'];
          
          final parsedList = rawList.map((item) {
            return ServiceTypeUiModel.fromMap(item as Map<String, dynamic>);
          }).toList();

          if (mounted) {
            setState(() {
              _serviceTypes = parsedList;
              _isLoading = false;
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Error fetching service types: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onContinue() {
    if (_selectedTypeId == null) return;

    final selectedService = _serviceTypes.firstWhere((s) => s.id == _selectedTypeId);

    HapticFeedback.mediumImpact();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VehicleSelectionScreen(
          // --- PASS DATA FORWARD ---
          pickup: widget.pickup,
          dropOffDestination: widget.dropOffDestination,
          pickup_name: widget.pickupName,
          
          // 1. Filter vehicles based on service type
          filterVehicleIds: selectedService.allowedVehicles,
          
          // 2. Pass ID for tracking
          serviceTypeId: selectedService.id,
          
          // 3. Pass Multiplier for pricing calculation
          priceMultiplier: selectedService.priceMultiplier, 
        ),
      ),
    );
  }

  // --- LOCALIZATION HELPERS ---
  // Maps DB IDs to ARB Keys
  String _getLocalizedTitle(String id, AppLocalizations l10n, String fallback) {
    switch (id) {
      case 'simple_transport': return l10n.st_simple_transport_title;
      case 'store_pickup': return l10n.st_store_pickup_title;
      case 'small_move': return l10n.st_small_move_title;
      case 'full_move': return l10n.st_full_move_title;
      default: return fallback;
    }
  }

  String _getLocalizedSubtitle(String id, AppLocalizations l10n, String fallback) {
    switch (id) {
      case 'simple_transport': return l10n.st_simple_transport_sub;
      case 'store_pickup': return l10n.st_store_pickup_sub;
      case 'small_move': return l10n.st_small_move_sub;
      case 'full_move': return l10n.st_full_move_sub;
      default: return fallback;
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
          // === Enhanced Header ===
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 24, 8),
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
                    l10n.serviceTypeTitle,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              l10n.serviceTypeSubtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),

          const SizedBox(height: 24),

          // === Service Type Cards ===
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: _serviceTypes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final type = _serviceTypes[index];
                final isSelected = _selectedTypeId == type.id;

                return _buildServiceCard(type, isSelected, colorScheme, l10n);
              },
            ),
          ),

          // === Bottom Continue Button ===
          _buildBottomBar(colorScheme, l10n),
        ],
      ),
    ),
  );
}

Widget _buildServiceCard(
  ServiceTypeUiModel data,
  bool isSelected,
  ColorScheme colorScheme,
  AppLocalizations l10n,
) {
  final title = _getLocalizedTitle(data.id, l10n, data.title);
  final subtitle = _getLocalizedSubtitle(data.id, l10n, data.subtitle);
  return GestureDetector(
    onTap: () {
      HapticFeedback.lightImpact();
      setState(() => _selectedTypeId = data.id);
    },
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: isSelected
            ? colorScheme.primaryContainer.withOpacity(0.35)
            : colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isSelected ? colorScheme.primary : colorScheme.outline.withOpacity(0.15),
          width: isSelected ? 2.5 : 1,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: colorScheme.primary.withOpacity(0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // === 1. MAIN SERVICE IMAGE ===
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  width: 72,
                  height: 72,
                  color: isSelected
                      ? colorScheme.primary.withOpacity(0.18)
                      : colorScheme.primaryContainer.withOpacity(0.35),
                  child: Image.asset(
                    data.iconAsset,
                    fit: BoxFit.cover,
                    width: 72,
                    height: 72,
                    // Subtle tint blending for cohesion
                    color: isSelected ? colorScheme.primary.withOpacity(0.25) : null,
                    colorBlendMode: isSelected ? BlendMode.srcATop : null,
                  ),
                ),
              ),

              const SizedBox(width: 16),

              // === 2. TITLE & SUBTITLE ===
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // === 3. SELECTION CHECKMARK ===
              AnimatedScale(
                scale: isSelected ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Icon(
                  Icons.check_circle_rounded,
                  color: colorScheme.primary,
                  size: 28,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // === 4. BOTTOM ROW: PRICE & PREMIUM ASSETS ===
          Row(
            children: [
              // -- Avg Price Pill -

              // -- 3 Premium Detail Icons --
              ..._getDetailIcons(data.id).map((assetPath) => Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Image.asset(
                  assetPath,
                  width: 20,
                  height: 20,
                  // Optional: Tint them to match text color for a clean look, 
                  // or remove 'color' to keep original icon colors.
                ),
              )),
            ],
          )
        ],
      ),
    ),
  );
}

// === HELPER: MAPPING IDs TO ASSETS ===
// This keeps your build method clean.
List<String> _getDetailIcons(String serviceId) {
  switch (serviceId) {
    case 'simple_transport': // Small / Express / Store Pickup
    case 'store_pickup':
      return [
        'assets/icons/smart-tv.png',       // Electronics (Fragile)
        'assets/icons/vegetables.png', // Legumes/Market (Heavy/Commercial)
        'assets/icons/oven.png',           // Mouton/Aid (Cultural/Live Animal)
        'assets/icons/shopping-bag.png',    // Fashion/Retail
        'assets/icons/bicycle.png',         // Small Appliances
      ];
      
    case 'small_move': // Medium (Household Heavy)
      return [
        'assets/icons/fridge.png',          // #1 Heavy Item
        'assets/icons/laundry-machine.png', // Standard Appliance
        'assets/icons/double-bed.png',      // Bulky Furniture
        'assets/icons/seater-sofa.png',     // Long Furniture
        'assets/icons/motorcycle.png',         // <--- SUGGESTION: Fits in a medium van, very common transport need!
      ];
      
    case 'full_move': // Big (Spaces & Pro)
      return [
        'assets/icons/moving-home.png',     // Full House
        'assets/icons/office.png',          // B2B / Desk moves
        'assets/icons/furniture.png',           // Specialty / Heavy
        'assets/icons/treadmill.png',   // Complex Assembly
        'assets/icons/closet.png',            // Labor (3+ People)
      ];
      
    default:
      return [];
  }
}
// === Helper Widget for the small icons ===



Widget _buildBottomBar(ColorScheme colorScheme, AppLocalizations l10n) {
  final bool isEnabled = _selectedTypeId != null;

  return Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 34),
    decoration: BoxDecoration(
      color: colorScheme.surface,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.08),
          blurRadius: 20,
          offset: const Offset(0, -8),
        ),
      ],
    ),
    child: SafeArea(
      top: false,
      child: SizedBox(
        height: 56,
        child: FilledButton.tonal(
          onPressed: isEnabled ? _onContinue : null,
          style: FilledButton.styleFrom(
            backgroundColor: isEnabled ? colorScheme.primary : colorScheme.surfaceContainerHighest,
            foregroundColor: isEnabled ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            elevation: isEnabled ? 6 : 0,
            shadowColor: isEnabled ? colorScheme.primary.withOpacity(0.4) : Colors.transparent,
          ),
          child: Text(
            l10n.continueText,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    ),
  );
}

}