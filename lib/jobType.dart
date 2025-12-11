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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context, colorScheme, l10n),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                children: [
                  Text(
                    l10n.serviceTypeTitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: colorScheme.onSurface),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.serviceTypeSubtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                itemCount: _serviceTypes.length,
                separatorBuilder: (ctx, i) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final type = _serviceTypes[index];
                  final isSelected = _selectedTypeId == type.id;
                  return _buildServiceCard(type, isSelected, colorScheme, l10n);
                },
              ),
            ),
            _buildBottomBar(colorScheme, l10n),
          ],
        ),
      ),
    );
  }
  
  Widget _buildHeader(BuildContext context, ColorScheme colorScheme, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: colorScheme.surfaceContainerHighest,
            foregroundColor: colorScheme.onSurface,
            child: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
          ),
          const Spacer(),
          
        ],
      ),
    );
  }

  Widget _buildServiceCard(ServiceTypeUiModel data, bool isSelected, ColorScheme colorScheme, AppLocalizations l10n) {
    final title = _getLocalizedTitle(data.id, l10n, data.title);
    final subtitle = _getLocalizedSubtitle(data.id, l10n, data.subtitle);

    return GestureDetector(
      onTap: () { setState(() => _selectedTypeId = data.id); HapticFeedback.lightImpact(); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primaryContainer : colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? colorScheme.primary : Colors.transparent, width: 2),
        ),
        child: Row(
          children: [
            SizedBox(width: 50, height: 50, child: Image.asset(data.iconAsset, fit: BoxFit.cover)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
                  Text(subtitle, style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            if (isSelected) Icon(Icons.check_circle, color: colorScheme.primary),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(ColorScheme colorScheme, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 34),
      decoration: BoxDecoration(color: colorScheme.surface, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, -5))]),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: _selectedTypeId != null ? _onContinue : null,
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          child: Text(l10n.continueText.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
      ),
    );
  }
}