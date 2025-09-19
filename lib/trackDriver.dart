import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as latlong;
import 'package:shnell/dots.dart';
import 'package:shnell/functions.dart';
import 'package:shnell/model/destinationdata.dart';
import 'package:shnell/model/oredrs.dart';
import 'package:shnell/ratingsScreen.dart';
import 'package:shnell/model/users.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';


// --- Helper Models & Enums ---
enum ScreenState { loading, ready, error }
enum DealStatus { accepted, almost, terminated, canceled }

class Deoaklna extends StatefulWidget {
  final String dealId;
  final bool watcher;
  const Deoaklna({super.key, required this.dealId , this.watcher=true});

  @override
  State<Deoaklna> createState() => _DeliveryTrackingTabState();
}

class _DeliveryTrackingTabState extends State<Deoaklna> with AutomaticKeepAliveClientMixin {
  // Configuration Constants
  static const String _googleApiKey = "AIzaSyCPNt6re39yO5lhlD-H1eXWmRs4BAp_y6w";
  static const int _networkTimeoutSeconds = 10;
  static const double _driverFocusZoomLevel = 17.0;
  static const double _offRouteThresholdMeters = 501.0;
  static const Duration _fetchTimeout = Duration(seconds: 8);

  // State Variables
  final Completer<GoogleMapController> _mapController = Completer();
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  final Set<Circle> _circles = {};
  final ValueNotifier<Set<Marker>> _markersNotifier = ValueNotifier({});
  final ValueNotifier<Set<Circle>> _circlesNotifier = ValueNotifier({});
  ScreenState _screenState = ScreenState.loading;
  Orders? _order;
  latlong.LatLng? _pickupLocation;
  List<DropOffData> _allDropoffs = []; // All stops, regardless of isDelivered
  List<DropOffData> _remainingDropoffs = []; // Only undelivered stops
  List<String> _stopIds = [];
  final ValueNotifier<String> _distanceRemaining = ValueNotifier('--');
  final ValueNotifier<String> _timeRemaining = ValueNotifier('--');
  String? _driverID;
  String? _driverPhone;
  String? _orderId;
  latlong.LatLng? _driverPosition;
  BitmapDescriptor _driverIcon = BitmapDescriptor.defaultMarker;
  BitmapDescriptor _pickupIcon = BitmapDescriptor.defaultMarker;
  BitmapDescriptor _undeliveredStopIcon = BitmapDescriptor.defaultMarker;

  BitmapDescriptor _deliveredStopIcon = BitmapDescriptor.defaultMarker;
  DealStatus _dealStatus = DealStatus.accepted;
  bool _isInitialRouteDrawn = false;


  // New Variables for Optimized Model
  Timer? _assuranceTimer;
  List<LatLng> _fullRouteCoordinates = [];
  double _initialTotalDuration = 0.0;
  String? _errorMessage;
  double _initialTotalDistance = 0.0;
  
  // Cache for marker icons
  static BitmapDescriptor? _cachedDriverIcon;
  static BitmapDescriptor? _cachedPickupIcon;
  static BitmapDescriptor? _cachedUndeliveredStopIcon;
  static BitmapDescriptor? _cachedDeliveredStopIcon;

