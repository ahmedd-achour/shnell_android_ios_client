import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:shnell/jobType.dart';
import 'package:shnell/model/destinationdata.dart';
import 'package:shnell/selectionType.dart'; 
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

// --- Data Model ---
class ItemCategory {
  final String id;
  final String title;
  final String iconAsset;
  final double approxKg;
  final double approxM3;
  int quantity;

  ItemCategory({
    required this.id,
    required this.title,
    required this.iconAsset,
    required this.approxKg,
    required this.approxM3,
    this.quantity = 0,
  });
}

class ItemSelectionScreen extends StatefulWidget {
  final LatLng pickup;
  final List<DropOffData> dropOffDestination;
  final String pickupName;

  const ItemSelectionScreen({
    super.key,
    required this.pickup,
    required this.dropOffDestination,
    required this.pickupName,
  });

  @override
  State<ItemSelectionScreen> createState() => _ItemSelectionScreenState();
}

class _ItemSelectionScreenState extends State<ItemSelectionScreen> {
  late List<ItemCategory> _row1Moves;
  late List<ItemCategory> _row2Furniture;
  late List<ItemCategory> _row3Appliances;
  late List<ItemCategory> _row4Misc;

  @override
  void initState() {
    super.initState();

    // ROW 1: FULL MOVES (CLASS CHOICE)
    _row1Moves = [
      ItemCategory(id: 'petit_demenagement', title: 'Studio', iconAsset: 'assets/icons/moving-home.png', approxKg: 600.0, approxM3: 6.0),
      ItemCategory(id: 'grand_demenagement', title: 'House', iconAsset: 'assets/icons/house.png', approxKg: 1500.0, approxM3: 15.0),
      ItemCategory(id: 'office', title: 'Office', iconAsset: 'assets/icons/office.png', approxKg: 800.0, approxM3: 8.0),
    ];

    // ROW 2: HEAVY FURNITURE
    _row2Furniture = [
      ItemCategory(id: 'sofa', title: 'Sofa', iconAsset: 'assets/icons/seater-sofa.png', approxKg: 80.0, approxM3: 1.5),
      ItemCategory(id: 'double_bed', title: 'Double Bed', iconAsset: 'assets/icons/double-bed.png', approxKg: 70.0, approxM3: 1.2),
      ItemCategory(id: 'closet', title: 'Wardrobe', iconAsset: 'assets/icons/closet.png', approxKg: 90.0, approxM3: 1.0),
    ];

    // ROW 3: APPLIANCES & GENERAL
    _row3Appliances = [
      ItemCategory(id: 'fridge', title: 'Fridge', iconAsset: 'assets/icons/fridge.png', approxKg: 75.0, approxM3: 0.8),
      ItemCategory(id: 'washing', title: 'Washing M.', iconAsset: 'assets/icons/laundry-machine.png', approxKg: 70.0, approxM3: 0.6),
      ItemCategory(id: 'fornitures', title: 'General / Mix', iconAsset: 'assets/icons/furniture.png', approxKg: 200.0, approxM3: 2.5),
    ];

    // ROW 4: PACKS & LIGHT LOADS
    _row4Misc = [
      ItemCategory(id: 'shopping', title: 'Shopping', iconAsset: 'assets/icons/shopping-bag.png', approxKg: 20.0, approxM3: 0.1),
      ItemCategory(id: 'vegetables', title: 'Market/Veg', iconAsset: 'assets/icons/vegetables.png', approxKg: 50.0, approxM3: 0.2), 
      ItemCategory(id: 'others', title: 'Boxes', iconAsset: 'assets/icons/box.png', approxKg: 15.0, approxM3: 0.1),
    ];
  }

  List<ItemCategory> get _allCategories => [
        ..._row1Moves,
        ..._row2Furniture,
        ..._row3Appliances,
        ..._row4Misc,
      ];

  ({double kg, double m3}) _calculateLoad() {
    double kg = 0, m3 = 0;
    for (var cat in _allCategories) {
      kg += cat.quantity * cat.approxKg;
      m3 += cat.quantity * cat.approxM3;
    }
    return (kg: kg * 1.1, m3: m3 * 1.1);
  }

  double _calculatePriceMultiplier() {
    final load = _calculateLoad();
    // Simplified logic for brevity
    if (load.kg > 1200 || load.m3 > 12) return 2.5; 
    if (load.kg > 600) return 1.8; 
    if (load.kg > 200) return 1.4; 
    return 1.0; 
  }

