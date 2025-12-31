import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui show ImageByteFormat, instantiateImageCodec;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as lt;
import 'package:http/http.dart' as http;
import 'package:shnell/customMapStyle.dart';
import 'package:shnell/dots.dart';
import 'package:shnell/googlePlaces.dart';
import 'package:shnell/jobType.dart';
import 'package:shnell/locationService.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:shnell/main.dart';
import 'dart:convert';
import 'package:shnell/model/destinationdata.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class ShnellMAp extends StatefulWidget {
  const ShnellMAp({super.key});

  @override
  State<ShnellMAp> createState() => _MapViewState();
}

class _MapViewState extends State<ShnellMAp> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  static const String _googleApiKey = "AIzaSyCPNt6re39yO5lhlD-H1eXWmRs4BAp_y6w";
  static const int _maxDropOffs = 9;
  static const Duration _debounceDuration = Duration(milliseconds: 500);

  final Completer<GoogleMapController> _mapController = Completer();
  final ValueNotifier<Set<Marker>> _markersNotifier = ValueNotifier({});
  final ValueNotifier<Set<Polyline>> _polylinesNotifier = ValueNotifier({});
  final ValueNotifier<List<TextEditingController>> _dropOffControllersNotifier = ValueNotifier([]);
  final TextEditingController _pickupController = TextEditingController();
  final GlobalKey _bottomSheetKey = GlobalKey();
  Timer? _debounceTimer;

  lt.LatLng? _pickupLocation;
  String? _pickupAddress;
  final List<DropOffData> _dropOffData = [];
  bool _isWaitingForSet = false;
  bool _needsBoundsUpdate = false;

  @override
  void initState() {
    super.initState();
    // Initialize with one empty drop-off
    _dropOffControllersNotifier.value = [TextEditingController()];
      mapStyleNotifier.addListener(_updateMapStyle); 
      
         _dropOffData.add(DropOffData(destination: const lt.LatLng(0, 0), destinationName: ''));
  }
void _updateMapStyle() {
  if (_mapController.isCompleted) {
    _mapController.future.then((controller) {
      controller.setMapStyle(mapStyleNotifier.value);
    });
  }
}



  @override
  void dispose() {
    _debounceTimer?.cancel();
    _pickupController.dispose();
    for (var controller in _dropOffControllersNotifier.value) {
      controller.dispose();
    }
    _dropOffControllersNotifier.dispose();
    _markersNotifier.dispose();
    _polylinesNotifier.dispose();
    _mapController.future.then((controller) => controller.dispose());
    super.dispose();
  }

  bool _isRtl(String localeName) {
    return localeName == 'ar'; // Add more RTL languages if needed
  }

  // ==================== MAP & ROUTING LOGIC ====================

