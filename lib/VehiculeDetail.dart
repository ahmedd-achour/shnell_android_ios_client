import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as lt;
import 'package:shnell/dots.dart'; 
import 'package:shnell/mainUsers.dart';
import 'package:shnell/model/destinationdata.dart';
import 'package:shnell/model/oredrs.dart';
import 'package:shnell/orderService.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

// --- SERVICE TYPE MODEL (From your instruction) ---
class ServiceType {
  final String id;
  final String title;
  final String subtitle;
  final String iconAsset;
  final double priceMultiplier; 
  final List<String> allowedVehicles;

  ServiceType({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.iconAsset,
    required this.allowedVehicles,
    required this.priceMultiplier
  });

  factory ServiceType.fromMap(Map<String, dynamic> map) {
    return ServiceType(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      priceMultiplier: (map['price_multiplier'] ?? 1.0).toDouble(), // Critical: Parse Multiplier
      subtitle: map['subtitle'] ?? '',
      iconAsset: map['icon_asset'] ?? 'assets/box.png',
      allowedVehicles: List<String>.from(map['allowed_vehicles'] ?? []),
    );
  }
}

// --- VEHICLE SETTINGS MODEL ---
class VehicleSettings {
  final String name;
  final double maxWeight;
  final double volume;
  final double basePrice;
  final double shortDistThreshold;
  final double shortDistMin;
  final double shortDistMult;
  final double longDistRate;

  VehicleSettings({
    required this.name,
    required this.maxWeight,
    required this.volume,
    required this.basePrice,
    required this.shortDistThreshold,
    required this.shortDistMin,
    required this.shortDistMult,
    required this.longDistRate,
  });

  factory VehicleSettings.fromMap(Map<String, dynamic> map) {
    return VehicleSettings(
      name: map['name'] ?? 'Unknown',
      maxWeight: (map['max_weight'] ?? 0).toDouble(),
      volume: (map['volume'] ?? 0).toDouble(),
      basePrice: (map['base_price'] ?? 0).toDouble(),
      shortDistThreshold: (map['short_dist_threshold'] ?? 300).toDouble(),
      shortDistMin: (map['short_dist_min'] ?? 0).toDouble(),
      shortDistMult: (map['short_dist_mult'] ?? 0).toDouble(),
      longDistRate: (map['long_dist_rate'] ?? 0).toDouble(),
    );
  }
}

class VehicleDetailScreen extends StatefulWidget {
  final String type; // Vehicle ID (e.g. 'light')
  final String image;
  final lt.LatLng pickupLocation;
  final List<DropOffData> dropOffDestination;
  final String pickup_name;
  final String? serviceTypeId; // Passed from Service Selection

  const VehicleDetailScreen({
    Key? key,
    required this.type,
    required this.image,
    required this.pickupLocation,
    required this.dropOffDestination,
    required this.pickup_name,
    this.serviceTypeId,
  }) : super(key: key);

  @override
  State<VehicleDetailScreen> createState() => _VehicleDetailScreenState();
}

class _VehicleDetailScreenState extends State<VehicleDetailScreen> {
  // State
  bool _isLoading = true;
  double _calculatedDistanceKm = 0.0;
  double _calculatedEstimatedPrice = 0.0;
  
  // Cloud Data
  VehicleSettings? _vehicleSettings;
  double _stopFee = 0.4;
  double _serviceMultiplier = 1.0; // Defaults to 1.0 if not set

  // Manual Offer Logic
  late TextEditingController _offerController;
  String? _offerErrorText;
  Color _priceStatusColor = Colors.grey; 

  static const String _googleMapsApiKey = "AIzaSyCPNt6re39yO5lhlD-H1eXWmRs4BAp_y6w";

  @override
  void initState() {
    super.initState();
    _offerController = TextEditingController();
    _initializeAppLogic();
  }

  @override
  void dispose() {
    _offerController.dispose();
    super.dispose();
  }

  // --- LOGIC SECTION ---

  Future<void> _initializeAppLogic() async {
    await _calculateRouteDistance();
    await _fetchCloudSettingsAndCalculate();
  }