  StreamSubscription? _dealStatusSubscription;
  StreamSubscription? _orderSubscription;
  StreamSubscription? _driverLocationSubscription;
  StreamSubscription? _stopsSubscription;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadCustomMarkerIcons();
  }

  @override
  void dispose() {
    _driverLocationSubscription?.cancel();
    _dealStatusSubscription?.cancel();
    _orderSubscription?.cancel();
    _stopsSubscription?.cancel();
    _assuranceTimer?.cancel();
    _distanceRemaining.dispose();
    _timeRemaining.dispose();
    _markersNotifier.dispose();
    _circlesNotifier.dispose();
    _mapController.future.then((controller) => controller.dispose());
    super.dispose();
  }

  // Helper to convert Firestore stop document to DropOffData
  DropOffData _dropOffFromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    debugPrint('Parsing stop ${doc.id}: $data');
    if (!data.containsKey('destination') || !data.containsKey('destinationName')) {
      debugPrint('Warning: Missing required fields in stop ${doc.id}');
    }
    return DropOffData(
      customerName: data['name'] as String?,
      customerPhoneNumber: data['phoneNumber'] as String?,
      destination: latlong.LatLng(
        (data['destination']?['latitude'] as num?)?.toDouble() ?? 0.0,
        (data['destination']?['longitude'] as num?)?.toDouble() ?? 0.0,
      ),
      destinationName: data['destinationName'] as String? ?? 'Unknown Stop',
      isDelivered: data['isdelivered'] as bool? ?? false,
    );
  }

  // Initialization & Data Fetching
  Future<void> _initializeScreen() async {
    debugPrint('Initializing screen for dealId: ${widget.dealId}');
    if (widget.dealId.isEmpty) {
      setState(() {
        _screenState = ScreenState.error;
        _errorMessage = 'Invalid deal ID';
        _dealStatus = DealStatus.accepted;
      });
      debugPrint('Error: Invalid deal ID');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _screenState = ScreenState.error;
        _errorMessage = 'User not authenticated';
        _dealStatus = DealStatus.accepted;
      });
      debugPrint('Error: User not authenticated');
      return;
    }

    setState(() => _screenState = ScreenState.loading);

    try {
      await _fetchInitialData().timeout(_fetchTimeout, onTimeout: () {
        throw TimeoutException('Data fetch timed out after ${_fetchTimeout.inSeconds} seconds');
      });
      _listenToDealStatus();
      _listenToOrderUpdates();
      _listenToDriverLocation();
      _listenToStopsUpdates();
      
      setState(() {
        _screenState = ScreenState.ready;
        _errorMessage = null;
      });
      debugPrint('Screen initialized successfully');
    } catch (e) {
      debugPrint('Error initializing screen: $e');
      setState(() {
        _screenState = ScreenState.error;
        _errorMessage = e.toString();
        _dealStatus = DealStatus.accepted;
      });
    }
  }

  Future<void> _fetchInitialData() async {
    debugPrint('Fetching initial data for dealId: ${widget.dealId}');
    final dealRef = FirebaseFirestore.instance.collection('deals').doc(widget.dealId);
    final dealDoc = await dealRef.get();
    if (!dealDoc.exists || dealDoc.data() == null) {
      debugPrint('Deal not found: ${widget.dealId}');
      throw Exception('Deal not found');
    }

    final dealData = dealDoc.data()!;
    debugPrint('Deal data: $dealData');
    _driverID = dealData['idDriver'] as String?;
    _orderId = dealData['idOrder'] as String?;
    if (_driverID == null || _driverID!.isEmpty) {
      debugPrint('Driver ID missing in deal: ${widget.dealId}');
      throw Exception('Driver ID missing');
    }
    if (_orderId == null || _orderId!.isEmpty) {
      debugPrint('Order ID missing in deal: ${widget.dealId}');
      throw Exception('Order ID missing');
    }

    final orderDoc = await FirebaseFirestore.instance.collection('orders').doc(_orderId).get();
    if (!orderDoc.exists || orderDoc.data() == null) {
      debugPrint('Order not found: $_orderId');
      throw Exception('Order not found');
    }

    await _fetchDriverPhone();

    try {
      final order = Orders.fromFirestore(orderDoc);
      final stopIds = order.stops.where((id) => id.isNotEmpty).toList();
      debugPrint('Order stop IDs: $stopIds');
      final List<DropOffData> stopData = [];
      for (final stopId in stopIds) {
        final stopDoc = await FirebaseFirestore.instance.collection('stops').doc(stopId).get();
        if (stopDoc.exists) {
          stopData.add(_dropOffFromFirestore(stopDoc));
        } else {
          debugPrint('Stop not found: $stopId');
        }
      }
      debugPrint('Order parsed: ${order.namePickUp}, ${stopData.length} stops');
      setState(() {
        _order = order;
        _pickupLocation = order.pickUpLocation;
        _stopIds = stopIds;
        _allDropoffs = stopData;
        _remainingDropoffs = stopData.where((dropOff) => dropOff.isDelivered != true).toList();
        _dealStatus = _parseDealStatus(dealData['status'] as String?);
        _addStaticMarkers();
      });
    } catch (e) {
      debugPrint('Error parsing order or stops: $e');
      throw Exception('Failed to parse order or stop data: $e');
    }
  }

  Future<void> _fetchDriverPhone() async {
    if (_driverID == null) return;
    try {
      final driverDoc = await FirebaseFirestore.instance.collection('users').doc(_driverID).get();
      if (driverDoc.exists && driverDoc.data() != null) {
        final driverData = shnellUsers.fromJson(driverDoc.data()!);
        setState(() {
          _driverPhone = driverData.phone;
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch driver phone number: $e');
    }
  }

  // Real-time Listeners
  void _listenToDealStatus() {
    _dealStatusSubscription = FirebaseFirestore.instance
        .collection('deals')
        .doc(widget.dealId)
        .snapshots()
        .listen((snapshot) async {
      if (!mounted || !snapshot.exists || snapshot.data() == null) {
        debugPrint('Deal snapshot invalid or missing for dealId: ${widget.dealId}');
        return;
      }

      final status = _parseDealStatus(snapshot.data()!['status'] as String?);
      if (_dealStatus == status) return;

      debugPrint('Deal status updated to: $status');
      setState(() {
        _dealStatus = status;
        _isInitialRouteDrawn = false;
        _fullRouteCoordinates.clear();
      });
      await _updateRouteBasedOnStatus();
      if (status == DealStatus.terminated) {
        _showRatingDialog();
      } else if (status == DealStatus.canceled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Delivery has been canceled.'),
            backgroundColor: Colors.red,
          ),
        );
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) Navigator.of(context).pop();
        });
      }
    }, onError: (e) {
      debugPrint('Deal status stream error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update deal status: $e'), backgroundColor: Colors.red),
        );
      }
    });
  }

  void _listenToOrderUpdates() {
    _orderSubscription = FirebaseFirestore.instance
        .collection('orders')
        .doc(_orderId)
        .snapshots()
        .listen((snapshot) async {
      if (!mounted || !snapshot.exists || snapshot.data() == null) {
        debugPrint('Order snapshot invalid or missing for orderId: $_orderId');
        return;
      }

      try {
        final newOrder = Orders.fromFirestore(snapshot);
        final stopIds = newOrder.stops.where((id) => id.isNotEmpty).toList();
        debugPrint('Order update stop IDs: $stopIds');
        final List<DropOffData> newStopData = [];
        for (final stopId in stopIds) {
          final stopDoc = await FirebaseFirestore.instance.collection('stops').doc(stopId).get();
          if (stopDoc.exists) {
            newStopData.add(_dropOffFromFirestore(stopDoc));
          } else {
            debugPrint('Stop not found in order update: $stopId');
          }
        }
        final newRemainingDropoffs = newStopData.where((dropOff) => dropOff.isDelivered != true).toList();
        debugPrint('Order updated: ${newOrder.namePickUp}, ${newStopData.length} stops, ${newRemainingDropoffs.length} remaining');

        if (_order != null &&
            _order!.stops == newOrder.stops &&
            _order!.price == newOrder.price &&
            _order!.isInstantDelivery == newOrder.isInstantDelivery &&
            newOrder.additionalInfo?['scheduledTimestamp']?.toDate() ==
                newOrder.additionalInfo?['scheduledTimestamp']?.toDate()) {
          return;
        }

        setState(() {
          _order = newOrder;
          _pickupLocation = newOrder.pickUpLocation;
          _stopIds = stopIds;
          _allDropoffs = newStopData;
          _remainingDropoffs = newRemainingDropoffs;
          _addStaticMarkers();
          _fullRouteCoordinates.clear();
        });
        if (_dealStatus != DealStatus.terminated && _dealStatus != DealStatus.canceled) {
          await _updateRouteBasedOnStatus();
        }
      } catch (e) {
        debugPrint('Error processing order update: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update order: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }, onError: (e) {
      debugPrint('Order stream error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update order: $e'), backgroundColor: Colors.red),
        );
      }
    });
  }

  void _listenToStopsUpdates() {
    if (_stopIds.isEmpty) {
      debugPrint('No stop IDs to listen for updates');
      return;
    }
    _stopsSubscription = FirebaseFirestore.instance
        .collection('stops')
        .where(FieldPath.documentId, whereIn: _stopIds)
        .snapshots()
        .listen((snapshot) async {
      if (!mounted) return;
      try {
        final newStopData = snapshot.docs
            .where((doc) => doc.exists)
            .map((doc) => _dropOffFromFirestore(doc))
            .toList();
        final newRemainingDropoffs = newStopData.where((dropOff) => dropOff.isDelivered != true).toList();
        debugPrint('Stops updated: ${newStopData.length} stops, ${newRemainingDropoffs.length} remaining');
        setState(() {
          _allDropoffs = newStopData;
          _remainingDropoffs = newRemainingDropoffs;
          _addStaticMarkers();
          _fullRouteCoordinates.clear();
        });
        if (_dealStatus != DealStatus.terminated && _dealStatus != DealStatus.canceled) {
          await _updateRouteBasedOnStatus();
        }
      } catch (e) {
        debugPrint('Error processing stops update: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update stops: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }, onError: (e) {
      debugPrint('Stops stream error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update stops: $e'), backgroundColor: Colors.red),
        );
      }
    });
  }

  void _listenToDriverLocation() {
    if (_driverID == null || _driverID!.isEmpty) {
      debugPrint('Cannot listen to driver location: driverID is null or empty');
      return;
    }

    _driverLocationSubscription = FirebaseDatabase.instance
        .ref('locations/$_driverID/coordinates')
        .onValue
        .listen((event) async {
      if (!mounted || !event.snapshot.exists || event.snapshot.value == null) {
        debugPrint('Driver location snapshot invalid or missing for driverID: $_driverID');
        return;
      }

      final data = event.snapshot.value as List;
      final newPosition = latlong.LatLng(data[1] as double, data[0] as double);

      debugPrint('Driver position updated: $newPosition');
      setState(() {
        _driverPosition = newPosition;
        _updateDriverMarker();
      });

      if (_dealStatus == DealStatus.terminated || _dealStatus == DealStatus.canceled) return;

      if (_fullRouteCoordinates.isEmpty) {
        await _updateRouteBasedOnStatus();
      } else {
        _updateClientSideRoute(newPosition);
        final isOffRoute = _isOffRoute(newPosition);
        if (isOffRoute) {
          debugPrint('Driver is off-route. Forcing new API call.');
          _assuranceTimer?.cancel();
          await _updateRouteBasedOnStatus();
        }
      }

      if (!(_assuranceTimer?.isActive ?? false)) {
        _assuranceTimer = Timer(const Duration(minutes: 1440), () async {
        //  await _updateRouteBasedOnStatus();
        });
      }
    }, onError: (e) {
      debugPrint('Driver location stream error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update driver location: $e'), backgroundColor: Colors.red),
        );
      }
    });
  }


  Future<void> _updateRouteBasedOnStatus() async {
    List<latlong.LatLng> allPoints = [];
    if (_dealStatus == DealStatus.accepted && _pickupLocation != null && _driverPosition != null) {
      allPoints = [
        _driverPosition!,
        _pickupLocation!,
        ..._allDropoffs.map((d) => d.destination), // Include all stops for route
      ];
    } else if (_dealStatus == DealStatus.almost && _driverPosition != null) {
      allPoints = [
        _driverPosition!,
        ..._remainingDropoffs.map((d) => d.destination), // Only undelivered stops
      ];
    }

    debugPrint('Route points: $allPoints');
    if (allPoints.length >= 2) {
      debugPrint('Initiating API call for route update with ${allPoints.length} points');
      _assuranceTimer?.cancel();
      try {
        await _getRouteAndSetData(allPoints);
      } catch (e) {
        debugPrint('API call failed: $e');
      }
    } else {
      debugPrint('Not enough points for route: $allPoints');
      setState(() {
        _polylines.clear();
        _fullRouteCoordinates.clear();
        _distanceRemaining.value = '--';
        _timeRemaining.value = '--';
      });
    }
  }

