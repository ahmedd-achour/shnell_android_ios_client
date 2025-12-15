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
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          // === ICON CONTAINER – FULL COVERAGE ===
          ClipRRect(
            borderRadius: BorderRadius.circular(18), // Slightly rounded for elegance
            child: Container(
              width: 80,
              height: 80,
              color: isSelected
                  ? colorScheme.primary.withOpacity(0.18)
                  : colorScheme.primaryContainer.withOpacity(0.35),
              child: Image.asset(
                data.iconAsset,
                fit: BoxFit.cover, // ← Critical: covers entire space, including edges
                width: 80,
                height: 80,
                // Optional: slight tint when selected, but keeps image clear
                color: isSelected
                    ? colorScheme.primary.withOpacity(0.25)
                    : null,
                colorBlendMode: isSelected ? BlendMode.srcATop : null,
              ),
            ),
          ),

          const SizedBox(width: 20),

          // === TEXT CONTENT ===
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18.5,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 14.5,
                    color: colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // === SELECTION CHECKMARK ===
          AnimatedScale(
            scale: isSelected ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.elasticOut,
            child: Icon(
              Icons.check_circle_rounded,
              color: colorScheme.primary,
              size: 34,
            ),
          ),
        ],
      ),
    ),
  );
}
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