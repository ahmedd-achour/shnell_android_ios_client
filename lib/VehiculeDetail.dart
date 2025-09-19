import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as lt;
import 'package:intl/intl.dart';
// Note: Assuming 'dots.dart', 'mainUsers.dart', 'destinationdata.dart',
// and 'oredrs.dart', 'orderService.dart' are in your project.
import 'package:shnell/dots.dart';
import 'package:shnell/mainUsers.dart';
import 'package:shnell/model/destinationdata.dart';
import 'package:shnell/model/oredrs.dart';
import 'package:shnell/orderService.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class VehicleDetailScreen extends StatefulWidget {
  final String type;
  final String image;
  final lt.LatLng pickupLocation;
  final List<DropOffData> dropOffDestination;
  final String pickup_name;


  const VehicleDetailScreen({
    Key? key,
    required this.type,
    required this.image,
    required this.pickupLocation,
    required this.dropOffDestination,
    required this.pickup_name,
  }) : super(key: key);

  @override
  State<VehicleDetailScreen> createState() => _VehicleDetailScreenState();
}

class _VehicleDetailScreenState extends State<VehicleDetailScreen> {
  // State variables
  bool _isLoading = true;
  bool _isInstantBooking = true;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  double _calculatedDistanceKm = 0.0;
  double _calculatedEstimatedPrice = 0.0;
  double _userOfferPrice = 0.0;
  
  bool _isMakingOffer = false;

  // Google Maps API key
  static const String _googleMapsApiKey = "AIzaSyCPNt6re39yO5lhlD-H1eXWmRs4BAp_y6w";
  

  @override
  void initState() {
    super.initState();
    _setAndCalculateRouteData();
  }

