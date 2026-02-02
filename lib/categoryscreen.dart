import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import 'package:latlong2/latlong.dart';

import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:shnell/model/destinationdata.dart';
import 'package:shnell/selectionType.dart';



class ServiceTierSelectionScreen extends StatefulWidget {

  final LatLng pickup;

  final List<DropOffData> dropOffDestination;

  final String pickupName;

  final dynamic selectedService; // Receives the ServiceTypeUiModel



  const ServiceTierSelectionScreen({

    super.key,

    required this.pickup,

    required this.dropOffDestination,

    required this.pickupName,

    required this.selectedService,

  });



  @override

  State<ServiceTierSelectionScreen> createState() => _ServiceTierSelectionScreenState();

}



class _ServiceTierSelectionScreenState extends State<ServiceTierSelectionScreen> {

  String _selectedTier = 'eco'; 



void _onContinue() {
    
    // 1. Get the selected service model (contains the list of allowed vehicles)
    final selectedService = widget.selectedService; // Use the passed selectedService directly
    
    HapticFeedback.mediumImpact();

    // 2. Pass 'filterVehicleIds' to the next screen
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => VehicleSelectionScreen(
          pickup: widget.pickup,
          dropOffDestination: widget.dropOffDestination,
          pickup_name: widget.pickupName,
          // CRITICAL: This restricts the next screen to ONLY the vehicles allowed for this job
          filterVehicleIds: selectedService.allowedVehicles, 
          serviceTypeId: selectedService.id, // Optional: if your next screen needs the ID
          priceMultiplier: selectedService.priceMultiplier,
          category: _selectedTier, // 'eco' or 'pro'
        ),
      ),
    );
  }



  @override

  Widget build(BuildContext context) {

    final colorScheme = Theme.of(context).colorScheme;

    final l10n = AppLocalizations.of(context)!;



    return Scaffold(

      backgroundColor: colorScheme.surface,

      body: SafeArea(

        child: Column(

          children: [

            // === HEADER ===

            _buildHeader(colorScheme, l10n),



            // === TIER OPTIONS ===

            Expanded(

              child: ListView(

                padding: const EdgeInsets.symmetric(horizontal: 20),

                children: [

              // Inside the ListView of ServiceTierSelectionScreen

_buildTierCard(

  id: 'eco',

  title: l10n.eco_title,

  icon: Icons.savings,

  colorScheme: colorScheme,

  features: [

    l10n.eco_feature_trips,

    l10n.eco_feature_partner,

    l10n.eco_feature_price,

  ],

),

const SizedBox(height: 16),

_buildTierCard(

  id: 'pro',

  title: l10n.pro_title,

  icon: Icons.verified_user_rounded,

  colorScheme: colorScheme,

  features: [

    l10n.pro_feature_premium,

    l10n.pro_feature_guarantee,

    l10n.pro_feature_safety,

    l10n.pro_feature_agency,

  ],

), ],

              ),

            ),



            // === BOTTOM BAR ===

            _buildBottomBar(colorScheme, l10n),

          ],

        ),

      ),

    );

  }



  Widget _buildTierCard({

    required String id,

    required String title,

    required IconData icon,

    required ColorScheme colorScheme,

    required List<String> features,

  }) {

    final isSelected = _selectedTier == id;

    final primaryColor = colorScheme.primary;



    return GestureDetector(

      onTap: () {

        HapticFeedback.lightImpact();

        setState(() => _selectedTier = id);

      },

      child: AnimatedContainer(

        duration: const Duration(milliseconds: 300),

        curve: Curves.easeInOut,

        padding: const EdgeInsets.all(20),

        decoration: BoxDecoration(

          color: isSelected ? primaryColor.withOpacity(0.08) : colorScheme.surfaceContainerLow,

          borderRadius: BorderRadius.circular(24),

          border: Border.all(

            color: isSelected ? primaryColor : Colors.transparent,

            width: 2,

          ),

        ),

        child: Column(

          crossAxisAlignment: CrossAxisAlignment.start,

          children: [

            Row(

              children: [

                Container(

                  padding: const EdgeInsets.all(10),

                  decoration: BoxDecoration(

                    color: isSelected ? primaryColor : colorScheme.surface,

                    borderRadius: BorderRadius.circular(12),

                  ),

                  child: Icon(

                    icon,

                    color: isSelected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,

                    size: 24,

                  ),

                ),

                const SizedBox(width: 16),

                Text(

                  title,

                  style: TextStyle(

                    fontSize: 20,

                    fontWeight: FontWeight.w800,

                    color: colorScheme.onSurface,

                  ),

                ),

                const Spacer(),

                if (isSelected)

                  Icon(Icons.check_circle_rounded, color: primaryColor, size: 28),

              ],

            ),

            const Padding(

              padding: EdgeInsets.symmetric(vertical: 16),

              child: Divider(height: 1),

            ),

            ...features.map((feature) => Padding(

              padding: const EdgeInsets.only(bottom: 8),

              child: Row(

                children: [

                  Icon(Icons.done_all_rounded, size: 16, color: primaryColor),

                  const SizedBox(width: 12),

                  Expanded(

                    child: Text(

                      feature,

                      style: TextStyle(

                        fontSize: 14,

                        color: colorScheme.onSurfaceVariant,

                        fontWeight: FontWeight.w500,

                      ),

                    ),

                  ),

                ],

              ),

            )).toList(),

          ],

        ),

      ),

    );

  }



  Widget _buildHeader(ColorScheme colorScheme, AppLocalizations l10n) {

    return Padding(

      padding: const EdgeInsets.fromLTRB(16, 16, 24, 24),

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

          const SizedBox(width: 8),

          Text(

           l10n.serviceTypeTitle,

            style: TextStyle(

              fontSize: 22,

              fontWeight: FontWeight.w800,

              color: colorScheme.onSurface,

            ),

          ),

        ],

      ),

    );

  }



  Widget _buildBottomBar(ColorScheme colorScheme, AppLocalizations l10n) {

    return Container(

      padding: const EdgeInsets.fromLTRB(24, 16, 24, 34),

      decoration: BoxDecoration(

        color: colorScheme.surface,

        border: Border(top: BorderSide(color: colorScheme.outlineVariant, width: 0.5)),

      ),

      child: SizedBox(

        width: double.infinity,

        height: 56,

        child: FilledButton(

          onPressed: _onContinue,

          style: FilledButton.styleFrom(

            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),

          ),

          child: Text(

            l10n.continueText,

            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),

          ),

        ),

      ),

    );

  }

}