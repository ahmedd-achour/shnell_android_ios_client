import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as lt;
import 'package:shnell/dots.dart';
// Adjust these imports based on your actual project structure
import 'package:shnell/mainUsers.dart';
import 'package:shnell/model/destinationdata.dart';
import 'package:shnell/model/oredrs.dart';
import 'package:shnell/orderService.dart';
// --- Localization Import ---
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

// --- SERVICE TYPE MODEL (Unchanged) ---
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
    required this.priceMultiplier,
  });

  factory ServiceType.fromMap(Map<String, dynamic> map) {
    return ServiceType(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      priceMultiplier: (map['price_multiplier'] ?? 1.0).toDouble(),
      subtitle: map['subtitle'] ?? '',
      iconAsset: map['icon_asset'] ?? 'assets/box.png',
      allowedVehicles: List<String>.from(map['allowed_vehicles'] ?? []),
    );
  }
}

// --- VEHICLE SETTINGS MODEL (Unchanged) ---
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
  final String? serviceTypeId;

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
  bool _isLoading = true;
  double _calculatedDistanceKm = 0.0;
  double _calculatedEstimatedPrice = 0.0;

  VehicleSettings? _vehicleSettings;
  double _stopFee = 0.4;
  double _serviceMultiplier = 1.0;

  late TextEditingController _offerController;
  // We store the error *code* or simple state, 
  // but to keep it simple with existing logic, we will check validity on the fly 
  // or update a boolean state. Here we stick to a helper method that returns strings via context.

  DateTime? _selectedScheduleDate;
  bool _hasChosenSchedule = false;

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

  Future<void> _initializeAppLogic() async {
    await _calculateRouteDistance();
    await _fetchCloudSettingsAndCalculate();
  }

  Future<void> _calculateRouteDistance() async {
    if (widget.dropOffDestination.isEmpty) return;
    final List<lt.LatLng> destinations =
        widget.dropOffDestination.map((dropOff) => dropOff.destination).toList();
    final distance =
        await getGoogleRoadDistance(widget.pickupLocation, destinations, _googleMapsApiKey);
    if (mounted && distance != null) {
      setState(() => _calculatedDistanceKm = distance);
    }
  }

  Future<void> _fetchCloudSettingsAndCalculate() async {
    try {
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('settings').doc('config').get(),
        FirebaseFirestore.instance.collection('settings').doc('vehicles').get(),
        FirebaseFirestore.instance.collection('settings').doc('service_types').get(),
      ]);

      final configDoc = results[0];
      final vehiclesDoc = results[1];
      final servicesDoc = results[2];

      if (mounted) {
        if (configDoc.exists && configDoc.data() != null) {
          _stopFee = (configDoc['stop_fee'] ?? 0.4).toDouble();
        }

        if (widget.serviceTypeId != null && servicesDoc.exists && servicesDoc.data() != null) {
          final data = servicesDoc.data() as Map<String, dynamic>;
          if (data['types'] is List) {
            final rawTypes = data['types'] as List<dynamic>;
            final selectedServiceData = rawTypes.firstWhere(
              (item) => item['id'] == widget.serviceTypeId,
              orElse: () => null,
            );
            if (selectedServiceData != null) {
              final serviceObj =
                  ServiceType.fromMap(selectedServiceData as Map<String, dynamic>);
              _serviceMultiplier = serviceObj.priceMultiplier;
            }
          }
        }

        if (vehiclesDoc.exists && vehiclesDoc.data() != null) {
          final data = vehiclesDoc.data() as Map<String, dynamic>;
          if (data.containsKey(widget.type)) {
            _vehicleSettings = VehicleSettings.fromMap(data[widget.type]);
            _calculatedEstimatedPrice = _calculateDynamicPrice(
              _calculatedDistanceKm,
              _vehicleSettings!,
              widget.dropOffDestination.length,
            );
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

  double _calculateDynamicPrice(double distance, VehicleSettings v, int stops) {
    double pricePerKm;
    if (distance < v.shortDistThreshold) {
      double factor = (1 - (distance / 1000)) * v.shortDistMult;
      pricePerKm = max(v.shortDistMin, factor);
    } else {
      pricePerKm = v.longDistRate;
    }
    double baseCalculation = v.basePrice + (distance * pricePerKm) + (stops * _stopFee);
    return baseCalculation * _serviceMultiplier;
  }

  Future<double?> getGoogleRoadDistance(
      lt.LatLng origin, List<lt.LatLng> destinations, String apiKey) async {
    String originStr = '${origin.latitude},${origin.longitude}';
    String destinationStr =
        '${destinations.last.latitude},${destinations.last.longitude}';
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

  double get _minAllowedPrice => _calculatedEstimatedPrice * 0.9;
  double get _maxAllowedPrice => _calculatedEstimatedPrice * 1.2;

  void _validateOffer(String value) {
    // We update the state to trigger rebuild, 
    // the actual error string is generated in build method using Context for localization
    setState(() {
      // Just triggering update, logic moved to build or helper that has context
    });
  }
  
  // Helper to get error string based on current value
  String? _getLocalizedError(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    double? val = double.tryParse(_offerController.text);
    if (val == null || val <= 0) {
      return loc.enterAmountError;
    }
    if (val < _minAllowedPrice) {
      return loc.tooLow;
    } else if (val > _maxAllowedPrice) {
      return loc.tooHigh;
    }
    return null; // Valid
  }

  Future<void> _selectScheduleDate(BuildContext context) async {
    final DateTime now = DateTime.now();
    final DateTime initialDate = _selectedScheduleDate ?? now.add(const Duration(minutes: 30));

    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
    );

    if (pickedDate != null) {
      final TimeOfDay initialTime = TimeOfDay.fromDateTime(initialDate);
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: initialTime,
      );

      if (pickedTime != null) {
        setState(() {
          _selectedScheduleDate = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            pickedTime.hour,
            pickedTime.minute,
          );
          _hasChosenSchedule = true;
        });
      }
    }
  }

  Future<void> _passAnOrder() async {
    final loc = AppLocalizations.of(context)!;
    double currentOffer = double.tryParse(_offerController.text) ?? 0;
    String? error = _getLocalizedError(context);

    if (error != null || currentOffer <= 0) {
       ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.validPriceError)),
      );
      return;
    }

    if (!_hasChosenSchedule || _selectedScheduleDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loc.scheduleError),
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
        isAcepted: false,
        scheduleAt: Timestamp.fromDate(_selectedScheduleDate!),
      );

      final orderService = OrderService();
      await orderService.addOrder(newOrder);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text(loc.bookingSuccess)),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const MainUsersScreen()),
          (Route<dynamic> route) => false,
        );
      }
    } catch (e) {
      debugPrint("Error passing order: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.bookingFail),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: RotatingDotsIndicator()));

    final vehicleName = _vehicleSettings?.name ?? "Transport";
    final vehicleMaxWeight = _vehicleSettings?.maxWeight ?? 0;
    final vehicleVolume = _vehicleSettings?.volume ?? 0;
    
    // --- LOCALIZATION ---
    final loc = AppLocalizations.of(context)!;
    
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    final size = MediaQuery.of(context).size;
    final bool isSmallScreen = size.width < 380;
    final double headerHeight = size.height * 0.35;
    final double cardHeight = size.height * 0.28;
    final double bottomPadding = isSmallScreen ? 90 : 110;

    String? currentError = _getLocalizedError(context);
    bool canBook = _hasChosenSchedule && currentError == null;
    String currentPriceDisplay = _offerController.text.isEmpty ? "0" : _offerController.text;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Container(
            height: headerHeight,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [colorScheme.primary, colorScheme.primaryContainer],
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(40),
                bottomRight: Radius.circular(40),
              ),
            ),
          ),

          SingleChildScrollView(
            padding: EdgeInsets.only(top: headerHeight * 0.35, bottom: bottomPadding),
            child: Column(
              children: [
                _buildFloatingVehicleCard(colorScheme, textTheme, cardHeight, isSmallScreen),
                SizedBox(height: size.height * 0.03),
                
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 16 : 20),
                  child: Column(
                    children: [
                       Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: _buildMainScreenPriceCard(colorScheme, textTheme, isSmallScreen, loc),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 4,
                            child: _buildMainScreenScheduleCard(colorScheme, textTheme, isSmallScreen, loc),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                SizedBox(height: size.height * 0.02),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 16 : 20),
                  child: _buildDetailsCard(
                      vehicleName, vehicleMaxWeight, vehicleVolume, colorScheme, textTheme, isSmallScreen, loc),
                ),

                Padding(
                  padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 16 : 20),
                  child: Row(
                    mainAxisSize: MainAxisSize.min, // Shrink to content width
                    crossAxisAlignment: CrossAxisAlignment.start, // Align icon with first line of text
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2), // Slight vertical adjustment for icon alignment
                        child: Icon(
                          Icons.info_outline,
                          color: colorScheme.onSurfaceVariant,
                          size: isSmallScreen ? 16 : 18,
                        ),
                      ),
                      const SizedBox(width: 4), // Small gap between icon and text
                      Expanded(
                        child: Text(
                          loc.service_note,
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            height: 1.2, // Tighter line spacing for small screens
                          ),
                          maxLines: 3, // Prevent overflow on very small screens
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )

              ],
            ),
          ),

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
                    ),
                  ),
                  Expanded(
                    child: Text(
                      vehicleName,
                      textAlign: TextAlign.center,
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: isSmallScreen ? 20 : 24,
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
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 16 : 20),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: canBook ? _passAnOrder : null,
            style: FilledButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 16 : 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              backgroundColor: colorScheme.primary,
              disabledBackgroundColor: Colors.grey.shade400,
            ),
            child: Text(
              loc.confirmBookingButton(currentPriceDisplay),
              style: TextStyle(
                fontSize: isSmallScreen ? 16 : 18, 
                fontWeight: FontWeight.w900, 
                letterSpacing: 1.1
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- NEW WIDGETS FOR MAIN SCREEN ---

  Widget _buildMainScreenPriceCard(ColorScheme colorScheme, TextTheme textTheme, bool isSmall, AppLocalizations loc) {
    return GestureDetector(
      onTap: () => _showPriceOnlyDialog(colorScheme, textTheme),
      child: Container(
         padding: EdgeInsets.all(isSmall ? 12 : 16),
         decoration: BoxDecoration(
           color: colorScheme.primaryContainer.withOpacity(0.5),
           borderRadius: BorderRadius.circular(24),
           border: Border.all(color: colorScheme.primary.withOpacity(0.3)),
         ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Row(
               children: [
                 Icon(Icons.edit, size: 16, color: colorScheme.primary),
                 const SizedBox(width: 4),
                 // LOCALIZED
                 Text(loc.yourOfferLabel, style: textTheme.labelLarge?.copyWith(color: colorScheme.primary)),
               ],
             ),
            const SizedBox(height: 8),
            RichText(
              text: TextSpan(
                style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900, color: colorScheme.onSurface),
                children: [
                   TextSpan(text: _offerController.text.isEmpty ? "0" : _offerController.text, 
                    style: TextStyle(fontSize: isSmall ? 24 : 28)),
                   TextSpan(text: " DT", style: textTheme.titleMedium?.copyWith(color: colorScheme.primary)),
                ]
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainScreenScheduleCard(ColorScheme colorScheme, TextTheme textTheme, bool isSmall, AppLocalizations loc) {
    // LOCALIZED
    String scheduleText = loc.selectTimeLabel;
    IconData scheduleIcon = Icons.calendar_today_rounded;
    Color bgColor = colorScheme.surfaceContainerHighest;
    Color textColor = colorScheme.onSurfaceVariant;

    if (_hasChosenSchedule && _selectedScheduleDate != null) {
      scheduleText = "${_selectedScheduleDate!.day}/${_selectedScheduleDate!.month} @ ${_selectedScheduleDate!.hour.toString().padLeft(2,'0')}:${_selectedScheduleDate!.minute.toString().padLeft(2,'0')}";
      scheduleIcon = Icons.check_circle_rounded;
      bgColor = colorScheme.secondaryContainer;
      textColor = colorScheme.onSecondaryContainer;
    }

    return GestureDetector(
      onTap: () => _selectScheduleDate(context),
      child: Container(
         padding: EdgeInsets.all(isSmall ? 12 : 16),
         decoration: BoxDecoration(
           color: bgColor,
           borderRadius: BorderRadius.circular(24),
           border: Border.all(color: _hasChosenSchedule ? colorScheme.secondary : Colors.transparent),
         ),
        child: Column(
           crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
               children: [
                 Icon(scheduleIcon, size: 16, color: textColor),
                 const SizedBox(width: 4),
                 // LOCALIZED
                 Text(loc.scheduleLabel, style: textTheme.labelLarge?.copyWith(color: textColor)),
               ],
             ),
             const SizedBox(height: 8),
             Text(
              scheduleText,
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: textColor, fontSize: isSmall? 15 : 16),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
               if (!_hasChosenSchedule) 
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                // LOCALIZED
                child: Text(loc.requiredLabel, style: textTheme.bodySmall?.copyWith(color: colorScheme.error)),
              )

          ],
        ),
      ),
    );
  }


  // --- MODAL DIALOG ---

  Future<void> _showPriceOnlyDialog(
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) async {
    final loc = AppLocalizations.of(context)!;
    double tempOffer = double.tryParse(_offerController.text) ?? _calculatedEstimatedPrice;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final minPrice = _minAllowedPrice;
          final maxPrice = _maxAllowedPrice;
          final bottomInset = MediaQuery.of(context).viewInsets.bottom; 
          final size = MediaQuery.of(context).size;
          final isSmallScreen = size.width < 380;

          Color statusColor;
          String statusText;

          if (tempOffer < minPrice) {
            statusColor = Colors.orange;
            statusText = loc.tooLow;
          } else if (tempOffer > maxPrice) {
            statusColor = Colors.red;
            statusText = loc.tooHigh;
          } else {
            statusColor = Colors.green;
            statusText = loc.looksGood;
          }

          return Container(
            padding: EdgeInsets.only(bottom: bottomInset + 20, top: 10, left: 20, right: 20),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    width: 40, height: 4,
                    decoration: BoxDecoration(color: colorScheme.outlineVariant, borderRadius: BorderRadius.circular(10)),
                  ),
                  // LOCALIZED
                  Text(loc.adjustOfferTitle, style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  // LOCALIZED
                  Text(loc.suggestedPrice(_calculatedEstimatedPrice.toStringAsFixed(0)), style: textTheme.bodyMedium?.copyWith(color: colorScheme.primary)),
                  
                  const SizedBox(height: 24),

                  Stack(
                    alignment: Alignment.center,
                    children: [
                        Opacity(
                          opacity: 0,
                          child: TextField(
                            keyboardType: const TextInputType.numberWithOptions(decimal: false),
                            autofocus: true,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
                            onChanged: (value) {
                              if(value.isNotEmpty) {
                                setDialogState(() {
                                  tempOffer = double.tryParse(value) ?? tempOffer;
                                });
                              }
                            },
                          ),
                        ),
                         Container(
                          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 32),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: statusColor, width: 3),
                             boxShadow: [BoxShadow(color: statusColor.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 5))],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                tempOffer.toStringAsFixed(0),
                                style: textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w900, color: statusColor, fontSize: isSmallScreen ? 40 : 48),
                              ),
                              const SizedBox(width: 8),
                              Text("DT", style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.outline)),
                            ],
                          ),
                        ),
                    ],
                  ),
                 
                  const SizedBox(height: 16),
                  Text(statusText, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 16)),
                  
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      // LOCALIZED
                      _buildRangeBadge(loc.minLabel, minPrice, statusColor == Colors.orange, colorScheme, textTheme),
                       Container(height: 30, width: 1, color: colorScheme.outlineVariant),
                      _buildRangeBadge(loc.maxLabel, maxPrice, statusColor == Colors.red, colorScheme, textTheme),
                    ],
                  ),

                  const SizedBox(height: 30),

                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: (statusColor == Colors.green)
                          ? () {
                              setState(() {
                                _offerController.text = tempOffer.toStringAsFixed(0);
                                _validateOffer(_offerController.text);
                              });
                              Navigator.pop(context);
                            }
                          : null, 
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        backgroundColor: statusColor == Colors.green ? colorScheme.primary : Colors.grey,
                      ),
                      child: Text(
                        // LOCALIZED
                        loc.setPriceButton,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFloatingVehicleCard(ColorScheme colorScheme, TextTheme textTheme, double height, bool isSmall) {
    return Container(
      height: height,
      margin: EdgeInsets.symmetric(horizontal: isSmall ? 20 : 30),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: -30, right: -30,
            child: Container(
              width: height * 0.75, height: height * 0.75,
              decoration: BoxDecoration(color: colorScheme.onPrimary.withOpacity(0.2), shape: BoxShape.circle),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Image.asset(widget.image, fit: BoxFit.contain),
          ),
          Positioned(
            bottom: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: colorScheme.shadow.withOpacity(0.1), blurRadius: 8)],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.route, size: 18, color: colorScheme.outline),
                  const SizedBox(width: 6),
                  Text(
                    "${_calculatedDistanceKm.toStringAsFixed(1)} km",
                    style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, fontSize: isSmall ? 14 : 16, color: colorScheme.onSurface),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRangeBadge(String label, double value, bool isActive, ColorScheme colorScheme, TextTheme textTheme) {
    return Column(
      children: [
        Text(label.toUpperCase(), style: textTheme.labelMedium?.copyWith(color: colorScheme.outline)),
        const SizedBox(height: 4),
        Text(
          "${value.toStringAsFixed(0)} DT",
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: isActive ? colorScheme.error : colorScheme.onSurface,
             fontSize: 18
          ),
        ),
      ],
    );
  }

  Widget _buildDetailsCard(String name, double weight, double vol, ColorScheme colorScheme, TextTheme textTheme, bool isSmall, AppLocalizations loc) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // LOCALIZED
            Text(loc.vehicleDetailsTitle, style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, fontSize: isSmall ? 18 : 22)),
            const SizedBox(height: 16),
            _buildDetailRow(Icons.local_shipping_outlined, loc.typeLabel, name, colorScheme, textTheme),
            const Divider(height: 24),
            _buildDetailRow(Icons.scale_outlined, loc.maxWeightLabel, "$weight Kg", colorScheme, textTheme),
            const Divider(height: 24),
            _buildDetailRow(Icons.aspect_ratio_outlined, loc.volumeLabel, "$vol m³", colorScheme, textTheme),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value, ColorScheme colorScheme, TextTheme textTheme) {
    return Row(
      children: [
        Icon(icon, color: colorScheme.primary, size: 24),
        const SizedBox(width: 12),
        Text(label, style: textTheme.bodyLarge?.copyWith(color: colorScheme.onSurfaceVariant)),
        const Spacer(),
        Text(value, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
      ],
    );
  }
}