  void _setAndCalculateRouteData() async {
    if (widget.dropOffDestination.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Veuillez sélectionner au moins une destination.")),
        );
        setState(() => _isLoading = false);
      }
      return;
    }

    if (_googleMapsApiKey == "YOUR_GOOGLE_MAPS_API_KEY_HERE") {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Veuillez fournir une clé API Google Maps valide.")),
        );
        setState(() => _isLoading = false);
      }
      return;
    }

    final List<lt.LatLng> destinations = widget.dropOffDestination.map((dropOff) => dropOff.destination).toList();

    final distance = await getGoogleRoadDistance(
      widget.pickupLocation,
      destinations,
      _googleMapsApiKey,
    );

    if (mounted && distance != null) {
      setState(() {
        _calculatedDistanceKm = distance;
        _calculatedEstimatedPrice = _calculatePrice(_calculatedDistanceKm, widget.type);
        _userOfferPrice = _calculatedEstimatedPrice; // Initialize offer to estimated price
        _isLoading = false;
      });
    } else if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Impossible de calculer la distance.")),
      );
    }
  }

  Future<double?> getGoogleRoadDistance(lt.LatLng origin, List<lt.LatLng> destinations, String apiKey) async {
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
          return totalDistance / 1000; // Convert to km
        } else {
          print("Erreur API Google Maps: ${data['status']}");
          if (data['error_message'] != null) {
            print("Message: ${data['error_message']}");
          }
        }
      } else {
        print("Erreur HTTP: ${response.statusCode}");
      }
    } catch (e) {
      print("Erreur réseau: $e");
    }
    return null;
  }

  double _calculatePrice(double distance, String vehicleType) {
    double basePrice, pricePerKm;
    switch (vehicleType) {
      case 'super_light':
        basePrice = 1.0;
        pricePerKm = distance < 300 ? max(0.4, (1 - (distance / 1000)) * 0.5) : 0.35;
        break;
      case 'light':
        basePrice = 25.0;
        pricePerKm = distance < 300 ? max(0.8, (1 - (distance / 1000)) * 1.4) : 0.9;
        break;
      case 'light_medium':
        basePrice = 30.0;
        pricePerKm = distance < 300 ? max(1.0, (1 - (distance / 1000)) * 1.8) : 1.2;
        break;
      case 'medium':
        basePrice = 60.0;
        pricePerKm = distance < 300 ? max(1.2, (1 - (distance / 1000)) * 2.0) : 1.4;
        break;
      case 'medium_heavy':
        basePrice = 80.0;
        pricePerKm = distance < 300 ? max(1.4, (1 - (distance / 1000)) * 2.3) : 1.6;
        break;
      case 'heavy':
        basePrice = 110.0;
        pricePerKm = distance < 300 ? max(1.8, (1 - (distance / 1000)) * 3.0) : 2.0;
        break;
      case 'super_heavy':
        basePrice = 180.0;
        pricePerKm = distance < 300 ? max(2.2, (1 - (distance / 1000)) * 3.5) : 2.5;
        break;
      default:
        basePrice = 0.0;
        pricePerKm = 0.0;
    }
    return basePrice + (distance * pricePerKm) + widget.dropOffDestination.length * 0.4;
  }

  Map<String, dynamic> getVehicleData(String type) {
    switch (type) {
      case 'super_light':
        return {'name': 'moto', 'maxWeight': 100, 'volume': 0.5};
      case 'light':
        return {'name': 'Small Van', 'maxWeight': 500, 'volume': 3};
      case 'light_medium':
        return {'name': 'Isuzu/D max', 'maxWeight': 1500, 'volume': 5};
      case 'medium':
        return {'name': 'Estafette', 'maxWeight': 3500, 'volume': 13};
      case 'medium_heavy':
        return {'name': 'Construction', 'maxWeight': 7500, 'volume': 15};
      case 'heavy':
        return {'name': 'Large Truck', 'maxWeight': 12000, 'volume': 20};
      case 'super_heavy':
        return {'name': 'Large Truck', 'maxWeight': 33000, 'volume': 25};
      default:
        return {'name': 'Unknown', 'maxWeight': 0, 'volume': 0};
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (pickedDate != null && pickedDate != _selectedDate) {
      setState(() => _selectedDate = pickedDate);
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
    );
    if (pickedTime != null && pickedTime != _selectedTime) {
      setState(() => _selectedTime = pickedTime);
    }
  }

  Future<void> _passAnOrder() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception("Utilisateur non connecté. Veuillez vous connecter.");
      }

      Map<String, dynamic>? additionalInfo;
      if (!_isInstantBooking) {
        if (_selectedDate == null || _selectedTime == null) {
          throw Exception("Veuillez sélectionner une date et une heure pour la planification.");
        }
        final fullDateTime = DateTime(
          _selectedDate!.year,
          _selectedDate!.month,
          _selectedDate!.day,
          _selectedTime!.hour,
          _selectedTime!.minute,
        );
        additionalInfo = {
          'scheduledTimestamp': Timestamp.fromDate(fullDateTime),
        };
      }

      final List<String> stopIds = [];
      for (final dropOff in widget.dropOffDestination) {
        final stopData = dropOff.toFirestore();
        final stopRef = await FirebaseFirestore.instance.collection('stops').add(stopData);
        stopIds.add(stopRef.id);
      }

      final orderPrice = _isMakingOffer ? _userOfferPrice : _calculatedEstimatedPrice;

      final newOrder = Orders(
        price: orderPrice,
        distance: _calculatedDistanceKm,
        namePickUp: widget.pickup_name,
        pickUpLocation: widget.pickupLocation,
        stops: stopIds,
        vehicleType: widget.type,
        userId: user.uid,
        isInstantDelivery: _isInstantBooking,
        additionalInfo: additionalInfo,
        isAcepted: false,
      );

      final orderService = OrderService();
      await orderService.addOrder(newOrder);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Commande créée avec succès !"),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const MainUsersScreen()),
          (Route<dynamic> route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erreur : ${e.toString()}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: RotatingDotsIndicator());
    }

    final vehicle = getVehicleData(widget.type);
    final theme = Theme.of(context);
        final l10n = AppLocalizations.of(context);


    return Theme(
      data: theme.copyWith(
        primaryColor: const Color(0xFFE5B800),
        colorScheme: theme.colorScheme.copyWith(
          primary: const Color(0xFFE5B800),
          secondary: const Color(0xFFF9DC5C),
        ),
        textTheme: theme.textTheme.apply(
        ),
      ),
      child: Scaffold(
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _passAnOrder,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE5B800),
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child:  Text(
                l10n!.confirmBooking,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,),
              ),
            ),
          ),
        ),
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 280.0,
              pinned: true,
              stretch: true,
              leading: IconButton(
                icon: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Icon(Icons.arrow_back,),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
              flexibleSpace: FlexibleSpaceBar(
                title: Text(
                  vehicle['name'],
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24,),
                ),
                centerTitle: true,
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      widget.image,
                      fit: BoxFit.fitWidth,
                    ),
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Color.fromARGB(150, 0, 0, 0),
                            Color.fromARGB(255, 0, 0, 0),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                stretchModes: const [StretchMode.zoomBackground],
              ),
            ),
            SliverList(
              delegate: SliverChildListDelegate([
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPriceSummaryCard(),
                      const SizedBox(height: 24),
                      _buildOfferToggle(),
                      if (_isMakingOffer) _buildOfferSlider(),
                      const SizedBox(height: 24),
                      _buildBookingTypeSelector(),
                      if (!_isInstantBooking) _buildDateTimePicker(),
                      const SizedBox(height: 24),
                      _buildDetailsSection(vehicle),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceSummaryCard() {
    final displayPrice = _isMakingOffer ? _userOfferPrice : _calculatedEstimatedPrice;
    final l10n = AppLocalizations.of(context);
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isMakingOffer ? l10n!.yourOffer : l10n!.estimatedPrice,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Icon(Icons.savings),
                Text(
                  "${displayPrice.toStringAsFixed(2)} DT",
                  style: const TextStyle(
                    color: Color(0xFFE5B800),
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                 Text(
                  l10n.distance,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "${_calculatedDistanceKm.toStringAsFixed(1)} km",
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfferToggle() {
    final l10n = AppLocalizations.of(context);
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SwitchListTile(
        title:  Text(
          l10n!.makeCustomOffer,
          style: TextStyle(fontWeight: FontWeight.bold,),
        ),
        value: _isMakingOffer,
        activeColor: const Color(0xFFE5B800),
        onChanged: (bool value) {
          setState(() {
            _isMakingOffer = value;
            if (!value) {
              _userOfferPrice = _calculatedEstimatedPrice;
            }
          });
        },
      ),
    );
  }

  Widget _buildOfferSlider() {
    final minPrice = _calculatedEstimatedPrice * 0.8;
    final maxPrice = _calculatedEstimatedPrice * 1.4;
    final l10n = AppLocalizations.of(context);

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Text(
              l10n!.adjustYourOffer,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,),
            ),
            const SizedBox(height: 8),
            Slider(
              value: _userOfferPrice,
              min: minPrice,
              max: maxPrice,
              divisions: 100,
              activeColor: const Color(0xFFE5B800),
              label: "${_userOfferPrice.toStringAsFixed(2)} DT",
              onChanged: (double value) {
                setState(() {
                  _userOfferPrice = value;
                });
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("${minPrice.toStringAsFixed(2)} DT",),
                Text("${maxPrice.toStringAsFixed(2)} DT"),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookingTypeSelector() {
    final l10n = AppLocalizations.of(context);

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          children: [
            _buildBookingButton(
              label: l10n!.instantTrip,
              isSelected: _isInstantBooking,
              onTap: () => setState(() => _isInstantBooking = true),
            ),
            _buildBookingButton(
              label: l10n.schedule,
              isSelected: !_isInstantBooking,
              onTap: () => setState(() => _isInstantBooking = false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookingButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFE5B800) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateTimePicker() {
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 16.0),
      child: Row(
        children: [
          Expanded(
            child: _buildDateTimeButton(
              icon: Icons.calendar_today,
              label: _selectedDate == null
                  ? l10n!.selectDate
                  : DateFormat('dd/MM/yyyy').format(_selectedDate!),
              onPressed: () => _selectDate(context),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildDateTimeButton(
              icon: Icons.access_time,
              label: _selectedTime == null ? l10n!.selectTime : _selectedTime!.format(context),
              onPressed: () => _selectTime(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateTimeButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      icon: Icon(icon, size: 20,),
      label: Text(label,),
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        side: const BorderSide( width: 1),
        padding: const EdgeInsets.symmetric(vertical: 18),
      ),
    );
  }

  Widget _buildDetailsSection(Map<String, dynamic> vehicle) {
    final l10n = AppLocalizations.of(context);

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Text(
              l10n!.details,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,),
            ),
            const Divider(height: 24,),
            _buildLocationRow(Icons.my_location, l10n.pickup, widget.pickup_name),
            const SizedBox(height: 16),
            ...widget.dropOffDestination.asMap().entries.map((entry) {
              int index = entry.key;
              String name = entry.value.destinationName;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: _buildLocationRow(
                  Icons.location_on,
                  '${l10n.arrival(index + 1)} ',
                  name,
                ),
              );
            }).toList(),
            const Divider(height: 32,),
            _buildInfoRow(Icons.fitness_center_rounded, l10n.maxWeight, "${vehicle['maxWeight']} kg"),
            const SizedBox(height: 12),
            _buildInfoRow(Icons.aspect_ratio_rounded, l10n.maxVolume, "${vehicle['volume']} m³"),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationRow(IconData icon, String title, String location) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFE5B800), size: 20),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 14,),
              ),
              Text(
                location,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20,),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 16,),
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold,),
        ),
      ],
    );
  }
}
