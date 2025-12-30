import 'dart:async';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:permission_handler/permission_handler.dart';
import 'package:shnell/calls/CallService.dart';
import 'package:shnell/calls/VoiceCall.dart';
import 'package:shnell/dots.dart';
import 'package:shnell/model/destinationdata.dart';
import 'package:shnell/model/oredrs.dart';
import 'package:shnell/ratingsScreen.dart';
import 'package:shnell/model/users.dart';
import 'package:shnell/model/calls.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
// --- Localization Import ---
import 'package:flutter_gen/gen_l10n/app_localizations.dart'; 

// --- Helper Models & Enums ---
class RouteInfo {
  final List<LatLng> points;
  final int durationSeconds; 
  final double distanceMeters;
  
  RouteInfo(this.points, this.durationSeconds, this.distanceMeters);
}

enum ScreenState { loading, ready, error }
enum DealStatus { accepted, almost, terminated, canceled }

class Deoaklna extends StatefulWidget {
  final String dealId;
  final bool watcher;
  const Deoaklna({super.key, required this.dealId, this.watcher = true});

  @override
  State<Deoaklna> createState() => _DeliveryTrackingTabState();
}

class _DeliveryTrackingTabState extends State<Deoaklna> with AutomaticKeepAliveClientMixin {
  // Configuration Constants
  static const Duration _fetchTimeout = Duration(seconds: 15);
  static const String googleDirectionsApiKey = 'YOUR_GOOGLE_API_KEY_HERE'; 

  // State Variables
  final Completer<GoogleMapController> _mapController = Completer();
  final Set<Circle> _circles = {};
  final ValueNotifier<Set<Marker>> _markersNotifier = ValueNotifier({});
  final ValueNotifier<Set<Circle>> _circlesNotifier = ValueNotifier({});
  final ValueNotifier<Set<Polyline>> _polylinesNotifier = ValueNotifier({});
  
  ScreenState _screenState = ScreenState.loading;
  String? _errorMessage;
  
  Orders? _order;
  latlong.LatLng? _pickupLocation;
  List<DropOffData> _allDropoffs = [];
  List<DropOffData> _remainingDropoffs = [];
  List<String> _stopIds = [];
  
  // Driver Details
  String? _driverID;
  String? _driverName;
  String? _orderId;
  latlong.LatLng? _driverPosition;
  
  // Marker Icons
  BitmapDescriptor _driverIcon = BitmapDescriptor.defaultMarker;
  BitmapDescriptor _pickupIcon = BitmapDescriptor.defaultMarker;
  BitmapDescriptor _undeliveredStopIcon = BitmapDescriptor.defaultMarker;
  BitmapDescriptor _deliveredStopIcon = BitmapDescriptor.defaultMarker;
  
  DealStatus _dealStatus = DealStatus.accepted;
  bool _isCallLoading = false; 

  // --- ETA Variables (Raw Data for Localization) ---
  int? _etaSecondsRemaining; // Changed from String to Int for cleaner L10n
  double? _baselineTotalDist; 
  int? _baselineTotalSeconds; 
  latlong.LatLng? _currentTarget; 

  // Subscriptions
  StreamSubscription? _dealStatusSubscription;
  StreamSubscription? _orderSubscription;
  StreamSubscription? _driverLocationSubscription;
  StreamSubscription? _stopsSubscription;