  Future<void> _calculateRouteDistance() async {
    if (widget.dropOffDestination.isEmpty) return;

    final List<lt.LatLng> destinations = widget.dropOffDestination.map((dropOff) => dropOff.destination).toList();
    final distance = await getGoogleRoadDistance(widget.pickupLocation, destinations, _googleMapsApiKey);

    if (mounted && distance != null) {
      setState(() => _calculatedDistanceKm = distance);
    }
  }

  Future<void> _fetchCloudSettingsAndCalculate() async {
    try {
      // 1. Fetch all settings in parallel
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('settings').doc('config').get(),        // Index 0
        FirebaseFirestore.instance.collection('settings').doc('vehicles').get(),      // Index 1
        FirebaseFirestore.instance.collection('settings').doc('service_types').get(), // Index 2
      ]);

      final configDoc = results[0];
      final vehiclesDoc = results[1];
      final servicesDoc = results[2];

      if (mounted) {
        // A. Parse Global Config
        if (configDoc.exists && configDoc.data() != null) {
          _stopFee = (configDoc['stop_fee'] ?? 0.4).toDouble();
        }

        // B. Parse Service Type to get Multiplier
        if (widget.serviceTypeId != null && servicesDoc.exists && servicesDoc.data() != null) {
          final data = servicesDoc.data() as Map<String, dynamic>;
          if (data['types'] is List) {
            final List<dynamic> rawTypes = data['types'];
            // Find the specific service the user selected
            final selectedServiceData = rawTypes.firstWhere(
              (item) => item['id'] == widget.serviceTypeId,
              orElse: () => null,
            );

            if (selectedServiceData != null) {
              // Create Object using the class you provided
              final serviceObj = ServiceType.fromMap(selectedServiceData as Map<String, dynamic>);
              _serviceMultiplier = serviceObj.priceMultiplier; // Apply the multiplier (e.g. 1.5)
            }
          }
        }

        // C. Parse Vehicle Data & Calculate Final Price
        if (vehiclesDoc.exists && vehiclesDoc.data() != null) {
          final data = vehiclesDoc.data() as Map<String, dynamic>;
          if (data.containsKey(widget.type)) {
            _vehicleSettings = VehicleSettings.fromMap(data[widget.type]);
            
            // Calculate
            _calculatedEstimatedPrice = _calculateDynamicPrice(
              _calculatedDistanceKm, 
              _vehicleSettings!,
              widget.dropOffDestination.length
            );
            
            // Set UI values
            _offerController.text = _calculatedEstimatedPrice.toStringAsFixed(0);
            _validateOffer(_offerController.text);
          }
        }
        
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint("Error fetching cloud settings: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // CORE PRICING LOGIC
  double _calculateDynamicPrice(double distance, VehicleSettings v, int stops) {
    double pricePerKm;
    
    // 1. Base Distance Rate
    if (distance < v.shortDistThreshold) {
      double factor = (1 - (distance / 1000)) * v.shortDistMult;
      pricePerKm = max(v.shortDistMin, factor);
    } else {
      pricePerKm = v.longDistRate;
    }

    // 2. Base Calculation
    double baseCalculation = v.basePrice + (distance * pricePerKm) + (stops * _stopFee);
    
    // 3. APPLY SERVICE MULTIPLIER (The Job Type Factor)
    // Moving Service (1.5x) costs more than Simple Transport (1.0x) for the same truck/distance
    return baseCalculation * _serviceMultiplier;
  }

  Future<double?> getGoogleRoadDistance(lt.LatLng origin, List<lt.LatLng> destinations, String apiKey) async {
    // ... (Keep existing Google Distance implementation)
    String originStr = '${origin.latitude},${origin.longitude}';
    String destinationStr = '${destinations.last.latitude},${destinations.last.longitude}';
    String waypointsStr = '';
    if (destinations.length > 1) {
      waypointsStr = destinations
          .sublist(0, destinations.length - 1)
          .map((d) => '${d.latitude},${d.longitude}')
          .join('|');
    }

    final String url =
        'https://maps.googleapis.com/maps/api/directions/json?origin=$originStr&destination=$destinationStr&mode=driving&waypoints=$waypointsStr&key=$apiKey';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['routes'] != null && data['routes'].isNotEmpty) {
          double totalDistance = 0.0;
          for (var leg in data['routes'][0]['legs']) {
            totalDistance += leg['distance']['value'];
          }
          return totalDistance / 1000; 
        }
      }
    } catch (e) {
      debugPrint("Network Error: $e");
    }
    return null;
  }

  // --- VALIDATION LOGIC ---

  // Min/Max also scales with multiplier automatically since they use _calculatedEstimatedPrice
  double get _minAllowedPrice => _calculatedEstimatedPrice * 0.75;
  double get _maxAllowedPrice => _calculatedEstimatedPrice * 1.50;

  void _validateOffer(String value) {
    double? val = double.tryParse(value);

    if (val == null || val <= 0) {
      setState(() {
        _offerErrorText = "Enter amount";
        _priceStatusColor = Colors.grey;
      });
      return;
    }

    if (val < _minAllowedPrice) {
      setState(() {
        _offerErrorText = "Too low";
        _priceStatusColor = Colors.orange; 
      });
    } else if (val > _maxAllowedPrice) {
      setState(() {
        _offerErrorText = "Too high";
        _priceStatusColor = Colors.red; 
      });
    } else {
      setState(() {
        _offerErrorText = null; 
        _priceStatusColor = Colors.green; 
      });
    }
  }

  Future<void> _passAnOrder() async {
    double currentOffer = double.tryParse(_offerController.text) ?? 0;
    
    // Strict Validation
    if (currentOffer < _minAllowedPrice || currentOffer > _maxAllowedPrice) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Price must be between ${_minAllowedPrice.toStringAsFixed(0)} and ${_maxAllowedPrice.toStringAsFixed(0)} DT"),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("User not logged in");

      final List<String> stopIds = [];
      for (final dropOff in widget.dropOffDestination) {
        final stopData = dropOff.toFirestore();
        final stopRef = await FirebaseFirestore.instance.collection('stops').add(stopData);
        stopIds.add(stopRef.id);
      }

      final newOrder = Orders(
        price: currentOffer,
        distance: _calculatedDistanceKm,
        namePickUp: widget.pickup_name,
        pickUpLocation: widget.pickupLocation,
        stops: stopIds,
        vehicleType: widget.type,
        id: '',
        userId: user.uid,
        additionalInfo: {
          'serviceType': widget.serviceTypeId ?? 'transport', 
          'appliedMultiplier': _serviceMultiplier, // Save the multiplier used for audit
        },
        isAcepted: false,
      );

      final orderService = OrderService();
      await orderService.addOrder(newOrder);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Booking confirmed!")),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const MainUsersScreen()),
          (Route<dynamic> route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: ${e.toString()}"), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  // --- UI BUILDING ---

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: RotatingDotsIndicator()));

    final vehicleName = _vehicleSettings?.name ?? "Transport";
    final vehicleMaxWeight = _vehicleSettings?.maxWeight ?? 0;
    final vehicleVolume = _vehicleSettings?.volume ?? 0;

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Scaffold(
      body: Stack(
        children: [
          // 1. TOP GRADIENT BACKGROUND
          Container(
            height: 320,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colorScheme.primary,
                  colorScheme.primaryContainer,
                ],
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(40),
                bottomRight: Radius.circular(40),
              ),
            ),
          ),

          // 2. SCROLLABLE CONTENT
          SingleChildScrollView(
            padding: const EdgeInsets.only(top: 100, bottom: 100),
            child: Column(
              children: [
                // A. FLOATING VEHICLE CARD
                _buildFloatingVehicleCard(colorScheme, textTheme),

                const SizedBox(height: 25),

                // B. PRICE CARD (MANUAL ENTRY)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildPriceNegotiationCard(l10n, colorScheme, textTheme),
                ),

                const SizedBox(height: 20),

                // C. TRIP DETAILS
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildDetailsCard(vehicleName, vehicleMaxWeight, vehicleVolume, colorScheme, textTheme),
                ),
              ],
            ),
          ),

          // 3. HEADER
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: colorScheme.surface,
                    foregroundColor: colorScheme.onSurface,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'Back',
                    ),
                  ),
                  Expanded(
                    child: Text(
                      vehicleName,
                      textAlign: TextAlign.center,
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
            ),
          ),
        ],
      ),

      // 4. BIG CONFIRM BUTTON
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _passAnOrder,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              backgroundColor: _offerErrorText == null ? colorScheme.primary : Colors.grey, // Grise le bouton si erreur
            ),
            child: Text(
              l10n?.confirmBooking.toUpperCase() ?? "CONFIRM NOW",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1.2),
            ),
          ),
        ),
      ),
    );
  }

  // --- SUB-WIDGETS ---

  Widget _buildFloatingVehicleCard(ColorScheme colorScheme, TextTheme textTheme) {
    return Container(
      height: 240,
      margin: const EdgeInsets.symmetric(horizontal: 30),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: -30,
            right: -30,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                color: colorScheme.onPrimary.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Image.asset(
              widget.image,
              fit: BoxFit.contain,
            ),
          ),
          Positioned(
            bottom: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: colorScheme.shadow.withOpacity(0.1), blurRadius: 8),
                ]
              ),
              child: Row(
                children: [
                   Icon(Icons.route, size: 18, color: colorScheme.outline),
                  const SizedBox(width: 6),
                  Text(
                    "${_calculatedDistanceKm.toStringAsFixed(1)} km",
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceNegotiationCard(AppLocalizations? l10n, ColorScheme colorScheme, TextTheme textTheme) {
    return Card(
      elevation: 4,
      shadowColor: colorScheme.shadow.withOpacity(0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      child: Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          children: [
            // 1. Label
            Text(
              "SET YOUR PRICE",
              style: textTheme.labelLarge?.copyWith(
                color: colorScheme.outline,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5
              ),
            ),

            const SizedBox(height: 20),

            // 2. The Big Manual Input Field
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _priceStatusColor, 
                  width: 2,
                ),
              ),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                   IntrinsicWidth(
                    child: TextField(
                      controller: _offerController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: textTheme.displayMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: colorScheme.onSurface,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: "0",
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                        LengthLimitingTextInputFormatter(6),
                      ],
                      onChanged: _validateOffer,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "DT",
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 15),

            // 3. Min / Max Visual Guide
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildPriceLimitBadge("Min", _minAllowedPrice, colorScheme, textTheme),
                
                if (_offerErrorText != null)
                   Text(
                    _offerErrorText!,
                    style: TextStyle(
                      color: _priceStatusColor, 
                      fontWeight: FontWeight.bold,
                      fontSize: 12
                    ),
                  )
                else
                   const Text("Fair Price", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),

                _buildPriceLimitBadge("Max", _maxAllowedPrice, colorScheme, textTheme),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceLimitBadge(String label, double price, ColorScheme colorScheme, TextTheme textTheme) {
    return Column(
      crossAxisAlignment: label == "Min" ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        Text(
          label.toUpperCase(),
          style: textTheme.labelSmall?.copyWith(color: colorScheme.outline),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            "${price.toStringAsFixed(0)} DT",
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailsCard(String name, double weight, double vol, ColorScheme colorScheme, TextTheme textTheme) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow(Icons.my_location, widget.pickup_name, colorScheme, textTheme, isStart: true),
            ...widget.dropOffDestination.map((d) => _buildDetailRow(Icons.location_on, d.destinationName, colorScheme, textTheme)).toList(),

            const SizedBox(height: 25),

            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildTechSpec(Icons.scale, "${weight.toStringAsFixed(0)} kg", "Max Load", colorScheme, textTheme),
                  Container(height: 30, width: 1, color: colorScheme.outlineVariant),
                  _buildTechSpec(Icons.view_in_ar, "${vol.toStringAsFixed(1)} m³", "Volume", colorScheme, textTheme),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String text, ColorScheme colorScheme, TextTheme textTheme, {bool isStart = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Icon(icon, color: colorScheme.primary, size: 24),
            if (isStart)
              Container(height: 24, width: 2, color: colorScheme.outlineVariant, margin: const EdgeInsets.symmetric(vertical: 2)),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.3,
                color: colorScheme.onSurface
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTechSpec(IconData icon, String value, String label, ColorScheme colorScheme, TextTheme textTheme) {
    return Column(
      children: [
        Icon(icon, color: colorScheme.secondary, size: 22),
        const SizedBox(height: 4),
        Text(
          value, 
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.onSurface)
        ),
        Text(
          label, 
          style: textTheme.bodySmall?.copyWith(color: colorScheme.outline)
        ),
      ],
    );
  }
}