  void _onMainButtonAction() {
    final hasSelection = _allCategories.any((c) => c.quantity > 0);
    HapticFeedback.mediumImpact();

    if (hasSelection) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VehicleSelectionScreen(
            pickup: widget.pickup,
            dropOffDestination: widget.dropOffDestination,
            pickup_name: widget.pickupName,
            priceMultiplier: _calculatePriceMultiplier(),
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ServiceTypeSelectionScreen(
            pickup: widget.pickup,
            dropOffDestination: widget.dropOffDestination,
            pickupName: widget.pickupName,
          ),
        ),
      );
    }
  }

  void _updateQuantity(ItemCategory item, int delta) {
    setState(() {
      final newQty = item.quantity + delta;
      item.quantity = newQty.clamp(0, 99);
    });
    if (delta > 0) HapticFeedback.selectionClick();
  }

  // Helper to ensure only one "Class" is selected at a time (Optional - for better UX)
  void _selectClass(ItemCategory selectedItem) {
    setState(() {
      // If tapping the same one, toggle off. If tapping a new one, switch to it.
      bool isAlreadySelected = selectedItem.quantity > 0;
      
      // Reset all row 1 items to 0
      for (var item in _row1Moves) {
        item.quantity = 0;
      }

      // If it wasn't selected, select it now (set qty to 1)
      if (!isAlreadySelected) {
        selectedItem.quantity = 1;
        HapticFeedback.heavyImpact();
      } else {
        HapticFeedback.selectionClick();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;
    final hasSelection = _allCategories.any((c) => c.quantity > 0);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.serviceTypeTitle),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(size.width * 0.04, 10, size.width * 0.04, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- NEW CLASS CHOICE SECTION ---
                    Text(
                      "BASE MOVE TYPE", 
                      style: TextStyle(
                        fontSize: 12, 
                        fontWeight: FontWeight.w900, 
                        letterSpacing: 1.2, 
                        color: colorScheme.primary
                      )
                    ),
                    const SizedBox(height: 10),
                    
                    // The Distinct Row 1
                    Row(
                      children: [
                        Expanded(child: _MainClassCard(item: _row1Moves[0], onTap: () => _selectClass(_row1Moves[0]))),
                        const SizedBox(width: 10),
                        Expanded(child: _MainClassCard(item: _row1Moves[1], onTap: () => _selectClass(_row1Moves[1]))),
                        const SizedBox(width: 10),
                        Expanded(child: _MainClassCard(item: _row1Moves[2], onTap: () => _selectClass(_row1Moves[2]))),
                      ],
                    ),

                    const SizedBox(height: 24),
                    const Divider(height: 1),
                    const SizedBox(height: 24),

                    // --- INVENTORY GRID SECTION ---
                    _buildSectionTitle("Heavy Furniture"),
                    _buildGridRow(_row2Furniture),
                    const SizedBox(height: 20),

                    _buildSectionTitle("Appliances & General"),
                    _buildGridRow(_row3Appliances),
                    const SizedBox(height: 20),

                    _buildSectionTitle("Packs & Shopping"),
                    _buildGridRow(_row4Misc),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      
      // Floating Action Button remains the same...
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: _buildBottomButton(hasSelection, colorScheme),
    );
  }

  Widget _buildBottomButton(bool hasSelection, ColorScheme colorScheme) {
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
              onPressed: _onMainButtonAction,
              style: FilledButton.styleFrom(
                backgroundColor: hasSelection ? colorScheme.primary : colorScheme.surfaceContainerHighest,
                foregroundColor: hasSelection ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              child: AnimatedSwitcher(
                 duration: const Duration(milliseconds: 300),
                 child: Text(
                  hasSelection 
                    ? 'Find Truck (~${_calculateLoad().kg.round()} kg)' 
                    : "I'm Not Sure",
                  key: ValueKey(hasSelection),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ),
      );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }

  Widget _buildGridRow(List<ItemCategory> items) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _ProItemCard(item: items[0], onUpdate: (d) => _updateQuantity(items[0], d))),
        const SizedBox(width: 12),
        Expanded(child: _ProItemCard(item: items[1], onUpdate: (d) => _updateQuantity(items[1], d))),
        const SizedBox(width: 12),
        Expanded(child: _ProItemCard(item: items[2], onUpdate: (d) => _updateQuantity(items[2], d))),
      ],
    );
  }
}

// --- NEW SPECIAL CARD FOR ROW 1 (CLASS CHOICE) ---
class _MainClassCard extends StatelessWidget {
  final ItemCategory item;
  final VoidCallback onTap;

  const _MainClassCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSelected = item.quantity > 0;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        height: 150, // Taller than standard cards
        decoration: BoxDecoration(
          // If selected, use a strong primary color fill, otherwise surface
          color: isSelected ? theme.colorScheme.primary : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant.withOpacity(0.5),
            width: isSelected ? 0 : 1.5,
          ),
          boxShadow: isSelected 
            ? [BoxShadow(color: theme.colorScheme.primary.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 6))]
            : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withOpacity(0.2) : theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: Image.asset(
                item.iconAsset,
                width: 40,
                height: 40,
                color: isSelected ? Colors.white : null, // Optional: white icon on active
              ),
            ),
            const SizedBox(height: 12),
            
            // Title
            Text(
              item.title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: isSelected ? Colors.white : theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            
            // Hint for Price/Size (The "Class" indicator)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? Colors.black.withOpacity(0.1) : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8)
              ),
              child: Text(
                "~${item.approxM3.toStringAsFixed(0)}m³", // Shows volume hint
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white.withOpacity(0.9) : theme.colorScheme.secondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- STANDARD ASSET CARD (Rows 2,3,4) ---
class _ProItemCard extends StatelessWidget {
  final ItemCategory item;
  final Function(int) onUpdate;

  const _ProItemCard({required this.item, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSelected = item.quantity > 0;
    
    return GestureDetector(
      onTap: () => onUpdate(1),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 120, // Shorter than Class Card
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primaryContainer.withOpacity(0.3) : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? theme.colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              top: 15,
              child: Column(
                children: [
                  Opacity(
                    opacity: isSelected ? 1.0 : 0.7,
                    child: Image.asset(item.iconAsset, width: 40, height: 40)
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),

            // Stepper (Only appears when selected)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: AnimatedOpacity(
                opacity: isSelected ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  height: 32,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _TapZone(icon: Icons.remove, onTap: () => onUpdate(-1), color: theme.colorScheme.primary),
                      Text('${item.quantity}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                      _TapZone(icon: Icons.add, onTap: () => onUpdate(1), color: theme.colorScheme.primary),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TapZone extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  const _TapZone({required this.icon, required this.onTap, required this.color});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque, 
      child: SizedBox(
        width: 30,
        height: 36,
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }
}