  List<List<LatLng>> _routeSegments = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadCustomMarkerIcons(); 
    _initializeScreen();
  }

  @override
  void dispose() {
    _driverLocationSubscription?.cancel();
    _dealStatusSubscription?.cancel();
    _orderSubscription?.cancel();
    _stopsSubscription?.cancel();
    _markersNotifier.dispose();
    _circlesNotifier.dispose();
    _polylinesNotifier.dispose();
    _mapController.future.then((controller) => controller.dispose());
    super.dispose();
  }

  // --- 1. ROUTING API ---

  Future<RouteInfo> _fetchRoute(LatLng start, LatLng end) async {
    final fallback = RouteInfo([start, end], 0, 0);

    try {
      // OSRM
      final osrmUrl = 'http://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=polyline';
      final response = await http.get(Uri.parse(osrmUrl));
      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        if (jsonResponse['routes'] != null && jsonResponse['routes'].isNotEmpty) {
          final route = jsonResponse['routes'][0];
          return RouteInfo(
            _decodePolyline(route['geometry']), 
            (route['duration'] as num).toInt(), 
            (route['distance'] as num).toDouble()
          );
        }
      }
    } catch (e) {
      debugPrint('OSRM failed: $e');
    }

    // Google Fallback
    try {
      final googleUrl = 'https://maps.googleapis.com/maps/api/directions/json?origin=${start.latitude},${start.longitude}&destination=${end.latitude},${end.longitude}&key=$googleDirectionsApiKey';
      final response = await http.get(Uri.parse(googleUrl));
      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        if (jsonResponse['routes'] != null && jsonResponse['routes'].isNotEmpty) {
          final route = jsonResponse['routes'][0];
          int duration = 0;
          double distance = 0;
          if (route['legs'] != null && route['legs'].isNotEmpty) {
             duration = (route['legs'][0]['duration']['value'] as num).toInt();
             distance = (route['legs'][0]['distance']['value'] as num).toDouble();
          }
          return RouteInfo(
            _decodePolyline(route['overview_polyline']['points']), 
            duration, 
            distance
          );
        }
      }
    } catch (e) {
      debugPrint('Google Directions failed: $e');
    }

    return fallback;
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> poly = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;
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
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;
      poly.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return poly;
  }

  // --- 2. ZERO-COST ETA MATH ---

  Future<void> _establishEtaBaseline(latlong.LatLng driverPos) async {
    if (_currentTarget == null || _baselineTotalSeconds != null) return; 

    final routeInfo = await _fetchRoute(
      LatLng(driverPos.latitude, driverPos.longitude), 
      LatLng(_currentTarget!.latitude, _currentTarget!.longitude)
    );

    if (mounted) {
      setState(() {
        _baselineTotalSeconds = routeInfo.durationSeconds;
        _baselineTotalDist = routeInfo.distanceMeters;
        _etaSecondsRemaining = routeInfo.durationSeconds; // Init
      });
    }
  }

  void _updateLiveEtaLocally(latlong.LatLng driverPos) {
    if (_baselineTotalSeconds == null) {
      _establishEtaBaseline(driverPos);
      return;
    }

    if (_baselineTotalDist == null || _currentTarget == null) return;

    final double distRemaining = const latlong.Distance().as(
      latlong.LengthUnit.Meter, driverPos, _currentTarget!
    );

    if (_baselineTotalDist == 0) return;

    double ratio = distRemaining / _baselineTotalDist!;
    if (ratio > 1.1) ratio = 1.1; 
    if (ratio < 0.0) ratio = 0.0;

    // Just update the integer seconds, don't format string here
    setState(() {
      _etaSecondsRemaining = (_baselineTotalSeconds! * ratio).round();
    });
  }

  // --- 3. INITIALIZATION ---

  Future<void> _initializeScreen() async {
    if (widget.dealId.isEmpty) {
      _setError('Invalid deal ID'); // This is internal error, not shown to user usually
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _setError('User not authenticated');
      return;
    }

    setState(() => _screenState = ScreenState.loading);

    try {
      await _fetchInitialData().timeout(_fetchTimeout);
      
      _listenToDealStatus();
      _listenToOrderUpdates();
      _listenToDriverLocation();
      _listenToStopsUpdates();
      
      setState(() {
        _screenState = ScreenState.ready;
        _errorMessage = null;
      });
    } catch (e) {
      _setError(e.toString());
    }
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _screenState = ScreenState.error;
      _errorMessage = message;
      _dealStatus = DealStatus.accepted;
    });
  }

  Future<void> _fetchInitialData() async {
    final dealDoc = await FirebaseFirestore.instance.collection('deals').doc(widget.dealId).get();
    if (!dealDoc.exists || dealDoc.data() == null) throw Exception('Deal not found');

    final dealData = dealDoc.data()!;
    _driverID = dealData['idDriver'] as String?;
    _orderId = dealData['idOrder'] as String?;
    
    if (_driverID == null) throw Exception('Waiting for driver assignment...');
    if (_orderId == null) throw Exception('Order ID missing');

    final orderDoc = await FirebaseFirestore.instance.collection('orders').doc(_orderId).get();
    if (!orderDoc.exists) throw Exception('Order not found');

    await _fetchDriverDetails();

    final order = Orders.fromFirestore(orderDoc);
    final stopIds = order.stops.where((id) => id.isNotEmpty).toList();
    
    final List<DropOffData> stopData = [];
    for (final stopId in stopIds) {
      final stopDoc = await FirebaseFirestore.instance.collection('stops').doc(stopId).get();
      if (stopDoc.exists) {
        stopData.add(_dropOffFromFirestore(stopDoc));
      }
    }

    final List<LatLng> routePoints = [];
    routePoints.add(order.pickUpLocation.toLatLng());
    for (final dropOff in stopData) {
      routePoints.add(dropOff.destination.toLatLng());
    }

    _routeSegments = [];
    if (routePoints.length >= 2) {
      for (int i = 0; i < routePoints.length - 1; i++) {
        final routeInfo = await _fetchRoute(routePoints[i], routePoints[i + 1]);
        _routeSegments.add(routeInfo.points);
      }
    }

    if (mounted) {
      setState(() {
        _order = order;
        _pickupLocation = order.pickUpLocation;
        _currentTarget = _pickupLocation; 
        _stopIds = stopIds;
        _allDropoffs = stopData;
        _remainingDropoffs = stopData.where((dropOff) => dropOff.isDelivered != true).toList();
        _dealStatus = _parseDealStatus(dealData['status'] as String?);
        _updateMarkers();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _zoomToFitAll());
    }
  }

  Future<void> _fetchDriverDetails() async {
    if (_driverID == null) return;
    try {
      final driverDoc = await FirebaseFirestore.instance.collection('users').doc(_driverID).get();
      if (driverDoc.exists && driverDoc.data() != null) {
        final driverData = shnellUsers.fromJson(driverDoc.data()!);
        if (mounted) {
          setState(() {
            _driverName = driverData.name;
          });
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch driver details: $e');
    }
  }

  // --- Listeners ---

  void _listenToDealStatus() {
    _dealStatusSubscription = FirebaseFirestore.instance
        .collection('deals')
        .doc(widget.dealId)
        .snapshots()
        .listen((snapshot) {
      if (!mounted || !snapshot.exists) return;
      final status = _parseDealStatus(snapshot.data()!['status'] as String?);
      if (_dealStatus == status) return;
      setState(() {
        _dealStatus = status;
        _updateMarkers();
      });
      if (status == DealStatus.terminated) {
        _showRatingDialog();
      } else if (status == DealStatus.canceled) {
        _showCancellationMessage();
      }
    });
  }

  void _listenToOrderUpdates() {
    if (_orderId == null) return;
    _orderSubscription = FirebaseFirestore.instance
        .collection('orders')
        .doc(_orderId)
        .snapshots()
        .listen((snapshot) {
       // Just tracking basic updates for now. 
       // Logic to switch Target/ETA is handled implicitly by dealStatus logic in build 
    });
  }

  void _listenToStopsUpdates() {
    if (_stopIds.isEmpty) return;
    _stopsSubscription = FirebaseFirestore.instance
        .collection('stops')
        .where(FieldPath.documentId, whereIn: _stopIds)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      final newStopData = snapshot.docs.map((doc) => _dropOffFromFirestore(doc)).toList();
      setState(() {
        _allDropoffs = newStopData;
        _remainingDropoffs = newStopData.where((d) => d.isDelivered != true).toList();
        _updateMarkers();
      });
    });
  }

  void _listenToDriverLocation() {
    if (_driverID == null) return;
    _driverLocationSubscription = FirebaseDatabase.instance
        .ref('locations/$_driverID/coordinates')
        .onValue
        .listen((event) {
      if (!mounted || !event.snapshot.exists || event.snapshot.value == null) return;

      final data = event.snapshot.value as List;
      final newPosition = latlong.LatLng(data[1] as double, data[0] as double);

      _updateLiveEtaLocally(newPosition);

      setState(() {
        _driverPosition = newPosition;
        _updateMarkers();
      });
    });
  }

  // --- Map & Markers ---

  void _updateMarkers() {
    if (!mounted) return;
    final Set<Marker> newMarkers = {};
    final Set<Polyline> newPolylines = {};
    final colorScheme = Theme.of(context).colorScheme;
    final loc = AppLocalizations.of(context)!; // Localization Access

    // Pickup
    if (_pickupLocation != null && _order != null) {
      newMarkers.add(Marker(
        markerId: const MarkerId('pickup'),
        position: _pickupLocation!.toLatLng(),
        icon: _pickupIcon,
        // LOCALIZED
        infoWindow: InfoWindow(title: loc.pickupTitle(_order!.namePickUp)),
      ));
    }

    // Dropoffs
    for (int i = 0; i < _allDropoffs.length; i++) {
      final dropOff = _allDropoffs[i];
      newMarkers.add(Marker(
        markerId: MarkerId('dropoff_$i'),
        position: dropOff.destination.toLatLng(),
        icon: dropOff.isDelivered ? _deliveredStopIcon : _undeliveredStopIcon,
        infoWindow: InfoWindow(title: dropOff.destinationName),
      ));
    }

    // Polylines
    for (int i = 0; i < _routeSegments.length; i++) {
      final bool isSegmentDelivered = i < _allDropoffs.length && _allDropoffs[i].isDelivered;
      newPolylines.add(Polyline(
        polylineId: PolylineId('route_segment_$i'),
        points: _routeSegments[i],
        width: 6,
        color: isSegmentDelivered
            ? colorScheme.primary 
            : colorScheme.outline.withOpacity(0.7), 
        patterns: isSegmentDelivered
            ? [] 
            : [PatternItem.dot], 
        zIndex: 1,
      ));
    }

    // Driver
    if (_driverPosition != null) {
      newMarkers.add(Marker(
        markerId: const MarkerId('driver'),
        position: _driverPosition!.toLatLng(),
        icon: _driverIcon,
        anchor: const Offset(0.5, 0.5),
        zIndex: 3,
      ));

      _circles.clear();
      _circles.add(Circle(
        circleId: const CircleId('driver_aura'),
        center: _driverPosition!.toLatLng(),
        radius: 30,
        fillColor: colorScheme.primary.withOpacity(0.15),
        strokeColor: colorScheme.primary.withOpacity(0.4),
        strokeWidth: 1,
      ));
      _circlesNotifier.value = Set.from(_circles);
    }

    _markersNotifier.value = newMarkers;
    _polylinesNotifier.value = newPolylines;
  }  
  
  Future<void> _zoomToFitAll() async {
    if (_driverPosition == null && _pickupLocation == null) return;
    try {
      final controller = await _mapController.future;
      double minLat = 90.0, maxLat = -90.0, minLng = 180.0, maxLng = -180.0;
      final List<latlong.LatLng> points = [
        if (_driverPosition != null) _driverPosition!,
        if (_pickupLocation != null) _pickupLocation!,
        ..._remainingDropoffs.map((s) => s.destination)
      ];

      if (points.isEmpty) return;

      for (var p in points) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
      await controller.animateCamera(CameraUpdate.newLatLngBounds(
        LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng)),
        100.0,
      ));
    } catch (e) {
      debugPrint("Zoom error: $e");
    }
  }

  // --- ACTIONS ---

