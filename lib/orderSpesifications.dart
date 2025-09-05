/*import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:shnell/VehiculeDetail.dart';
import 'package:shnell/model/destinationdata.dart'; // Assurez-vous d'importer l'écran des détails

// ... (vos autres imports et modèles de données restent les mêmes)

//############################################################################
// DATA MODELS AND DATASET
//############################################################################

class ShipmentItem {
  final String name;
  final IconData icon;
  final double? volume;
  final double? weight;
  final List<ShipmentOption>? options;

  ShipmentItem({
    required this.name,
    required this.icon,
    this.volume,
    this.weight,
    this.options,
  });
}

class ShipmentOption {
  final String label;
  final double volume;
  final double weight;

  ShipmentOption({required this.label, required this.volume, required this.weight});
}

class ShipmentCategory {
  final String name;
  final IconData icon;
  final List<ShipmentItem> items;

  ShipmentCategory({required this.name, required this.icon, required this.items});
}

class SelectedItem {
  final String name;
  final String? optionLabel;
  final double volume;
  final double weight;
  int quantity;

  SelectedItem({
    required this.name,
    this.optionLabel,
    required this.volume,
    required this.weight,
    this.quantity = 1,
  });

  String get id => optionLabel != null ? '$name-$optionLabel' : name;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (optionLabel != null) 'option': optionLabel,
      'quantity': quantity,
      'volume_per_unit': volume,
      'weight_per_unit': weight,
    };
  }
}

// --- DATASET COMPLET ET ÉLARGI ---
final shipmentData = [
  ShipmentCategory(
    name: "🪑 Mobilier",
    icon: Icons.chair_rounded,
    items: [
      ShipmentItem(name: "Canapé / Divan", icon: Icons.weekend_rounded, options: [ShipmentOption(label: "2 places", volume: 1.2, weight: 50), ShipmentOption(label: "3 places", volume: 1.8, weight: 70), ShipmentOption(label: "Angle", volume: 2.5, weight: 90)]),
      ShipmentItem(name: "Fauteuil / Relax", icon: Icons.chair_alt_rounded, volume: 0.8, weight: 30),
      ShipmentItem(name: "Table basse", icon: Icons.square_foot_rounded, volume: 0.3, weight: 15),
      ShipmentItem(name: "Table à manger", icon: Icons.table_restaurant_rounded, volume: 1.2, weight: 40),
      ShipmentItem(name: "Chaise", icon: Icons.chair_rounded, volume: 0.2, weight: 5),
      ShipmentItem(name: "Cadre de lit", icon: Icons.bed_rounded, options: [ShipmentOption(label: "90cm", volume: 0.4, weight: 20), ShipmentOption(label: "140cm", volume: 0.6, weight: 30), ShipmentOption(label: "Queen", volume: 0.7, weight: 35), ShipmentOption(label: "King", volume: 0.8, weight: 40)]),
      ShipmentItem(name: "Matelas", icon: Icons.king_bed_rounded, options: [ShipmentOption(label: "90cm", volume: 0.3, weight: 15), ShipmentOption(label: "140cm", volume: 0.5, weight: 25), ShipmentOption(label: "Queen", volume: 0.6, weight: 30), ShipmentOption(label: "King", volume: 0.7, weight: 35)]),
      ShipmentItem(name: "Armoire / Dressing", icon: Icons.door_front_door_rounded, volume: 1.5, weight: 80),
      ShipmentItem(name: "Meuble TV / Buffet", icon: Icons.tv_rounded, volume: 0.7, weight: 35),
    ],
  ),
  ShipmentCategory(
    name: "🧊 Électroménager",
    icon: Icons.kitchen_rounded,
    items: [
      ShipmentItem(name: "Réfrigérateur", icon: Icons.kitchen_rounded, options: [ShipmentOption(label: "Petit", volume: 0.5, weight: 30), ShipmentOption(label: "Standard", volume: 1.2, weight: 60), ShipmentOption(label: "Double", volume: 1.8, weight: 90)]),
      ShipmentItem(name: "Lave-linge", icon: Icons.local_laundry_service_rounded, volume: 0.5, weight: 70),
      ShipmentItem(name: "Sèche-linge", icon: Icons.dry_cleaning_rounded, volume: 0.5, weight: 50),
      ShipmentItem(name: "Lave-vaisselle", icon: Icons.wash, volume: 0.4, weight: 45),
      ShipmentItem(name: "Cuisinière / Four", icon: Icons.outdoor_grill_rounded, volume: 0.6, weight: 55),
      ShipmentItem(name: "Congélateur", icon: Icons.ac_unit_rounded, volume: 0.8, weight: 50),
    ],
  ),
  ShipmentCategory(
    name: "🛒 Magasin & Grande Surface",
    icon: Icons.storefront_rounded,
    items: [
      ShipmentItem(name: "Caddie de courses", icon: Icons.shopping_cart_checkout_rounded, volume: 0.2, weight: 40),
      ShipmentItem(name: "Pack de boissons", icon: Icons.local_drink_rounded, volume: 0.02, weight: 10),
      ShipmentItem(name: "Carton de produits secs", icon: Icons.fastfood_rounded, volume: 0.05, weight: 15),
      ShipmentItem(name: "Sacs de courses", icon: Icons.shopping_bag_rounded, volume: 0.08, weight: 25),
      ShipmentItem(name: "Sac de croquettes", icon: Icons.pets_rounded, volume: 0.06, weight: 20),
    ],
  ),
    ShipmentCategory(
    name: "🍉 Marché & Gros",
    icon: Icons.shopping_basket_rounded,
    items: [
      ShipmentItem(name: "Cagette de fruits/légumes", icon: Icons.grass, volume: 0.04, weight: 15),
      ShipmentItem(name: "Sac de pommes de terre/oignons", icon: Icons.view_headline, volume: 0.03, weight: 25),
      ShipmentItem(name: "Carton de marchandise", icon: Icons.inventory, volume: 0.1, weight: 20),
      ShipmentItem(name: "Bidon d'huile (25L)", icon: Icons.oil_barrel_rounded, volume: 0.03, weight: 25),
      ShipmentItem(name: "Palette de marchandise", icon: Icons.grid_on_rounded, volume: 1.2, weight: 800),
    ],
  ),
  ShipmentCategory(
    name: "🧱 Matériaux de Construction",
    icon: Icons.foundation_rounded,
    items: [
      ShipmentItem(name: "Ciment", icon: Icons.inventory_2_outlined, options: [ShipmentOption(label: "Sac 50kg", volume: 0.025, weight: 50)]),
      ShipmentItem(name: "Brique (palette)", icon: Icons.grid_on_rounded, volume: 1.0, weight: 1200),
      ShipmentItem(name: "Sable / Gravier", icon: Icons.grain_rounded, options: [ShipmentOption(label: "Big Bag (1m³)", volume: 1.0, weight: 1500)]),
      ShipmentItem(name: "Parpaing (Bloc béton)", icon: Icons.crop_square_rounded, volume: 0.01, weight: 20),
      ShipmentItem(name: "Barre de fer à béton", icon: Icons.linear_scale_rounded, volume: 0.01, weight: 10),
      ShipmentItem(name: "Carton de Carrelage", icon: Icons.view_module_rounded, volume: 0.02, weight: 25),
      ShipmentItem(name: "Porte / Fenêtre", icon: Icons.sensor_door_rounded, volume: 0.5, weight: 25),
    ],
  ),
  ShipmentCategory(
    name: "📦 Colis & Déménagement",
    icon: Icons.inventory_2_rounded,
    items: [
      ShipmentItem(name: "Carton de déménagement", icon: Icons.inventory, options: [ShipmentOption(label: "Petit", volume: 0.03, weight: 5), ShipmentOption(label: "Moyen", volume: 0.06, weight: 10), ShipmentOption(label: "Grand", volume: 0.12, weight: 20)]),
      ShipmentItem(name: "Valise", icon: Icons.luggage_rounded, volume: 0.1, weight: 25),
      ShipmentItem(name: "Boîte à outils", icon: Icons.build_rounded, volume: 0.05, weight: 18),
      ShipmentItem(name: "Poussette", icon: Icons.child_friendly_rounded, volume: 0.3, weight: 12),
    ],
  ),
   ShipmentCategory(
    name: "🌿 Jardin & Extérieur",
    icon: Icons.local_florist_rounded,
    items: [
      ShipmentItem(name: "Mobilier d'extérieur", icon: Icons.deck_rounded, volume: 1.5, weight: 50),
      ShipmentItem(name: "Barbecue", icon: Icons.outdoor_grill_rounded, volume: 0.4, weight: 25),
      ShipmentItem(name: "Tondeuse", icon: Icons.grass_rounded, volume: 0.5, weight: 30),
      ShipmentItem(name: "Brouette", icon: Icons.agriculture_outlined, volume: 0.3, weight: 15),
    ],
  ),
  ShipmentCategory(
    name: "🛠️ Matériel Pro",
    icon: Icons.construction_rounded,
    items: [
      ShipmentItem(name: "Étagère / Rayonnage", icon: Icons.shelves, volume: 0.8, weight: 40),
      ShipmentItem(name: "Échafaudage (petit)", icon: Icons.construction, volume: 1.5, weight: 100),
    ],
  ),
  ShipmentCategory(
    name: "🚲 Sport & Loisirs",
    icon: Icons.sports_basketball_rounded,
    items: [
      ShipmentItem(name: "Vélo", icon: Icons.pedal_bike_rounded, volume: 0.4, weight: 15),
      ShipmentItem(name: "Tapis de course", icon: Icons.fitness_center_rounded, volume: 1.0, weight: 80),
      ShipmentItem(name: "Kayak / Canoë", icon: Icons.kayaking_rounded, volume: 1.5, weight: 30),
    ],
  ),
  ShipmentCategory(
    name: "🛻 Véhicules & Pièces",
    icon: Icons.two_wheeler_rounded,
    items: [
      ShipmentItem(name: "Moto / Scooter", icon: Icons.two_wheeler_rounded, volume: 1.2, weight: 150),
      ShipmentItem(name: "Moteur", icon: Icons.settings, volume: 0.5, weight: 150),
      ShipmentItem(name: "Pneu de camion", icon: Icons.adjust, volume: 0.2, weight: 50),
      ShipmentItem(name: "Quad", icon: Icons.agriculture_rounded, volume: 2.0, weight: 250),
    ],
  ),
];
class SchnellApp extends StatelessWidget {
  final LatLng pickupLocation;
  final List<DropOffData> dropOffDestination;
  final String pickup_name;

  const SchnellApp({
    super.key,
    required this.pickupLocation,
    required this.dropOffDestination,

    required this.pickup_name
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shnell',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.amber,
        scaffoldBackgroundColor: const Color(0xFF1C1C1E),
        colorScheme: const ColorScheme.dark(
          primary: Colors.amber,
          secondary: Colors.amberAccent,
          surface: Color(0xFF2C2C2E),
          onPrimary: Colors.black,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amber,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 16),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      home: ShipmentSelectionScreen(
        pickupLocation: pickupLocation,
        dropOffDestination: dropOffDestination,
        pickup_name: pickup_name,
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ShipmentSelectionScreen extends StatefulWidget {
  final LatLng pickupLocation;
  final List<DropOffData> dropOffDestination;
  final String pickup_name;

  const ShipmentSelectionScreen({
    super.key,
    required this.pickupLocation,
    required this.dropOffDestination,
    required this.pickup_name
  });

  @override
  State<ShipmentSelectionScreen> createState() => _ShipmentSelectionScreenState();
}

class _ShipmentSelectionScreenState extends State<ShipmentSelectionScreen> {
  final Map<String, SelectedItem> _selectedItems = {};
  final List<SelectedItem> _customItems = [];

  double _totalVolume = 0.0;
  double _totalWeight = 0.0;
  bool _isLoading = false;

  void _updateTotals() {
    double vol = 0.0;
    double wgt = 0.0;
    _selectedItems.forEach((key, item) {
      vol += item.volume * item.quantity;
      wgt += item.weight * item.quantity;
    });
    if (mounted) {
      setState(() {
        _totalVolume = vol;
        _totalWeight = wgt;
      });
    }
  }

  void _updateItemQuantity(String id, SelectedItem item, int change) {
    setState(() {
      if (_selectedItems.containsKey(id)) {
        _selectedItems[id]!.quantity += change;
        if (_selectedItems[id]!.quantity <= 0) {
          _selectedItems.remove(id);
        }
      } else if (change > 0) {
        _selectedItems[id] = item;
      }
      _updateTotals();
    });
  }

  void _addCustomItem(SelectedItem item) {
    setState(() {
      _customItems.add(item);
      _selectedItems[item.id] = item;
      _updateTotals();
    });
  }
  
  // ✨ NOUVELLE FONCTION: Détermine le type de véhicule et navigue.
  void _proceedToVehicleSelection() {
    if (_selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Veuillez sélectionner au moins un article.")),
      );
      return;
    }

    // Détermine le type de véhicule requis
    final vehicleTypeCode = _getRequiredVehicleTypeCode(_totalVolume, _totalWeight);
    final vehicleImage = _getVehicleImage(vehicleTypeCode);

    // Navigue vers l'écran de détails du véhicule avec les infos nécessaires
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VehicleDetailScreen(
          type: vehicleTypeCode,
          image: vehicleImage,
          pickupLocation: widget.pickupLocation,
          dropOffDestination: widget.dropOffDestination,pickup_name: widget.pickup_name,
          // NOTE: Vous devrez probablement passer plus de données ici, comme
          // le volume, le poids et la liste des articles pour la création de la commande finale.
        ),
      ),
    );
  }

  /// ✨ NOUVELLE FONCTION: Logique pour choisir automatiquement le véhicule.
  String _getRequiredVehicleTypeCode(double volume, double weight) {
    // Cette logique peut être affinée selon vos besoins métier.
    // Elle retourne le code du plus petit véhicule capable de faire le transport.
    if (volume <= 1 && weight <= 100) return 'super_light';

    if (volume <= 3 && weight <= 800) return 'light';
    if (volume <= 5 && weight <= 1500) return 'medium';
    if (volume <= 12 && weight <= 3500) return 'medium_heavy';
    return 'heavy'; // Par défaut pour les très gros volumes/poids
  }
  
  /// ✨ NOUVELLE FONCTION: Retourne l'image correspondant au type de véhicule.
  String _getVehicleImage(String typeCode) {
    switch (typeCode) {
      case 'super_light': return 'assets/super_light.png';
      case 'light': return 'assets/light.png';
      case 'medium': return 'assets/isuzu.png';
      case 'medium_heavy': return 'assets/medium.png';
      case 'heavy': return 'assets/heavy.png';
      default: return 'assets/heavy.png';
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: const Text("Listez vos Articles", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          _SummaryBar(
            totalVolume: _totalVolume,
            totalWeight: _totalWeight,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // ✨ SUPPRIMÉ: Le widget _DeliveryOptions a été retiré.
                ...shipmentData.map((category) => _CategoryExpansionTile(
                      category: category,
                      selectedItems: _selectedItems,
                      onUpdate: _updateItemQuantity,
                    )),
                if (_customItems.isNotEmpty)
                  _CustomItemsExpansionTile(
                    items: _customItems,
                    selectedItems: _selectedItems,
                    onUpdate: _updateItemQuantity,
                  ),
                const SizedBox(height: 20),
                TextButton.icon(
                  icon: const Icon(Icons.auto_awesome, color: Colors.amber, size: 20),
                  label: const Text('Ajouter un article personnalisé', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                  onPressed: () => _showCustomItemDialog(),
                  style: TextButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      padding: const EdgeInsets.all(16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                ),
                const SizedBox(height: 100), // Espace pour le bouton flottant
              ],
            ),
          ),
        ],
      ),
      // ✨ MODIFIÉ: Le bouton flottant appelle maintenant la nouvelle fonction.
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _selectedItems.isNotEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _proceedToVehicleSelection,
                icon: const Icon(Icons.directions_car_filled),
                label: const Text('Continuer'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
            )
          : null,
    );
  }

  Future<void> _showCustomItemDialog() async {
    await showDialog(
      context: context,
      builder: (context) => _CustomItemDialog(onAddItem: _addCustomItem),
    );
  }
}

//############################################################################
// SUB-WIDGETS & DIALOGS (La plupart restent inchangés)
//############################################################################

class _SummaryBar extends StatelessWidget {
  final double totalVolume;
  final double totalWeight;
  
  // onOptimize a été retiré car n'est plus pertinent pour cette vue.
  const _SummaryBar({required this.totalVolume, required this.totalWeight});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStat('VOLUME TOTAL', '${totalVolume.toStringAsFixed(2)} m³'),
          _buildStat('POIDS TOTAL', '${totalWeight.toStringAsFixed(0)} kg'),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.amber, fontSize: 24, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

// ... Le reste de vos sub-widgets (_CategoryExpansionTile, _ItemRow, etc.)
// peut rester exactement le même car leur logique interne n'a pas changé.
class _CategoryExpansionTile extends StatelessWidget {
  final ShipmentCategory category;
  final Map<String, SelectedItem> selectedItems;
  final Function(String, SelectedItem, int) onUpdate;

  const _CategoryExpansionTile({required this.category, required this.selectedItems, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surface,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(category.icon, color: Colors.amber),
        title: Text(category.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        children: category.items.map((item) => _ItemRow(item: item, selectedItems: selectedItems, onUpdate: onUpdate)).toList(),
      ),
    );
  }
}

class _CustomItemsExpansionTile extends StatelessWidget {
  final List<SelectedItem> items;
  final Map<String, SelectedItem> selectedItems;
  final Function(String, SelectedItem, int) onUpdate;

  const _CustomItemsExpansionTile({required this.items, required this.selectedItems, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    return Card(
        color: Theme.of(context).colorScheme.surface,
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          initiallyExpanded: true,
          leading: const Icon(Icons.edit_note_rounded, color: Colors.amber),
          title: const Text("Articles Personnalisés", style: TextStyle(fontWeight: FontWeight.bold)),
          children: items.map((item) {
            final shipmentItem = ShipmentItem(name: item.name, icon: Icons.label_important_outline_rounded, volume: item.volume, weight: item.weight);
            return _ItemRow(item: shipmentItem, selectedItems: selectedItems, onUpdate: onUpdate, isCustom: true);
          }).toList(),
        ));
  }
}

class _ItemRow extends StatefulWidget {
  final ShipmentItem item;
  final Map<String, SelectedItem> selectedItems;
  final Function(String, SelectedItem, int) onUpdate;
  final bool isCustom;

  const _ItemRow({required this.item, required this.selectedItems, required this.onUpdate, this.isCustom = false});

  @override
  State<_ItemRow> createState() => _ItemRowState();
}

class _ItemRowState extends State<_ItemRow> {
  late String _selectedOption;

  @override
  void initState() {
    super.initState();
    _selectedOption = widget.item.options?.first.label ?? '';
  }

  String get _itemId => widget.item.options != null ? '${widget.item.name}-$_selectedOption' : widget.item.name;

  @override
  Widget build(BuildContext context) {
    final currentItem = widget.selectedItems[_itemId];
    final quantity = currentItem?.quantity ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(widget.item.icon, color: Colors.amber.withOpacity(0.8)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.item.name),
                if (widget.item.options != null) _buildDropdown(),
                if (widget.isCustom) Text("Vol: ${widget.item.volume?.toStringAsFixed(2)}m³, Poids: ${widget.item.weight?.toStringAsFixed(0)}kg (Estimé)", style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          _buildQuantityControl(quantity),
        ],
      ),
    );
  }

  Widget _buildDropdown() {
    return DropdownButton<String>(
      value: _selectedOption,
      isDense: true,
      underline: const SizedBox(),
      items: widget.item.options!.map((opt) => DropdownMenuItem(value: opt.label, child: Text(opt.label))).toList(),
      onChanged: (value) => setState(() => _selectedOption = value!),
    );
  }

  Widget _buildQuantityControl(int quantity) {
    return Row(
      children: [
        IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => widget.onUpdate(_itemId, _getSelectedItemData(), -1)),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
          child: Text('$quantity', key: ValueKey<int>(quantity), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        IconButton(icon: const Icon(Icons.add_circle, color: Colors.amber), onPressed: () => widget.onUpdate(_itemId, _getSelectedItemData(), 1)),
      ],
    );
  }

  SelectedItem _getSelectedItemData() {
    if (widget.item.options != null) {
      final option = widget.item.options!.firstWhere((o) => o.label == _selectedOption);
      return SelectedItem(name: widget.item.name, optionLabel: option.label, volume: option.volume, weight: option.weight);
    }
    return SelectedItem(name: widget.item.name, volume: widget.item.volume!, weight: widget.item.weight!);
  }
}

class _CustomItemDialog extends StatefulWidget {
  final Function(SelectedItem) onAddItem;
  const _CustomItemDialog({required this.onAddItem});

  @override
  State<_CustomItemDialog> createState() => _CustomItemDialogState();
}

class _CustomItemDialogState extends State<_CustomItemDialog> {
  // This dialog can be used for adding custom items, potentially with Gemini API estimation.
  final _controller = TextEditingController();
  final _volumeController = TextEditingController();
  final _weightController = TextEditingController();
  
  void _addItem() {
    final name = _controller.text;
    final volume = double.tryParse(_volumeController.text) ?? 0.1;
    final weight = double.tryParse(_weightController.text) ?? 5.0;

    if (name.isNotEmpty) {
      widget.onAddItem(SelectedItem(name: name, volume: volume, weight: weight));
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('✨ Ajouter un Article Personnalisé'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: _controller, decoration: const InputDecoration(labelText: 'Nom de l\'article', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: _volumeController, decoration: const InputDecoration(labelText: 'Volume (m³)', border: OutlineInputBorder()), keyboardType: TextInputType.number),
          const SizedBox(height: 8),
          TextField(controller: _weightController, decoration: const InputDecoration(labelText: 'Poids (kg)', border: OutlineInputBorder()), keyboardType: TextInputType.number),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(onPressed: _addItem, child: const Text('Ajouter')),
      ],
    );
  }
}*/