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
      } else {
        if(mounted) setState(() => _isLoading = false);
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
          pickup: widget.pickup,
          dropOffDestination: widget.dropOffDestination,
          pickup_name: widget.pickupName,
          filterVehicleIds: selectedService.allowedVehicles,
          serviceTypeId: selectedService.id,
          priceMultiplier: selectedService.priceMultiplier, 
        ),
      ),
    );
  }

  // --- LOCALIZATION HELPERS ---
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
            // === HEADER ===
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.serviceTypeTitle,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: colorScheme.onSurface,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          l10n.serviceTypeSubtitle,
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // === LIST ===
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                itemCount: _serviceTypes.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final type = _serviceTypes[index];
                  final isSelected = _selectedTypeId == type.id;
                  return _buildServiceCard(type, isSelected, colorScheme, l10n);
                },
              ),
            ),

            // === BOTTOM BAR ===
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
    final detailIcons = _getDetailIcons(data.id);

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _selectedTypeId = data.id);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          // Logic: Subtle background change, clear border
          color: isSelected
              ? colorScheme.primaryContainer.withOpacity(0.3)
              : colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Icon Container
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(                    borderRadius: BorderRadius.circular(16),
                    // Removed shadow as requested
                    border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.3)),
                  ),
                  child: Image.asset(
                    data.iconAsset,
                    fit: BoxFit.fill,
                    // REMOVED: color/colorBlendMode to keep original asset colors
                  ),
                ),

                const SizedBox(width: 16),

                // 2. Text Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          // Selection Indicator
                          AnimatedScale(
                            scale: isSelected ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 200),
                            child: Icon(Icons.check_circle, color: colorScheme.primary, size: 24),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // 3. "Suitable For" Section
            if (detailIcons.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Divider(color: colorScheme.outlineVariant.withOpacity(0.3), height: 1),
              ),
              Row(
                children: [
                  Text(
                    l10n.bestValueTag, // Fallback
                    style: TextStyle(
                      fontSize: 11, 
                      color: colorScheme.primary, 
                      fontWeight: FontWeight.w600
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: detailIcons.map((asset) => Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: colorScheme.surface,
                              shape: BoxShape.circle,
                              border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.2)),
                            ),
                            padding: const EdgeInsets.all(6),
                            child: Image.asset(
                              asset,
                              fit: BoxFit.fill,
                              // Ensure no tint is applied here either
                            ),
                          ),
                        )).toList(),
                      ),
                    ),
                  )
                ],
              )
            ]
          ],
        ),
      ),
    );
  }

  // === ASSET MAPPING (Fixed Paths) ===
  List<String> _getDetailIcons(String serviceId) {
    switch (serviceId) {
      case 'simple_transport': 
        return [
          'assets/icons/shopping-bag.png',   
          'assets/icons/bicycle.png',      
        ];
      case 'store_pickup':
        return [
          'assets/icons/smart-tv.png',       
          'assets/icons/oven.png',
          'assets/icons/vegetables.png',           
        ];
      case 'small_move': 
        return [
          'assets/icons/fridge.png',          
          'assets/icons/laundry-machine.png', 
          'assets/icons/seater-sofa.png',  
          'assets/icons/double-bed.png',   
        ];
      case 'full_move': 
        return [
          'assets/icons/moving-home.png',     
          'assets/icons/office.png',          
          'assets/icons/furniture.png',           
          'assets/icons/treadmill.png',   
        ];
      default:
        return [];
    }
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
          // Reverted to FilledButton.tonal as requested
          child: FilledButton.tonal(
            onPressed: isEnabled ? _onContinue : null,
            style: FilledButton.styleFrom(
              backgroundColor: isEnabled ? colorScheme.primary : colorScheme.surfaceContainerHighest,
              foregroundColor: isEnabled ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              elevation: isEnabled ? 4 : 0,
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