Future<bool> _checkCallPermissions(BuildContext context) async {

  final status = await Permission.microphone.status;

  if (status.isGranted) {
    return true;
  }

  final result = await Permission.microphone.request();

  if (result.isGranted) {
    return true;
  }

  if (result.isPermanentlyDenied) {
    if (context.mounted) {
      await openAppSettings();
    }
  }

  return false;
}

  Future<void> _initiateInAppCall() async {
    if (_driverID == null || _isCallLoading) return;
    final hasPermission = await _checkCallPermissions(context);
  if (!hasPermission) return;
    setState(() => _isCallLoading = true);
    
    final loc = AppLocalizations.of(context)!;

    try {
      final call = Call(
        callId: widget.dealId,
        dealId: widget.dealId,
        driverId: _driverID!,
        userId:  FirebaseAuth.instance.currentUser!.uid,
        callerId: FirebaseAuth.instance.currentUser!.uid,
        receiverId: _driverID!, 
        callStatus: 'dialing',
        agoraChannel: widget.dealId, 
        agoraToken: '',
        hasVideo: false,
        timestamp: DateTime.now(),
      );
      final isproceed =  await CallService().makeCall(call: call);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => VoiceCallScreen(call: call , isCaller: true,),
        ),
      );
      

      if (isproceed == false) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc.callInitiationFailed)),
          );
        }
        return;
      }
    } catch (e) {
       // Handle error
    } finally {
      if (mounted) setState(() => _isCallLoading = false);
    }
  }

  Future<void> _loadCustomMarkerIcons() async {
    try {
      _driverIcon = await _loadCustomMarker('delivery_boy' , 64);
      _pickupIcon = await _loadCustomMarker('custom' , 96);
      _undeliveredStopIcon = await _loadCustomMarker('pin' , 64);
      _deliveredStopIcon = await _loadCustomMarker('check' , 64);
      setState(() {});
    } catch(e) {
      debugPrint("Asset error: $e");
    }
  }

  Future<BitmapDescriptor> _loadCustomMarker(String path , int width) async {
    final imageBytes = (await rootBundle.load('assets/$path.png')).buffer.asUint8List();
    final codec = await instantiateImageCodec(imageBytes, targetWidth: width);
    final frameInfo = await codec.getNextFrame();
    final imageData = await frameInfo.image.toByteData(format: ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(imageData!.buffer.asUint8List());
  }

  DealStatus _parseDealStatus(String? status) {
    if (status == null) return DealStatus.accepted;
    switch (status.trim().toLowerCase()) {
      case 'accepted': return DealStatus.accepted;
      case 'almost': return DealStatus.almost;
      case 'terminated': return DealStatus.terminated;
      case 'canceled': return DealStatus.canceled;
      default: return DealStatus.accepted;
    }
  }

  void _showCancellationMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.deliveryCanceled), 
        backgroundColor: Theme.of(context).colorScheme.error
      ),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _showRatingDialog() {
    if (_driverID != null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => RatingPopupWidget(driverRated: _driverID!, userIdToRate: FirebaseAuth.instance.currentUser!.uid,),
      );
    }
  }

  DropOffData _dropOffFromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    // Localization of 'Unknown Stop' handled in build() logic if needed, 
    // or pass through if it's user input data.
    return DropOffData(
      destination: latlong.LatLng(
        (data['destination']?['latitude'] as num?)?.toDouble() ?? 0.0,
        (data['destination']?['longitude'] as num?)?.toDouble() ?? 0.0,
      ),
      destinationName: data['destinationName'] as String? ?? 'Unknown',
      isDelivered: data['isdelivered'] as bool? ?? false,
    );
  }

  // --- BUILD ---

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    // Localizations
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Stack(
        children: [
          // 1. Google Map
          GoogleMap(
            initialCameraPosition: const CameraPosition(target: LatLng(36.8065, 10.1815), zoom: 10.0),
            onMapCreated: (controller) => _mapController.complete(controller),
            markers: _markersNotifier.value,
            circles: _circlesNotifier.value,
            polylines: _polylinesNotifier.value,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),

          // 2. Loading State
          if (_screenState == ScreenState.loading)
            const Center(child: RotatingDotsIndicator()),
            
          // 3. Error State
          if (_screenState == ScreenState.error)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 48, color: colorScheme.error),
                  const SizedBox(height: 16),
                  Text(_errorMessage ?? loc.errorLabel, style: TextStyle(color: colorScheme.onSurface)),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: _initializeScreen, child: Text(loc.retryButton)),
                ],
              ),
            ),

          // 4. Driver Card with Localized ETA
          if (_screenState == ScreenState.ready && widget.watcher)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.shadow.withOpacity(0.2),
                        blurRadius: 24,
                        offset: const Offset(0, -6),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 32,
                            backgroundColor: colorScheme.primaryContainer,
                            child: Image.asset("assets/${_order?.vehicleType}.png"),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _driverName ?? loc.driverTitle,
                                  style: textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                
                                // --- LOCALIZED ETA BADGE ---
                                if (_dealStatus == DealStatus.accepted) ...[
                                  // Phase: Picking up (Green)
                                  Builder(builder: (context) {
                                    String timeString = "--";
                                    if (_etaSecondsRemaining != null) {
                                      if (_etaSecondsRemaining! < 60) {
                                        timeString = loc.lessThanOneMin;
                                      } else {
                                        final min = (_etaSecondsRemaining! / 60).ceil().toString();
                                        timeString = loc.minutesShort(min);
                                      }
                                    }
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade100,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        loc.pickupIn(timeString), // "Pickup in 15 min"
                                        style: textTheme.labelSmall?.copyWith(
                                          color: Colors.green.shade800,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    );
                                  }),
                                ] else ...[
                                  // Phase: In Transit (Blue)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade100,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      loc.inTransit,
                                      style: textTheme.labelSmall?.copyWith(
                                        color: Colors.blue.shade800,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ]
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          if (_driverID != null)
                            FloatingActionButton(
                              onPressed: _isCallLoading ? (){} : _initiateInAppCall,
                              backgroundColor: colorScheme.primary,
                              foregroundColor: colorScheme.onPrimary,
                              elevation: 6,
                              child: _isCallLoading
                                  ? const SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    )
                                  : const Icon(Icons.call_rounded, size: 32),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _order?.price != null
                                ? loc.totalPrice(_order!.price.toStringAsFixed(2))
                                : loc.totalPriceEmpty,
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          // Cancellation Fee (Only show in early stages)
                          if (_dealStatus == DealStatus.accepted)
                            Text(
                              loc.cancellationFeeWarning(
                                (_order?.price != null ? _order!.price * 0.10 : 0).toStringAsFixed(2)
                              ),
                              style: textTheme.bodySmall?.copyWith(
                                color: colorScheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

extension LatLngConverter on latlong.LatLng {
  LatLng toLatLng() => LatLng(latitude, longitude);
}