Future<void> _updateMapElements({bool forceBoundsUpdate = false}) async {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return;
    
    // Récupération de la couleur primaire pour la polyline
    final primaryColor = Theme.of(context).colorScheme.primary;

    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(_debounceDuration, () async {
      final newMarkers = <Marker>{};
      final newPolylines = <Polyline>{};

      if (_pickupLocation != null) {
newMarkers.add(
  Marker(
    markerId: const MarkerId('pickup'),
    position: LatLng(_pickupLocation!.latitude, _pickupLocation!.longitude),
    icon: await _loadCustomMarker(),
    infoWindow: InfoWindow(title: _pickupAddress ?? l10n.pickupLocation),
  ),
);
      }
      for (int i = 0; i < _dropOffData.length; i++) {
        final dropOff = _dropOffData[i];
        if (dropOff.destination.latitude != 0 && dropOff.destination.longitude != 0) {
          newMarkers.add(
            Marker(
              markerId: MarkerId('dropoff_$i'),
              position: LatLng(dropOff.destination.latitude, dropOff.destination.longitude),
              icon: await _loadCustomMarker(),//BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
              infoWindow: InfoWindow(
                title: dropOff.destinationName.isNotEmpty
                    ? dropOff.destinationName
                    : l10n.destinationWithNumber('${i + 1}'),
              ),
              
            ),
          );
        }
      }
      _markersNotifier.value = newMarkers;

      if (_pickupLocation != null &&
          _dropOffData.any((data) => data.destination.latitude != 0 && data.destination.longitude != 0)) {
        
        // Appel de la logique API
        final result = await _optimizeRoute();
        
        if (result['points'].isNotEmpty) {
          newPolylines.add(
            Polyline(
              polylineId: const PolylineId('route'),
              points: result['points'],
              color: primaryColor, // Utilisation de la couleur du thème
              width: 5,
              patterns: [PatternItem.dash(20), PatternItem.gap(10)],
            ),
          );
        }
        _polylinesNotifier.value = newPolylines;
        if (forceBoundsUpdate || _needsBoundsUpdate) {
          await _fitMapToBounds();
          _needsBoundsUpdate = false;
        }
      } else {
        _polylinesNotifier.value = {};
        if (_pickupLocation != null && _needsBoundsUpdate) {
          await _animateCameraTo(_pickupLocation!);
          _needsBoundsUpdate = false;
        }
      }
    });
  }

  Future<Map<String, dynamic>> _optimizeRoute() async {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return {'points': <LatLng>[]};

    final validDropOffs =
        _dropOffData.where((data) => data.destination.latitude != 0 && data.destination.longitude != 0).toList();
    if (_pickupLocation == null || validDropOffs.isEmpty) {
      return {'points': <LatLng>[]};
    }

    final List<DropOffData> orderedDropOffs = [];
    final List<DropOffData> remainingDropOffs = List.from(validDropOffs);

    lt.LatLng currentLocation = _pickupLocation!;
    while (remainingDropOffs.isNotEmpty) {
      int nearestIndex = 0;
      num minDistance = double.infinity;
      for (int i = 0; i < remainingDropOffs.length; i++) {
        final distance = _calculateHaversineDistance(currentLocation, remainingDropOffs[i].destination);
        if (distance < minDistance) {
          minDistance = distance;
          nearestIndex = i;
        }
      }
      orderedDropOffs.add(remainingDropOffs[nearestIndex]);
      currentLocation = remainingDropOffs[nearestIndex].destination;
      remainingDropOffs.removeAt(nearestIndex);
    }

    if (mounted) {
      setState(() {
        _dropOffData.clear();
        _dropOffData.addAll(orderedDropOffs);
        for (int i = 0; i < _dropOffControllersNotifier.value.length; i++) {
          _dropOffControllersNotifier.value[i].text = _dropOffData.length > i ? _dropOffData[i].destinationName : '';
        }
      });
    }

    final allPoints = [_pickupLocation!, ...orderedDropOffs.map((data) => data.destination)];
    List<LatLng> routePoints = [];

    // 1. Essai avec OSRM (Open Source Routing Machine)
    try {
      final coordinates = allPoints
          .map((loc) => '${loc.longitude.toStringAsFixed(6)},${loc.latitude.toStringAsFixed(6)}')
          .join(';');
      final url = Uri.parse('http://router.project-osrm.org/route/v1/driving/$coordinates?overview=full&geometries=polyline');
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 'Ok' && data['routes'].isNotEmpty) {
          final polyline = data['routes'][0]['geometry'];
          final polylinePoints = PolylinePoints();
          final decodedPoints = polylinePoints.decodePolyline(polyline);
          routePoints = decodedPoints.map((point) => LatLng(point.latitude, point.longitude)).toList();
          return {'points': routePoints};
        }
      }
    } catch (e) {
    }

    // 2. Fallback Google Maps Directions API
    try {
      const int maxWaypoints = 9;
      final List<List<LatLng>> chunks = [];
      for (int i = 0; i < allPoints.length; i += maxWaypoints) {
        final chunk = allPoints.sublist(
          i,
          i + maxWaypoints > allPoints.length ? allPoints.length : i + maxWaypoints,
        );
        chunks.add(chunk.map((p) => LatLng(p.latitude, p.longitude)).toList());
      }
      for (final chunk in chunks) {
        final origin = '${chunk.first.latitude.toStringAsFixed(6)},${chunk.first.longitude.toStringAsFixed(6)}';
        final destination = '${chunk.last.latitude.toStringAsFixed(6)},${chunk.last.longitude.toStringAsFixed(6)}';
        final waypoints = chunk
            .sublist(1, chunk.length - 1)
            .map((loc) => '${loc.latitude.toStringAsFixed(6)},${loc.longitude.toStringAsFixed(6)}')
            .join('|');

        final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/directions/json?'
          'origin=$origin&'
          'destination=$destination&'
          'waypoints=$waypoints&'
          'key=$_googleApiKey',
        );
        final response = await http.get(url).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
            final polyline = data['routes'][0]['overview_polyline']['points'];
            final polylinePoints = PolylinePoints();
            final decodedPoints = polylinePoints.decodePolyline(polyline);
            routePoints.addAll(decodedPoints.map((point) => LatLng(point.latitude, point.longitude)));
          } else {
            _showError(l10n.googleDirectionsError(data['status']));
            return {'points': <LatLng>[]};
          }
        } else {
          _showError(l10n.googleHttpError(response.statusCode.toString()));
          return {'points': <LatLng>[]};
        }
      }
      return {'points': routePoints};
    } catch (e) {
      _showError(l10n.googleNetworkError(e.toString()));
      return {'points': <LatLng>[]};
    }
  }

  Future<BitmapDescriptor> _loadCustomMarker() async {
    final imageBytes = (await rootBundle.load('assets/pin.png')).buffer.asUint8List();
    final codec = await ui.instantiateImageCodec(imageBytes, targetWidth: 85);
    final frameInfo = await codec.getNextFrame();
    final imageData = await frameInfo.image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(imageData!.buffer.asUint8List());
  }


  num _calculateHaversineDistance(lt.LatLng point1, lt.LatLng point2) {
    const earthRadius = 6371;
    final lat1 = point1.latitude * pi / 180;
    final lat2 = point2.latitude * pi / 180;
    final deltaLat = (point2.latitude - point1.latitude) * pi / 180;
    final deltaLng = (point2.longitude - point1.longitude) * pi / 180;
    final a = sin(deltaLat / 2) * sin(deltaLat / 2) + cos(lat1) * cos(lat2) * sin(deltaLng / 2) * sin(deltaLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  Future<void> _fitMapToBounds() async {
    final allLocations = [_pickupLocation, ..._dropOffData.map((data) => data.destination)]
        .where((loc) => loc != null && loc.latitude != 0 && loc.longitude != 0)
        .toList();
    if (allLocations.isEmpty) return;

    num minLat = allLocations.first!.latitude;
    num maxLat = allLocations.first!.latitude;
    num minLng = allLocations.first!.longitude;
    num maxLng = allLocations.first!.longitude;

    for (var loc in allLocations) {
      minLat = min(minLat, loc!.latitude);
      maxLat = max(maxLat, loc.latitude);
      minLng = min(minLng, loc.longitude);
      maxLng = max(maxLng, loc.longitude);
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat.toDouble(), minLng.toDouble()),
      northeast: LatLng(maxLat.toDouble(), maxLng.toDouble()),
    );
    final controller = await _mapController.future;
    await controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
  }

  Future<void> _animateCameraTo(lt.LatLng location, {double zoom = 15.0}) async {
    final controller = await _mapController.future;
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(location.latitude, location.longitude),
          zoom: zoom,
        ),
      ),
    );
  }

  void _onLocationSelected(String type, GooglePlacePrediction? place, {int? index}) {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return;

    if (place?.lat == null || place?.lng == null) {
      _showError(l10n.locationCoordinatesError);
      return;
    }
    final selectedLocation = lt.LatLng(place!.lat!, place.lng!);
    final selectedAddress = place.description!;

    if (mounted) {
      setState(() {
        if (type == "pickup") {
          _pickupLocation = selectedLocation;
          _pickupAddress = selectedAddress;
          _pickupController.text = selectedAddress;
        } else {
          if (index != null && _dropOffData.length > index) {
            _dropOffData[index] = DropOffData(
              destination: selectedLocation,
              destinationName: selectedAddress,
            );
            _dropOffControllersNotifier.value[index].text = selectedAddress;
          } else {
            _dropOffData.add(DropOffData(
              destination: selectedLocation,
              destinationName: selectedAddress,
            ));
            _dropOffControllersNotifier.value.last.text = selectedAddress;
          }
        }
        _needsBoundsUpdate = true;
      });
      _updateMapElements(forceBoundsUpdate: true);
    }
  }
