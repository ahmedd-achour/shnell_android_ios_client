import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as lt;
import 'package:intl/intl.dart';
import 'package:shnell/dots.dart';
import 'package:shnell/mainUsers.dart';
import 'package:shnell/model/destinationdata.dart';
import 'package:shnell/model/oredrs.dart';
import 'package:shnell/orderService.dart';

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
        basePrice = 20.0;
        pricePerKm = distance < 300 ? max(0.8, (1 - (distance / 1000)) * 1.2) : 0.9;
        break;
      case 'light_medium':
        basePrice = 40.0;
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
        return {'name': 'Small Van', 'maxWeight': 800, 'volume': 3};
      case 'light_medium':
        return {'name': 'Isuzu/D max', 'maxWeight': 1500, 'volume': 5};
      case 'medium':
        return {'name': 'Estafette', 'maxWeight': 3500, 'volume': 13};
      case 'medium_heavy':
        return {'name': 'Construction', 'maxWeight': 7500, 'volume': 15};
      case 'heavy':
        return {'name': 'Large Truck', 'maxWeight': 12000, 'volume': 20};
      case 'super_heavy':
        return {'name': 'Large Truck', 'maxWeight': 20000, 'volume': 25};
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

      // Store each DropOffData in the 'stops' collection and collect their IDs
      final List<String> stopIds = [];
      for (final dropOff in widget.dropOffDestination) {
        final stopData = dropOff.toFirestore();
        final stopRef = await FirebaseFirestore.instance.collection('stops').add(stopData);
        stopIds.add(stopRef.id);
      }

      // Create the new order with stopIds as List<String>
      final newOrder = Orders(
        price: _calculatedEstimatedPrice,
        distance: _calculatedDistanceKm,
        namePickUp: widget.pickup_name,
        pickUpLocation: widget.pickupLocation,
        stops: stopIds, // Store directly as List<String>
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

    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _passAnOrder,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.amber,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text(
              "Confirmer la Réservation",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 250.0,
            pinned: true,
            stretch: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                vehicle['name'],
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
              ),
              centerTitle: true,
              background: ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Colors.white, Colors.transparent],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ).createShader(bounds),
                blendMode: BlendMode.darken,
                child: Image.asset(
                  widget.image,
                  fit: BoxFit.fitWidth,
                ),
              ),
              stretchModes: const [StretchMode.zoomBackground],
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPriceSummaryCard(),
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
    );
  }

  Widget _buildPriceSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(24.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "PRIX ESTIMÉ",
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                "${_calculatedEstimatedPrice.toStringAsFixed(2)} TND",
                style: const TextStyle(
                  color: Colors.amber,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                "DISTANCE",
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                "${_calculatedDistanceKm.toStringAsFixed(1)} km",
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBookingTypeSelector() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _isInstantBooking = true),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: _isInstantBooking ? Colors.amber : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    "Course Instantanée",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _isInstantBooking = false),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: !_isInstantBooking ? Colors.amber : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    "Planifier",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateTimePicker() {
    return Padding(
      padding: const EdgeInsets.only(top: 16.0),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text(
                _selectedDate == null
                    ? 'Choisir date'
                    : DateFormat('dd/MM/yyyy').format(_selectedDate!),
              ),
              onPressed: () => _selectDate(context),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                side: BorderSide(color: Colors.grey.shade400, width: 1),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.access_time, size: 18),
              label: Text(
                _selectedTime == null ? 'Choisir heure' : _selectedTime!.format(context),
              ),
              onPressed: () => _selectTime(context),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                side: BorderSide(color: Colors.grey.shade400, width: 1),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsSection(Map<String, dynamic> vehicle) {
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "DÉTAILS",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Divider(height: 24),
          _buildLocationRow(Icons.my_location, 'Départ', widget.pickup_name),
          const SizedBox(height: 16),
          ...widget.dropOffDestination.asMap().entries.map((entry) {
            int index = entry.key;
            String name = entry.value.destinationName;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: _buildLocationRow(
                Icons.location_on,
                'Arrivée ${index + 1}',
                name,
              ),
            );
          }).toList(),
          const Divider(height: 32),
          _buildInfoRow(Icons.fitness_center_rounded, 'Poids Max.', "${vehicle['maxWeight']} kg"),
          const SizedBox(height: 12),
          _buildInfoRow(Icons.aspect_ratio_rounded, 'Volume Max.', "${vehicle['volume']} m³"),
        ],
      ),
    );
  }

  Widget _buildLocationRow(IconData icon, String title, String location) {
    return Row(
      children: [
        Icon(icon, color: Colors.amber, size: 20),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 14, color: Colors.grey),
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
        Icon(icon, size: 20),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 16),
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}