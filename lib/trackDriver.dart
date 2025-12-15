import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:shnell/calls/VoiceCall.dart';
import 'package:shnell/calls/CallService.dart';
import 'package:shnell/dots.dart'; 
import 'package:shnell/model/destinationdata.dart';
import 'package:shnell/model/oredrs.dart';
import 'package:shnell/ratingsScreen.dart';
import 'package:shnell/model/users.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

// --- CALL FEATURE IMPORTS ---
import 'package:shnell/model/calls.dart';

// --- Helper Models & Enums ---
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

  // State Variables
  final Completer<GoogleMapController> _mapController = Completer();
  final Set<Circle> _circles = {};
  final ValueNotifier<Set<Marker>> _markersNotifier = ValueNotifier({});
  final ValueNotifier<Set<Circle>> _circlesNotifier = ValueNotifier({});
  
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
  bool _isCallLoading = false; // Controls the spinner on the call button

  // Subscriptions
  StreamSubscription? _dealStatusSubscription;
  StreamSubscription? _orderSubscription;
  StreamSubscription? _driverLocationSubscription;
  StreamSubscription? _stopsSubscription;

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
    _mapController.future.then((controller) => controller.dispose());
    super.dispose();
  }

  // --- Helper Methods ---

  DropOffData _dropOffFromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
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

  // --- Initialization ---

  Future<void> _initializeScreen() async {
    if (widget.dealId.isEmpty) {
      _setError('Invalid deal ID');
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
    debugPrint('Error: $message');
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

    // Fetch Full Driver Details
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

    if (mounted) {
      setState(() {
        _order = order;
        _pickupLocation = order.pickUpLocation;
        _stopIds = stopIds;
        _allDropoffs = stopData;
        _remainingDropoffs = stopData.where((dropOff) => dropOff.isDelivered != true).toList();
        _dealStatus = _parseDealStatus(dealData['status'] as String?);
        _updateMarkers();
      });
      // Initial zoom
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
      // Handle updates if needed
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
    final colorScheme = Theme.of(context).colorScheme;

    if (_pickupLocation != null && _order != null) {
      newMarkers.add(Marker(
        markerId: const MarkerId('pickup'),
        position: _pickupLocation!.toLatLng(),
        icon: _pickupIcon,
        infoWindow: InfoWindow(title: "Pickup: ${_order!.namePickUp}"),
      ));
    }

    for (int i = 0; i < _allDropoffs.length; i++) {
      final dropOff = _allDropoffs[i];
      newMarkers.add(Marker(
        markerId: MarkerId('dropoff_$i'),
        position: dropOff.destination.toLatLng(),
        icon: dropOff.isDelivered == true ? _deliveredStopIcon : _undeliveredStopIcon,
        infoWindow: InfoWindow(title: dropOff.destinationName),
      ));
    }

    if (_driverPosition != null) {
      newMarkers.add(Marker(
        markerId: const MarkerId('driver'),
        position: _driverPosition!.toLatLng(),
        icon: _driverIcon,
        anchor: const Offset(0.5, 0.5),
        zIndex: 2,
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

  Future<void> _recenterOnDriver() async {
    if (_driverPosition == null) return;
    final controller = await _mapController.future;
    await controller.animateCamera(CameraUpdate.newLatLng(_driverPosition!.toLatLng()));
  }

  // --- ACTIONS & CALL LOGIC (The Awake Strategy) ---

Future<void> _initiateInAppCall() async {
    if (_driverID == null) return;
    if (_isCallLoading) return;
    
    setState(() => _isCallLoading = true);

    try {
      
      final call = Call(
        callId: widget.dealId,
        dealId: widget.dealId,
        driverId: _driverID!,
        userId:  FirebaseAuth.instance.currentUser!.uid,
        callerId: FirebaseAuth.instance.currentUser!.uid,
        receiverId: _driverID!, // ou userId selon qui appelle
        callStatus: 'dialing',
        agoraChannel: widget.dealId, 
        
        // --- CHANGEMENT ICI ---
        agoraToken: '', // On laisse vide, Agora acceptera car "App ID Only"
        // ----------------------
        
        hasVideo: false,
        timestamp: DateTime.now(),
      );
      final isproceed =  await CallService().makeCall(call: call); // Ceci appelle la fonction Cloud

        if (isproceed == false) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Call initiation failed')),
            );
          }
          return;
        }
      // 1. On crée le doc (ce qui déclenche la notif via la Cloud Function simplifiée)

      if (!mounted) return;

      // 2. PLUS D'ATTENTE ! On rejoint direct.
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VoiceCallScreen(call: call, isCaller: true)
        ),
      );

    } catch (e) {
       // Gestion erreur
    } finally {
      if (mounted) setState(() => _isCallLoading = false);
    }
  }
  // --- Utils & Assets ---

  Future<void> _loadCustomMarkerIcons() async {
    try {
      _driverIcon = await BitmapDescriptor.fromAssetImage(const ImageConfiguration(), 'assets/delivery_boy.png');
      _pickupIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
      _undeliveredStopIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
      _deliveredStopIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
      setState(() {});
    } catch(e) {
      debugPrint("Asset error: $e");
    }
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
      SnackBar(content: const Text('Delivery canceled'), backgroundColor: Theme.of(context).colorScheme.error),
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

  Future<void> _handleCancellation() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Order?'),
        content: const Text('Are you sure you want to cancel?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance.collection('deals').doc(widget.dealId).update({'status': 'canceled'});
    }
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final l10n = AppLocalizations.of(context)!;

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
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),

          // 2. Loading & Error States
          if (_screenState == ScreenState.loading)
            const Center(child: RotatingDotsIndicator()),
            
          if (_screenState == ScreenState.error)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 48, color: colorScheme.error),
                  const SizedBox(height: 16),
                  Text(_errorMessage ?? 'Error', style: TextStyle(color: colorScheme.onSurface)),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: _initializeScreen, child: const Text('Retry')),
                ],
              ),
            ),

          // 3. Top Buttons (Recenter)
          if (_screenState == ScreenState.ready)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              right: 16,
              child: FloatingActionButton.small(
                heroTag: 'center',
                onPressed: _recenterOnDriver,
                backgroundColor: colorScheme.surface,
                foregroundColor: colorScheme.onSurface,
                child: const Icon(Icons.gps_fixed),
              ),
            ),

          // 4. Premium Compact Driver Card
          if (_screenState == ScreenState.ready && widget.watcher)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 16), // Floating effect
                  padding: const EdgeInsets.all(12), // Compact internal padding
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh, // Slightly distinct from map
                    borderRadius: BorderRadius.circular(24), // Modern rounded corners
                    border: Border.all(
                      color: colorScheme.outlineVariant.withOpacity(0.5), 
                      width: 0.5
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.shadow.withOpacity(0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      )
                    ],
                  ),
                  child: Row(
                    children: [
                      // --- A. Driver Avatar ---
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            (_driverName ?? "D").substring(0, 1).toUpperCase(),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ),
                      
                      const SizedBox(width: 12),

                      // --- B. Info (Compact Column) ---
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min, // Hug content
                          children: [
                            Text(
                              _driverName ?? 'driver',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            // Status Badge Row
                            Row(
                              children: [
                                Icon(
                                  Icons.circle, 
                                  size: 8, 
                                  color: _dealStatus == DealStatus.accepted 
                                    ? Colors.amber // Pending
                                    : Colors.green // Active
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _dealStatus == DealStatus.accepted 
                                      ? "En approche" 
                                      : "En cours",
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // --- C. Actions (Row) ---
                      
                      // 1. Cancel Button (Discrete Icon)
                      IconButton(
                        onPressed: _handleCancellation,
                        tooltip: l10n.cancelOrder,
                        style: IconButton.styleFrom(
                          backgroundColor: colorScheme.errorContainer.withOpacity(0.2),
                          foregroundColor: colorScheme.error,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.all(8),
                          minimumSize: const Size(40, 40),
                        ),
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                      
                      const SizedBox(width: 8),

                      // 2. Call Button (Prominent)
                      if (_driverID != null)
                        SizedBox(
                          height: 48,
                          child: FilledButton.icon(
                            onPressed: _isCallLoading ? (){} : _initiateInAppCall,
                            style: FilledButton.styleFrom(
                              backgroundColor: colorScheme.primary,
                              foregroundColor: colorScheme.onPrimary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              elevation: 2,
                            ),
                            icon: _isCallLoading
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      color: colorScheme.onPrimary,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.call_rounded, size: 20),
                            label: _isCallLoading 
                              ? const SizedBox.shrink()
                              : const Text("Appeler", style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
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