/*
  void _addDropOffField() {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return;

    if (_pickupLocation == null) {
      _showError(l10n.definePickupFirst);
      return;
    }
    for (final controller in _dropOffControllersNotifier.value) {
      if (controller.text.isEmpty) {
        _showError(l10n.definePreviousDestinationFirst);
        return;
      }
    }
    if (_dropOffControllersNotifier.value.length < _maxDropOffs) {
      if (mounted) {
        setState(() {
          final newController = TextEditingController();
          _dropOffControllersNotifier.value = List.from(_dropOffControllersNotifier.value)..add(newController);
          _dropOffData.add(DropOffData(destination: lt.LatLng(0, 0), destinationName: ''));
          _needsBoundsUpdate = true;
        });
        _updateMapElements();
      }
    } else {
      _showError(l10n.maxDestinationsReached(_maxDropOffs.toString()));
    }
  }

  void _removeDropOffField(int index) {
    if (_dropOffControllersNotifier.value.length > 1) {
      if (mounted) {
        setState(() {
          final controllers = List<TextEditingController>.from(_dropOffControllersNotifier.value);
          controllers[index].dispose();
          controllers.removeAt(index);
          _dropOffControllersNotifier.value = controllers;
          if (_dropOffData.length > index) {
            _dropOffData.removeAt(index);
          }
          _needsBoundsUpdate = true;
        });
        _updateMapElements(forceBoundsUpdate: true);
      }
    }
  }

*/

  void _navigateToVehicleSelection() {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return;

    if (_pickupLocation == null) {
      _showError(l10n.definePickupFirst);
      return;
    }
    if (_dropOffData.isEmpty || (_dropOffControllersNotifier.value.last.text.isEmpty && _dropOffData.last.destination.latitude == 0)) {
      _showError(l10n.selectAtLeastOneDestination);
      return;
    }

    setState(() => _isWaitingForSet = true);

    _optimizeRoute().then((result) {
      if (mounted) {
        setState(() => _isWaitingForSet = false);
        if (result['points'].isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) {
                return ServiceTypeSelectionScreen(
                  pickup: _pickupLocation!,
                  pickupName: _pickupAddress ?? l10n.pickupLocation,
                  dropOffDestination: _dropOffData, 
                );
              },
            ),
          );
        } else {
          _showError(l10n.routeGenerationError, retry: () => _navigateToVehicleSelection());
        }
      }
    });
  }

  Future<void> _openSearch(String type, {int? index}) async {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return;

    final selectedPlace = await Navigator.push<GooglePlacePrediction?>(
      context,
      MaterialPageRoute(
        builder: (context) {
          return SearchLocationScreen(
            hintText: l10n.searchLocationHint(type == 'pickup' ? l10n.pickup : l10n.destination),
          );
        },
      ),
    );
    if (mounted && selectedPlace != null) {
      _onLocationSelected(type, selectedPlace, index: index);
    }
  }

  void _showError(String message, {VoidCallback? retry}) {
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.onError),
            const SizedBox(width: 8),
            Expanded(child: Text(message, style: TextStyle(color: theme.colorScheme.onError))),
          ],
        ),
        backgroundColor: theme.colorScheme.error,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        action: retry != null
            ? SnackBarAction(
                label: AppLocalizations.of(context)?.retry ?? 'Retry',
                textColor: theme.colorScheme.onError,
                onPressed: retry,
              )
            : null,
      ),
    );
  }

 
 
  Widget _buildContinueButton(BuildContext context, {required bool isActive}) {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final primaryColor = colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: SizedBox(
        height: 48, // Hauteur réduite (avant c'était 60 ou plus)
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 1.0, end: _isWaitingForSet ? 0.95 : 1.0),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          builder: (context, scale, child) {
            return Transform.scale(
              scale: scale,
              child: ElevatedButton(
                onPressed: _isWaitingForSet || !isActive
                    ? isActive ? (){} : null
                    : () {
                        HapticFeedback.mediumImpact();
                        _navigateToVehicleSelection();
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isActive ? primaryColor : colorScheme.onSurface.withOpacity(0.12),
                  foregroundColor: isActive ? colorScheme.onPrimary : colorScheme.onSurface.withOpacity(0.38),
                  // Padding interne réduit
                  padding: const EdgeInsets.symmetric(vertical: 0), 
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16), // Rayon un peu plus petit pour matcher la taille
                  ),
                  elevation: isActive ? 4 : 0, // Élévation réduite
                  shadowColor: primaryColor.withOpacity(0.4),
                ),
                child: _isWaitingForSet
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: RotatingDotsIndicator(), // Assurez-vous que votre indicateur s'adapte à 20px
                      )
                    : Text(
                        l10n.continueText,
                        style: TextStyle(
                          fontSize: 16, // Police légèrement réduite pour l'équilibre
                          fontWeight: FontWeight.w600,
                          color: isActive ? colorScheme.onPrimary : colorScheme.onSurface.withOpacity(0.38),
                        ),
                      ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _addDropOff() {
    if (_dropOffControllersNotifier.value.length >= _maxDropOffs) return;

    setState(() {
      _dropOffControllersNotifier.value.add(TextEditingController());
      _dropOffData.add(DropOffData(destination: const lt.LatLng(0, 0), destinationName: ''));
    });
    _dropOffControllersNotifier.value = List.from(_dropOffControllersNotifier.value);
  }

  void _removeDropOff(int index) {
    if (_dropOffControllersNotifier.value.length <= 1) return;

    setState(() {
      _dropOffControllersNotifier.value[index].dispose();
      _dropOffControllersNotifier.value.removeAt(index);
      if (index < _dropOffData.length) {
        _dropOffData.removeAt(index);
      }
      _needsBoundsUpdate = true;
    });
    _dropOffControllersNotifier.value = List.from(_dropOffControllersNotifier.value);
    _updateMapElements(forceBoundsUpdate: true);
  }
  // ==================== UI ====================

@override
Widget build(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  if (l10n == null) return const Scaffold(body: Center(child: Text('Localization not available')));

  super.build(context);

  return Scaffold(
    body: Directionality(
      textDirection: _isRtl(l10n.localeName) ? TextDirection.rtl : TextDirection.ltr,
      child: Stack(
        children: [
          // The full-screen Google Map
          ValueListenableBuilder<Set<Marker>>(
            valueListenable: _markersNotifier,
            builder: (context, markers, child) {
              return ValueListenableBuilder<Set<Polyline>>(
                valueListenable: _polylinesNotifier,
                builder: (context, polylines, child) {
                  return GoogleMap(
                    initialCameraPosition: const CameraPosition(target: LatLng(36.8065, 10.1815), zoom: 11.0),
                    mapType: MapType.normal,
                    
                    onMapCreated: (GoogleMapController controller) {
                      if (!_mapController.isCompleted) {
                        // _applyMapStyle(controller, context);
                        _mapController.complete(controller);
                        _updateMapElements();
                        controller.setMapStyle(mapStyleNotifier.value);
                      }
                    },
                    markers: markers,
                    polylines: polylines,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    compassEnabled: true,
                    zoomControlsEnabled: false,
                  );
                },
              );
            },
          ),

          // Loading indicator overlay
          if (_isWaitingForSet) const Center(child: RotatingDotsIndicator()),

          // Draggable bottom sheet overlay
          _buildDraggableSheet(),  // Move your entire _buildDraggableSheet() here
        ],
      ),
    ),
  );
}
@override
void didChangeDependencies() {
  super.didChangeDependencies();

  // If the map is already created, update the style when theme changes
  if (_mapController.isCompleted) {
    _mapController.future.then((controller) {
      _applyMapStyle(controller, context);
    });
  }
}
void _applyMapStyle(GoogleMapController controller, BuildContext context) {
  final brightness = Theme.of(context).brightness;
  final style = brightness == Brightness.dark ? darkMapStyle : lightMapStyle;
  
  controller.setMapStyle(style).catchError((e) {
    // Silently handle if style is invalid (optional)
    print('Map style error: $e');
  });
}
  Widget _buildDraggableSheet() {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final dropOffCount = _dropOffControllersNotifier.value.length;
    final canContinue = _pickupAddress != null &&
        _dropOffData.any((d) => d.destination.latitude != 0 && d.destination.longitude != 0);

    return AnimatedBuilder(
      animation: _dropOffControllersNotifier,
      builder: (_, __) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final screenHeight = constraints.maxHeight;

            const handleH = 20.0;
            const titleH = 50.0;
            const slotH = 58.0;
            const addBtnH = 40.0;
            const footerH = 80.0;

            double contentH = handleH +
                titleH +
                slotH * (1 + dropOffCount) +
                (dropOffCount < _maxDropOffs ? addBtnH : 10) +
                40;

            if (canContinue) contentH += footerH;

            final minSize = (contentH / screenHeight).clamp(0.25, 0.55);
            final initialSize = canContinue ? 0.45 : minSize;

            return DraggableScrollableSheet(
              key: _bottomSheetKey,
              initialChildSize: initialSize,
              minChildSize: 0.25,
              maxChildSize: 0.85,
              snap: true,
              snapSizes: [0.25, minSize, 0.85],
              builder: (context, scrollController) {
                return Container(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 15,
                          offset: const Offset(0, -5)),
                    ],
                  ),
                  child: Stack(
                    children: [
                      CustomScrollView(
                        controller: scrollController,
                        slivers: [
                          SliverToBoxAdapter(
                            child: Center(
                              child: Container(
                                width: 36,
                                height: 4,
                                margin: const EdgeInsets.only(top: 12, bottom: 8),
                                decoration: BoxDecoration(
                                    color: Colors.grey[300],
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                              child: Text(
                                l10n.whereDoYouWantToGo,
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildTimelineVisuals(dropOffCount, colors),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        children: [
                                          _buildThinInput(
                                            title: l10n.pickupLocation,
                                            controller: _pickupController,
                                            onTap: () => _openSearch('pickup'),
                                            isPickup: true,
                                          ),
                                          const SizedBox(height: 12),
                                          ...List.generate(dropOffCount, (i) {
                                            return Padding(
                                              padding: const EdgeInsets.only(bottom: 12),
                                              child: _buildThinInput(
                                                title: l10n.destination,
                                                controller: _dropOffControllersNotifier.value[i],
                                                onTap: () => _openSearch('dropoff', index: i),
                                                onRemove: () => _removeDropOff(i),
                                                showRemove: true,
                                              ),
                                            );
                                          }),
                                          if (dropOffCount < _maxDropOffs)
                                            GestureDetector(
                                              onTap: () {
                                                HapticFeedback.lightImpact();
                                                _addDropOff();
                                              },
                                              child: Container(
                                                height: 36,
                                                alignment: Alignment.centerLeft,
                                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                                decoration: BoxDecoration(
                                                  color: colors.surfaceContainerHighest.withOpacity(0.3),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.add_rounded,
                                                        size: 18, color: colors.primary),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      l10n.addDestination,
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        fontWeight: FontWeight.w600,
                                                        color: colors.primary,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          const SizedBox(height: 100),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                        if(canContinue)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child:_buildContinueButton(context, isActive: canContinue)),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildTimelineVisuals(int dropOffCount, ColorScheme colors) {
    return Column(
      children: [
        // Pickup dot
        SizedBox(
          height: 46,
          child: Center(
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle),
            ),
          ),
        ),
        // Connecting line
        Expanded(
          child: Container(
            width: 2,
            color: colors.outlineVariant.withOpacity(0.5),
            margin: const EdgeInsets.symmetric(vertical: 4),
          ),
        ),
        // Drop-off squares
        ...List.generate(dropOffCount, (i) {
          return Column(
            children: [
              SizedBox(
                height: 46,
                child: Center(
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: colors.primary, shape: BoxShape.rectangle),
                  ),
                ),
              ),
              if (i < dropOffCount - 1) const SizedBox(height: 12),
            ],
          );
        }),
        if (dropOffCount < _maxDropOffs) const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildThinInput({
    required String title,
    required TextEditingController controller,
    required VoidCallback onTap,
    bool isPickup = false,
    bool showRemove = false,
    VoidCallback? onRemove,
  }) {
    final colors = Theme.of(context).colorScheme;
    final isEmpty = controller.text.isEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.outline.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                isEmpty ? title : controller.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isEmpty ? FontWeight.w400 : FontWeight.w600,
                  color: isEmpty ? colors.onSurfaceVariant : colors.onSurface,
                ),
              ),
            ),
            if (showRemove)
              GestureDetector(
                onTap: onRemove,
                child: Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: colors.surfaceDim),
                  child: Icon(Icons.delete, size: 20, color: colors.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}