Future<void> _getRouteAndSetData(List<latlong.LatLng> allPoints) async {
  try {
    // Step 1: Always try Firestore first
   await _getRouteFromFirestore();
    debugPrint('Firestore route fetched successfully');

    // Step 2: Check if driver is off-route
    if (_driverPosition != null && _isOffRoute(_driverPosition!)) {
      debugPrint('Driver is off-route, forcing new route fetch...');
   //   try {
        // Step 3: Try OSRM if off-route
        //await _getRouteFromOSRM(allPoints).timeout(Duration(seconds: _networkTimeoutSeconds));
     //   debugPrint('OSRM route fetched successfully');
  //    } catch (osrmError) {
     //   debugPrint('OSRM failed: $osrmError. Trying Google fallback...');
        try {
          // Step 4: Fall back to Google if OSRM fails
          await _getRouteFromGoogle(allPoints).timeout(Duration(seconds: _networkTimeoutSeconds));
          debugPrint('Google route fetched successfully');
        } catch (googleError) {
          debugPrint('Google fallback failed: $googleError');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to load route: $googleError'), backgroundColor: Colors.red),
            );
          }
        }
    //  }
    } else {
      debugPrint('Driver is on-route, using Firestore route.');
    }
  } catch (firestoreErr) {
    debugPrint('Firestore failed: $firestoreErr. Trying OSRM...');
    try {
      // Step 5: If Firestore fails, try OSRM
    //  await _getRouteFromOSRM(allPoints).timeout(Duration(seconds: _networkTimeoutSeconds));
      debugPrint('OSRM route fetched successfully');
    } catch (osrmError) {
      debugPrint('OSRM failed: $osrmError. Trying Google fallback...');
      try {
        // Step 6: Fall back to Google if OSRM fails
        await _getRouteFromGoogle(allPoints).timeout(Duration(seconds: _networkTimeoutSeconds));
        debugPrint('Google route fetched successfully');
      } catch (googleError) {
        debugPrint('Google fallback failed: $googleError');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load route: $googleError'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }
}

  double apiCalls = 0;


/*
  Future<void> _getRouteFromOSRM(List<latlong.LatLng> allPoints) async {
    final waypointString = allPoints.map((loc) => '${loc.longitude},${loc.latitude}').join(';');
    final url = 'https://router.project-osrm.org/route/v1/driving/$waypointString?overview=full&geometries=polyline&steps=true';
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('OSRM server error with status ${response.statusCode}');
    }
    setState(() {
      apiCalls += 1;
    });
    final data = json.decode(response.body);
    if (data['code'] != 'Ok' || data['routes'].isEmpty) {
      throw Exception('OSRM API Error: ${data["message"] ?? "Unknown"}');
    }

    final route = data['routes'][0];
    final coordinates = _decodeOSRMPolyline(route['geometry'] as String);
    _initialTotalDistance = (route['distance'] as num).toDouble();
    _initialTotalDuration = (route['duration'] as num).toDouble();
    _fullRouteCoordinates = coordinates;

      final cacheRef = FirebaseFirestore.instance.collection('routes').doc(_driverID);
         await cacheRef.set({
      'dealId': widget.dealId,
      'driverId': _driverID,
      'timestamp': FieldValue.serverTimestamp(),
      'routeData': data,
    });


    _updateClientSideRoute(_driverPosition!);
    
    if (!_isInitialRouteDrawn && _driverPosition != null) {
      final destination = _dealStatus == DealStatus.accepted
          ? _pickupLocation
          : _remainingDropoffs.isNotEmpty
              ? _remainingDropoffs.first.destination
              : _allDropoffs.isNotEmpty
                  ? _allDropoffs.first.destination
                  : null;
      if (destination != null) {
        await _zoomToFitRoute(
          _driverPosition!.toLatLng(),
          destination.toLatLng(),
        );
        _isInitialRouteDrawn = true;
      }
    }
  }

  List<LatLng> _decodeOSRMPolyline(String encoded) {
    var points = <LatLng>[];
    int index = 0, len = encoded.length;
    int lat = 0, lon = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlon = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lon += dlon;

      points.add(LatLng(lat / 1E5, lon / 1E5));
    }
    return points;
  }*/
/*
  Future<void> _getRouteFromFirestore() async {

    final String _driverId = await Maptools().getFieldValue(collectionName: 'deals', documentId: widget.dealId, fieldName: 'idDriver');
    if(_driverId==null){
        throw Exception('Route data missing in Firestore document');
    }
    try {
      final doc = await FirebaseFirestore.instance.collection('routes').doc(_driverId).get();
      if (!doc.exists || doc.data() == null) {
        throw Exception('Route document not found for driver $_driverId');
      }

      final data = doc.data()!;
      final routeData = data['routeData'] as Map<String, dynamic>?;
      if (routeData == null) {
        throw Exception('Route data missing in Firestore document');
      }

      if (routeData['status'] != 'OK' && routeData['status'] != 'FALLBACK' && routeData['status'] != 'NO_WAYPOINTS') {
        throw Exception('Invalid route status: ${routeData['status']}');
      }
      if (routeData['routes'] == null || (routeData['routes'] as List).isEmpty) {
        throw Exception('No routes found in Firestore data');
      }

      final List<LatLng> coordinates = [];
      _initialTotalDistance = 0;
      _initialTotalDuration = 0;

      if (routeData['status'] == 'OK') {
        // Process Google API response
        for (var leg in routeData['routes'][0]['legs']) {
          _initialTotalDistance += (leg['distance']['value'] as num).toDouble();
          _initialTotalDuration += (leg['duration']['value'] as num).toDouble();
          for (var step in leg['steps']) {
            final points = _decodeGooglePolyline(step['polyline']['points']);
            coordinates.addAll(points);
          }
        }
      } else if (routeData['status'] == 'FALLBACK' || routeData['status'] == 'NO_WAYPOINTS') {
        // Process fallback or no-waypoints data
        for (var leg in routeData['routes'][0]['legs']) {
          coordinates.add(LatLng(
            leg['start_location']['lat'] as double,
            leg['start_location']['lng'] as double,
          ));
          _initialTotalDistance += (leg['distance']['value'] as num).toDouble();
          _initialTotalDuration += (leg['duration']['value'] as num).toDouble();
        }
        // Add the last end_location for completeness
        final lastLeg = routeData['routes'][0]['legs'].last;
        coordinates.add(LatLng(
          lastLeg['end_location']['lat'] as double,
          lastLeg['end_location']['lng'] as double,
        ));
      }

      _fullRouteCoordinates = coordinates;

      _updateClientSideRoute(_driverPosition!);

      if (!_isInitialRouteDrawn && _driverPosition != null) {
        final destination = _dealStatus == DealStatus.accepted
            ? _pickupLocation
            : _remainingDropoffs.isNotEmpty
                ? _remainingDropoffs.first.destination
                : _allDropoffs.isNotEmpty
                    ? _allDropoffs.first.destination
                    : null;
        if (destination != null) {
          await _zoomToFitRoute(
            _driverPosition!.toLatLng(),
            destination.toLatLng(),
          );
          _isInitialRouteDrawn = true;
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch route from Firestore: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to fetch route: $e'), backgroundColor: Colors.red),
        );
      }
      rethrow; // Allow caller to handle the error
    }
  }
*/
Future<void> _getRouteFromFirestore() async {
  const maxRetries = 3;
  const retryDelay = Duration(seconds: 2);
  int attempt = 0;

  while (attempt < maxRetries) {
    try {
      // Fetch driverId safely
      final String? driverId = await Maptools().getFieldValue(
        collectionName: 'deals',
        documentId: widget.dealId,
        fieldName: 'idDriver',
      ).timeout(const Duration(seconds: 5), onTimeout: () {
        throw Exception('Timeout fetching driver ID');
      });

      if (driverId == null || driverId.isEmpty) {
        debugPrint('Driver ID missing for dealId: ${widget.dealId}');
        throw Exception('Driver ID is missing or empty');
      }

      // Fetch route document
      final doc = await FirebaseFirestore.instance
          .collection('routes')
          .doc(driverId)
          .get()
          .timeout(const Duration(seconds: 5), onTimeout: () {
        throw Exception('Timeout fetching route document');
      });

      if (!doc.exists || doc.data() == null) {
        debugPrint('Route document not found for driver: $driverId');
        throw Exception('Route document not found');
      }

      final data = doc.data()!;
      final routeData = data['routeData'] as Map<String, dynamic>?;
      if (routeData == null) {
        debugPrint('Route data missing in Firestore document for driver: $driverId');
        //_getRouteFromGoogle(allPoints);
        throw Exception('Route data missing');
      }

      // Validate route status
      final status = routeData['status'] as String?;
      if (status == null || !['OK', 'FALLBACK', 'NO_WAYPOINTS'].contains(status)) {
        debugPrint('Invalid route status: $status for driver: $driverId');
        throw Exception('Invalid route status: ${status ?? 'null'}');
      }

      // Validate routes array
      final routes = routeData['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) {
        debugPrint('No routes found in Firestore data for driver: $driverId');
        throw Exception('No routes found');
      }

      final List<LatLng> coordinates = [];
      _initialTotalDistance = 0.0;
      _initialTotalDuration = 0.0;

      // Process route data based on status
      try {
        final legs = routes[0]['legs'] as List<dynamic>? ?? [];
        if (legs.isEmpty) {
          debugPrint('No legs found in route data for driver: $driverId');
          throw Exception('No legs found in route');
        }

        if (status == 'OK') {
          // Process Google API response
          for (var leg in legs) {
            _initialTotalDistance += (leg['distance']?['value'] as num?)?.toDouble() ?? 0.0;
            _initialTotalDuration += (leg['duration']?['value'] as num?)?.toDouble() ?? 0.0;
            final steps = leg['steps'] as List<dynamic>? ?? [];
            for (var step in steps) {
              final points = step['polyline']?['points'] as String?;
              if (points != null && points.isNotEmpty) {
                try {
                  final decodedPoints = _decodeGooglePolyline(points);
                  coordinates.addAll(decodedPoints);
                } catch (e) {
                  debugPrint('Error decoding polyline for step in driver: $driverId, error: $e');
                }
              }
            }
          }
        } else if (status == 'FALLBACK' || status == 'NO_WAYPOINTS') {
          // Process fallback or no-waypoints data
          for (var leg in legs) {
            final startLat = (leg['start_location']?['lat'] as num?)?.toDouble();
            final startLng = (leg['start_location']?['lng'] as num?)?.toDouble();
            if (startLat != null && startLng != null && startLat != 0.0 && startLng != 0.0) {
              coordinates.add(LatLng(startLat, startLng));
            }
            _initialTotalDistance += (leg['distance']?['value'] as num?)?.toDouble() ?? 0.0;
            _initialTotalDuration += (leg['duration']?['value'] as num?)?.toDouble() ?? 0.0;
          }
          final lastLeg = legs.lastOrNull;
          if (lastLeg != null) {
            final endLat = (lastLeg['end_location']?['lat'] as num?)?.toDouble();
            final endLng = (lastLeg['end_location']?['lng'] as num?)?.toDouble();
            if (endLat != null && endLng != null && endLat != 0.0 && endLng != 0.0) {
              coordinates.add(LatLng(endLat, endLng));
            }
          }
        }
      } catch (e) {
        debugPrint('Error parsing route data for driver: $driverId, error: $e');
        throw Exception('Invalid route data format: $e');
      }

      if (coordinates.isEmpty) {
        debugPrint('No valid coordinates parsed for driver: $driverId');
        throw Exception('No valid coordinates in route data');
      }

      setState(() {
        _fullRouteCoordinates = coordinates;
      });

      // Update route if driver position is available
      if (_driverPosition != null) {
        _updateClientSideRoute(_driverPosition!);
      } else {
        debugPrint('Warning: _driverPosition is null, using full route coordinates');
        setState(() {
          _polylines.clear();
          _polylines.add(Polyline(
            polylineId: const PolylineId('tracking_route'),
            color: const Color.fromARGB(255, 255, 191, 0),
            points: _fullRouteCoordinates,
            width: 5,
            patterns: [PatternItem.dash(20), PatternItem.gap(10)],
          ));
        });
      }

      // Zoom to fit route if not yet drawn
      if (!_isInitialRouteDrawn && _driverPosition != null) {
        final destination = _dealStatus == DealStatus.accepted
            ? _pickupLocation
            : _remainingDropoffs.isNotEmpty
                ? _remainingDropoffs.first.destination
                : _allDropoffs.isNotEmpty
                    ? _allDropoffs.first.destination
                    : null;
        if (destination != null && destination.latitude != 0.0 && destination.longitude != 0.0) {
          await _zoomToFitRoute(
            _driverPosition!.toLatLng(),
            destination.toLatLng(),
          );
          setState(() {
            _isInitialRouteDrawn = true;
          });
        } else {
          debugPrint('Warning: Invalid or missing destination for zooming');
         // await _zoomToFitAllMarkers(); // Fallback to show all markers
        }
      }

      debugPrint('Successfully fetched and processed route from Firestore for driver: $driverId');
      return; // Success, exit retry loop
    } catch (e) {
      attempt++;
      debugPrint('Attempt $attempt failed to fetch route from Firestore: $e');
      if (attempt >= maxRetries) {
        debugPrint('Max retries reached for Firestore route fetch');
        if (mounted) {
         /*  ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(
              content: Text('Unable to load route data. Please try again later.'),
              backgroundColor: Colors.red,
            ),
          );*/
        }
        throw Exception('Failed to fetch route after $maxRetries attempts: $e');
      }
      await Future.delayed(retryDelay * (attempt + 1)); // Exponential backoff
    }
  }
}
  Future<void> _getRouteFromGoogle(List<latlong.LatLng> allPoints) async {
    if (_googleApiKey.isEmpty) throw Exception('Google API Key not configured.');

    final origin = allPoints.first;
    final destination = allPoints.last;
    final waypoints = allPoints.sublist(1, allPoints.length - 1);
    final waypointParam = waypoints.isNotEmpty
        ? '&waypoints=optimize:true|' + waypoints.map((p) => '${p.latitude},${p.longitude}').join('|')
        : '';
    final url =
        'https://maps.googleapis.com/maps/api/directions/json?origin=${origin.latitude},${origin.longitude}&destination=${destination.latitude},${destination.longitude}&key=$_googleApiKey$waypointParam';

    final response = await http.get(Uri.parse(url));
    setState(() {
      apiCalls += 1;
    });

    if (response.statusCode != 200) {
      throw Exception('Google request failed with status ${response.statusCode}');
    }

    final data = json.decode(response.body);
    if (data['status'] != 'OK' || data['routes'].isEmpty) {
      throw Exception('Google API error: ${data['error_message'] ?? data['status']}');
    }
      final cacheRef = FirebaseFirestore.instance.collection('routes').doc(_driverID);
        await cacheRef.set({
      'dealId': widget.dealId,
      'driverId': _driverID,
      'timestamp': FieldValue.serverTimestamp(),
      'routeData': data,
    });

    final List<LatLng> coordinates = [];
    _initialTotalDistance = 0;
    _initialTotalDuration = 0;
    for (var leg in data['routes'][0]['legs']) {
      _initialTotalDistance += (leg['distance']['value'] as num).toDouble();
      _initialTotalDuration += (leg['duration']['value'] as num).toDouble();
      for (var step in leg['steps']) {
        final points = _decodeGooglePolyline(step['polyline']['points']);
        coordinates.addAll(points);
      }
    }

    _fullRouteCoordinates = coordinates;

    _updateClientSideRoute(_driverPosition!);
    
    if (!_isInitialRouteDrawn && _driverPosition != null) {
      final destination = _dealStatus == DealStatus.accepted
          ? _pickupLocation
          : _remainingDropoffs.isNotEmpty
              ? _remainingDropoffs.first.destination
              : _allDropoffs.isNotEmpty
                  ? _allDropoffs.first.destination
                  : null;
      if (destination != null) {
        await _zoomToFitRoute(
          _driverPosition!.toLatLng(),
          destination.toLatLng(),
        );
        _isInitialRouteDrawn = true;
      }
    }
  }

  List<LatLng> _decodeGooglePolyline(String encoded) {
    var points = PolylinePoints().decodePolyline(encoded);
    return points.map((p) => LatLng(p.latitude, p.longitude)).toList();
  }

  void _updateClientSideRoute(latlong.LatLng driverPosition) {
    if (_fullRouteCoordinates.isEmpty) return;

    final List<LatLng> remainingRoute = [];
    double distanceTraveled = 0.0;
    double remainingDistance = 0.0;
    
    double minDistanceToSegment = double.infinity;
    int nearestSegmentIndex = -1;
    latlong.LatLng? nearestPointOnSegment;

    for (int i = 0; i < _fullRouteCoordinates.length - 1; i++) {
      final p1 = _fullRouteCoordinates[i];
      final p2 = _fullRouteCoordinates[i + 1];

      final distToSegment = _distanceToLineSegment(
        latlong.LatLng(p1.latitude, p1.longitude),
        latlong.LatLng(p2.latitude, p2.longitude),
        driverPosition,
      );

      if (distToSegment.distance < minDistanceToSegment) {
        minDistanceToSegment = distToSegment.distance;
        nearestSegmentIndex = i;
        nearestPointOnSegment = distToSegment.projection;
      }
    }

    if (nearestSegmentIndex != -1) {
      for (int i = 0; i < nearestSegmentIndex; i++) {
        distanceTraveled += Geolocator.distanceBetween(
          _fullRouteCoordinates[i].latitude,
          _fullRouteCoordinates[i].longitude,
          _fullRouteCoordinates[i + 1].latitude,
          _fullRouteCoordinates[i + 1].longitude,
        );
      }
      distanceTraveled += Geolocator.distanceBetween(
        _fullRouteCoordinates[nearestSegmentIndex].latitude,
        _fullRouteCoordinates[nearestSegmentIndex].longitude,
        nearestPointOnSegment!.latitude,
        nearestPointOnSegment.longitude,
      );

      remainingRoute.add(nearestPointOnSegment.toLatLng());
      for (int i = nearestSegmentIndex + 1; i < _fullRouteCoordinates.length; i++) {
        remainingRoute.add(_fullRouteCoordinates[i]);
      }

      remainingDistance = _initialTotalDistance - distanceTraveled;
    }
    
    setState(() {
      _polylines.clear();
      _polylines.add(Polyline(
        polylineId: const PolylineId('tracking_route'),
        color: const Color.fromARGB(255, 255, 191, 0),
        points: remainingRoute.isNotEmpty ? remainingRoute : _fullRouteCoordinates,
        width: 5,
        patterns: [PatternItem.dash(20), PatternItem.gap(10)],
      ));
      _distanceRemaining.value = _formatDistance(remainingDistance > 0 ? remainingDistance : 0.0);
      _timeRemaining.value = _formatDuration(_initialTotalDuration * (remainingDistance / _initialTotalDistance));
    });
  }

  bool _isOffRoute(latlong.LatLng driverPosition) {
    if (_fullRouteCoordinates.isEmpty) return false;
    double minDistance = double.infinity;

    for (int i = 0; i < _fullRouteCoordinates.length - 1; i++) {
      final dist = _distanceToLineSegment(
        latlong.LatLng(_fullRouteCoordinates[i].latitude, _fullRouteCoordinates[i].longitude),
        latlong.LatLng(_fullRouteCoordinates[i + 1].latitude, _fullRouteCoordinates[i + 1].longitude),
        driverPosition,
      );
      if (dist.distance < minDistance) {
        minDistance = dist.distance;
      }
    }
    return minDistance > _offRouteThresholdMeters;
  }

  _DistanceToSegmentResult _distanceToLineSegment(latlong.LatLng start, latlong.LatLng end, latlong.LatLng point) {
    final lat1 = start.latitude, lon1 = start.longitude;
    final lat2 = end.latitude, lon2 = end.longitude;
    final latP = point.latitude, lonP = point.longitude;

    final dx = lat2 - lat1;
    final dy = lon2 - lon1;
    final squaredLength = dx * dx + dy * dy;

    double t = 0.0;
    if (squaredLength > 0) {
      t = ((latP - lat1) * dx + (lonP - lon1) * dy) / squaredLength;
      t = t.clamp(0.0, 1.0);
    }

    final projectedLat = lat1 + t * dx;
    final projectedLon = lon1 + t * dy;
    final projectedPoint = latlong.LatLng(projectedLat, projectedLon);

    final distance = Geolocator.distanceBetween(latP, lonP, projectedLat, projectedLon);
    return _DistanceToSegmentResult(distance, projectedPoint);
  }

  Future<void> _zoomToFitRoute(LatLng point1, LatLng point2) async {
    try {
      final controller = await _mapController.future;
      final bounds = LatLngBounds(
        southwest: LatLng(
          point1.latitude < point2.latitude ? point1.latitude : point2.latitude,
          point1.longitude < point2.longitude ? point1.longitude : point2.longitude,
        ),
        northeast: LatLng(
          point1.latitude > point2.latitude ? point1.latitude : point2.latitude,
          point1.longitude > point2.longitude ? point1.longitude : point2.longitude,
        ),
      );
      final padding = MediaQuery.of(context).size.width * 0.15;
      await controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, padding));
    } catch (e) {
      debugPrint('Error zooming camera: $e');
    }
  }

  Future<void> _recenterOnDriver() async {
    if (_driverPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Driver location unavailable.'), backgroundColor: Colors.red),
      );
      return;
    }
    try {
      final controller = await _mapController.future;
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: _driverPosition!.toLatLng(), zoom: _driverFocusZoomLevel, tilt: 30.0),
        ),
      );
    } catch (e) {
      debugPrint('Error centering on driver: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to center on driver: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handleCancellation() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Cancellation'),
        content: const Text('Are you sure you want to cancel this delivery?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No', style: TextStyle(fontSize: 16, color: Colors.grey)),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: const BorderSide(color: Colors.redAccent, width: 2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Yes, Cancel', style: TextStyle(fontSize: 16, color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await _updateDealStatus('canceled');
    }
  }

  Future<void> _updateDealStatus(String newStatus) async {
    try {
      await FirebaseFirestore.instance.collection('deals').doc(widget.dealId).update({'status': newStatus});
      debugPrint('Deal status updated to: $newStatus');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Delivery $newStatus successfully.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint('Failed to update deal status: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update status: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showRatingDialog() {
    if (_driverID == null) {
      debugPrint('Cannot show rating dialog: driverID is null');
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => RatingPopupWidget(
        userIdToRate: _driverID!,
      ),
    );
  }

  void _addStaticMarkers() {
    if (_pickupLocation == null || _order == null) {
      debugPrint('Cannot add markers: pickupLocation or order is null');
      return;
    }
    setState(() {
      _markers.removeWhere((m) => m.markerId.value != 'driver');
      _markers.add(Marker(
        markerId: const MarkerId('pickup'),
        position: _pickupLocation!.toLatLng(),
        icon: _pickupIcon,
        infoWindow: InfoWindow(title: _order!.namePickUp),
      ));

      for (int i = 0; i < _allDropoffs.length; i++) {
        final dropOff = _allDropoffs[i];
    final l10n = AppLocalizations.of(context)!;

        _markers.add(Marker(
          markerId: MarkerId('dropoff_$i'),
          position: dropOff.destination.toLatLng(),
          icon: dropOff.isDelivered == true ? _deliveredStopIcon : _undeliveredStopIcon,
          infoWindow: InfoWindow(
            title: dropOff.destinationName,
            snippet: dropOff.isDelivered == true ? l10n.deliveredSuccessfully : dropOff.isDelivered == false? l10n.notDelivered : l10n.deliveryCanceled,
          ),
        ));

   
      }
      _markersNotifier.value = Set.of(_markers);
      debugPrint('Added ${_markers.length} static markers (pickup + ${_allDropoffs.length} stops)');
    });
  }

  void _updateDriverMarker() {
    if (_driverPosition == null) {
      debugPrint('Cannot update driver marker: driverPosition is null');
      return;
    }
    setState(() {
      _markers.removeWhere((m) => m.markerId.value == 'driver');
      _markers.add(Marker(
        markerId: const MarkerId('driver'),
        position: _driverPosition!.toLatLng(),
        icon: _driverIcon,
        anchor: const Offset(0.5, 0.5),
      ));
      _circles.clear();
      _circles.add(Circle(
        circleId: const CircleId('driver_mask'),
        center: _driverPosition!.toLatLng(),
        radius: 10,
        fillColor: const Color.fromARGB(100, 255, 191, 0),
        strokeWidth: 0,
      ));
      _markersNotifier.value = Set.of(_markers);
      _circlesNotifier.value = Set.of(_circles);
      debugPrint('Driver marker updated at: $_driverPosition');
    });
  }

  Future<void> _loadCustomMarkerIcons() async {
    if (_cachedDriverIcon != null &&
        _cachedPickupIcon != null &&
        _cachedUndeliveredStopIcon != null &&
        _cachedDeliveredStopIcon != null) {
      setState(() {
        _driverIcon = _cachedDriverIcon!;
        _pickupIcon = _cachedPickupIcon!;
        _undeliveredStopIcon = _cachedUndeliveredStopIcon!;
        _deliveredStopIcon = _cachedDeliveredStopIcon!;
      });
      debugPrint('Using cached marker icons');
      return;
    }

    try {
      // Load driver icon
      final driverData = await rootBundle.load('assets/delivery_boy.png');
      final driverBytes = driverData.buffer.asUint8List();
      _cachedDriverIcon = await BitmapDescriptor.fromBytes(driverBytes);

      // Load pickup icon (green pin)
      _cachedPickupIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);

      // Load undelivered stop icon (red pin)
      _cachedUndeliveredStopIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);

      // Load delivered stop icon (blue pin)
      _cachedDeliveredStopIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);

      if (mounted) {
        setState(() {
          _driverIcon = _cachedDriverIcon!;
          _pickupIcon = _cachedPickupIcon!;
          _undeliveredStopIcon = _cachedUndeliveredStopIcon!;
          _deliveredStopIcon = _cachedDeliveredStopIcon!;
        });
        debugPrint('Custom marker icons loaded');
      }
    } catch (e) {
      debugPrint('Error loading custom marker icons: $e');
      if (mounted) {
        setState(() {
          _driverIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);
          _pickupIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
          _undeliveredStopIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
          _deliveredStopIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
        });
      }
    }
  }

  Future<void> _launchPhoneCall(String? phoneNumber) async {
    if (phoneNumber == null || phoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No valid phone number available.')),
      );
      return;
    }
    final Uri telUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(telUri)) {
      await launchUrl(telUri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not launch phone call.')),
      );
    }
  }

  DealStatus _parseDealStatus(String? status) {
    if (status == null || status.trim().isEmpty) {
      debugPrint('Warning: Deal status is null or empty for dealId: ${widget.dealId}');
      return DealStatus.accepted;
    }

    final normalizedStatus = status.trim().toLowerCase();
    switch (normalizedStatus) {
      case 'accepted':
        return DealStatus.accepted;
      case 'almost':
        return DealStatus.almost;
      case 'terminated':
        return DealStatus.terminated;
      case 'canceled':
        return DealStatus.canceled;
      default:
        debugPrint('Warning: Unrecognized deal status "$normalizedStatus" for dealId: ${widget.dealId}');
        return DealStatus.accepted;
    }
  }

  String _formatDistance(double meters) => meters < 1000 ? '${meters.toInt()} m' : '${(meters / 1000).toStringAsFixed(1)} km';
  String _formatDuration(double seconds) {
    final minutes = (seconds / 60).ceil();
    return minutes < 60 ? '$minutes min' : '${minutes ~/ 60} h ${minutes % 60} min';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(36.7315, 10.2525),
              zoom: 10.0,
            ),
            onMapCreated: (controller) {
              _mapController.complete(controller);
              debugPrint('Map created');
            },
            markers: _markersNotifier.value,
            polylines: _polylines,
            circles: _circlesNotifier.value,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            compassEnabled: false,
            zoomControlsEnabled: false,
            padding: const EdgeInsets.only(
              top: 16,
              bottom: 80,
              left: 16,
              right: 16,
            ),
          ),
          if (_screenState == ScreenState.loading)
            const Center(child: RotatingDotsIndicator()),
          if (_screenState == ScreenState.error)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage ?? 'Failed to load delivery details: Unknown Error',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _initializeScreen,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color.fromARGB(255, 255, 191, 0),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          if (_screenState == ScreenState.ready) ...[
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              right: 16,
              child: Column(
                children: [
                  FloatingActionButton.small(
                    heroTag: 'recenter_btn',
                    onPressed: _recenterOnDriver,
                    backgroundColor: Colors.white,
                    child: const Icon(Icons.my_location, color: Colors.black54),
                  ),
                  const SizedBox(height: 8),
                  if(widget.watcher)
                  FloatingActionButton.small(
                    heroTag: 'call_driver_btn',
                    onPressed: () => _launchPhoneCall(_driverPhone),
                    backgroundColor: _driverPhone != null ? Colors.white : Colors.grey,
                    child: Icon(Icons.phone, color: _driverPhone != null ? Colors.blue : Colors.black26),
                  ),
                  if(widget.watcher)
                  FloatingActionButton.small(
                    heroTag: 'api_calls_btn',
                    onPressed: () => _launchPhoneCall(_driverPhone),
                    backgroundColor: _driverPhone != null ? Colors.white : Colors.grey,
                    child: Text("$apiCalls"),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: _buildIconBar(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildIconBar() {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;


    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fire_truck, color: colorScheme.primary, size: 24),
              const SizedBox(height: 4),
              ValueListenableBuilder<String>(
                valueListenable: _distanceRemaining,
                builder: (context, value, child) => Text(
                  value,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.access_time_filled, color: colorScheme.primary, size: 24),
              const SizedBox(height: 4),
              ValueListenableBuilder<String>(
                valueListenable: _timeRemaining,
                builder: (context, value, child) => Text(
                  value,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          if(widget.watcher)
          GestureDetector(
            onTap: _handleCancellation,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cancel, color: Colors.red, size: 24),
                const SizedBox(height: 4),
                Text(
                  l10n.cancel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension LatLngConverter on latlong.LatLng {
  LatLng toLatLng() {
    return LatLng(latitude, longitude);
  }
}

class _DistanceToSegmentResult {
  final double distance;
  final latlong.LatLng projection;
  _DistanceToSegmentResult(this.distance, this.projection);
}