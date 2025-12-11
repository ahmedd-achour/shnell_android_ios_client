import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as lt;
import 'package:http/http.dart' as http;
import 'package:shnell/dots.dart';
import 'package:shnell/googlePlaces.dart';
import 'package:shnell/jobType.dart';
import 'package:shnell/locationService.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'dart:convert';
import 'package:shnell/model/destinationdata.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'dart:ui' show TextDirection;

class ShnellMAp extends StatefulWidget {
  const ShnellMAp({super.key});

  @override
  State<ShnellMAp> createState() => _MapViewState();
}

class _MapViewState extends State<ShnellMAp> with AutomaticKeepAliveClientMixin {
  static const String _googleApiKey = "AIzaSyCPNt6re39yO5lhlD-H1eXWmRs4BAp_y6w";
  static const int _maxDropOffs = 24;
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
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _dropOffControllersNotifier.value.add(TextEditingController());
    _dropOffData.add(DropOffData(destination: lt.LatLng(0, 0), destinationName: ''));
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

  bool _isRtl(String? localeName) {
    return false;
  }

  // --- LOGIQUE API & MAP ---

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
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
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
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
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
              customerName: _dropOffData[index].customerName,
              customerPhoneNumber: _dropOffData[index].customerPhoneNumber,
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

  // --- WIDGETS UI ---


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
                          _mapController.complete(controller);
                          _updateMapElements();
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
            if (_isWaitingForSet) const Center(child: RotatingDotsIndicator()),
          ],
        ),
      ),
      bottomSheet: _buildDraggableSheet(),
    );
  }
Widget _buildDropOffFieldSliver({
    required BuildContext context,
    required TextEditingController controller,
    required int index,
  }) {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final primaryColor = colorScheme.primary;

    return ReorderableDragStartListener(
      index: index,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
        // Suppression de l'ombre ici pour la performance (on la mettra au drag)
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Poignée visuelle
              Padding(
                padding: const EdgeInsets.only(left: 8.0, right: 4.0),
                child: Icon(Icons.drag_indicator, color: colorScheme.outline.withOpacity(0.5)),
              ),
              _buildDotsAndLines(index, _dropOffControllersNotifier.value.length, primaryColor),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: controller,
                  readOnly: true,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _openSearch('dropoff', index: index);
                  },
                  decoration: InputDecoration(
                    hintText: l10n.destinationWithNumber('${index + 1}'),
                    prefixIcon: Icon(Icons.location_on_outlined, color: primaryColor, size: 24),
                    border: InputBorder.none, // Suppression des bordures internes pour alléger le rendu
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  style: TextStyle(fontSize: 16, color: colorScheme.onSurface),
                ),
              ),
              // Boutons d'action
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.close, color: colorScheme.onSurface.withOpacity(0.6), size: 20),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      _removeDropOffField(index);
                    },
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }


  // Ajoutez cette méthode dans votre classe State


Widget _buildDraggableSheet() {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final primaryColor = colorScheme.primary;

    return AnimatedBuilder(
      animation: _dropOffControllersNotifier,
      builder: (context, child) {
        // Utilisation de LayoutBuilder pour obtenir la hauteur totale de l'écran
        return LayoutBuilder(
          builder: (context, constraints) {
            final double screenHeight = constraints.maxHeight;

            // --- CALCUL DES HAUTEURS EN PIXELS (Fixes) ---
            
            // 1. Footer (Bouton + Padding)
            // Bouton (48px) + Padding Top (10px) + Padding Bottom (16px pour safe area/marge)
            const double footerPixels = 48.0 + 10.0 + 16.0;

            // 2. Header (Poignée + Titre "Where to go")
            // Poignée (4px) + Marges (32px) + Texte (22px * 1.2 line height ≈ 27px)
            const double headerPixels = 70.0;

            // 3. Calcul du ratio (0.0 à 1.0)
            // On ajoute une petite marge de sécurité (+10px)
            final double minSizeCalculated = (footerPixels + headerPixels) / screenHeight;
            
            // Sécurité : on s'assure que la valeur reste entre 0.1 et 0.5
            final double minChildSize = minSizeCalculated.clamp(0.1, 0.5);

            return DraggableScrollableSheet(
              key: _bottomSheetKey,
              initialChildSize: 0.55,
              minChildSize: minChildSize, // Valeur dynamique calculée
              maxChildSize: 0.8,
              expand: false,
              snap: true,
              // Le premier point de snap est maintenant exactement la hauteur du header + bouton
              snapSizes: [minChildSize, 0.55, 0.8],
              builder: (BuildContext context, ScrollController scrollController) {
                return Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.shadow.withOpacity(0.2),
                        blurRadius: 20,
                        offset: const Offset(0, -10),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      // --- COUCHE 1 : LE CONTENU DÉFILANT ---
                      CustomScrollView(
                        controller: scrollController,
                        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                        slivers: [
                          // Poignée
                          SliverToBoxAdapter(
                            child: Center(
                              child: Container(
                                width: 48,
                                height: 4,
                                margin: const EdgeInsets.symmetric(vertical: 16),
                                decoration: BoxDecoration(
                                  color: primaryColor.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),

                          // Titre + Pickup
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.whereDoYouWantToGo,
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  _buildLocationCard(
                                    context: context,
                                    title: l10n.pickup,
                                    icon: Icons.my_location_rounded,
                                    controller: _pickupController,
                                    hintText: l10n.pickupLocation,
                                    onTap: () => _openSearch('pickup'),
                                  ),
                                  const SizedBox(height: 24),
                                  Text(
                                    l10n.destination,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.onSurface.withOpacity(0.6),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                              ),
                            ),
                          ),

                          // Liste des destinations
                         // Liste des destinations (Sans réorganisation manuelle)
ValueListenableBuilder<List<TextEditingController>>(
  valueListenable: _dropOffControllersNotifier,
  builder: (context, controllers, child) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          // No RepaintBoundary or Reorderable wrapper needed here for standard lists
          return _buildDropOffFieldSliver(
            context: context,
            controller: controllers[index],
            index: index,
          );
        },
        childCount: controllers.length,
      ),
    );
  },
),

                          // Bouton "Ajouter une destination"
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24.0),
                              child: _dropOffControllersNotifier.value.length < _maxDropOffs
                                  ? _buildAddDestinationButton(context)
                                  : const SizedBox(height: 20),
                            ),
                          ),

                          // Espace vide pour ne pas cacher le dernier élément derrière le footer
                          SliverToBoxAdapter(
                            child: SizedBox(height: footerPixels + MediaQuery.of(context).viewInsets.bottom),
                          ),
                        ],
                      ),

                      // --- COUCHE 2 : LE BOUTON FIXE (REDUIT) ---
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          // Padding réduit pour gagner de la place (10 en haut, 16 en bas)
                          padding: const EdgeInsets.fromLTRB(24, 10, 24, 16),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            // Optionnel : petite ligne de séparation subtile si désiré
                            border: Border(top: BorderSide(color: colorScheme.outline.withOpacity(0.05))),
                          ),
                          child: SafeArea(
                            top: false,
                            child: _pickupAddress == null || _dropOffData.isEmpty
                                ? _buildContinueButton(context, isActive: false)
                                : _buildContinueButton(context, isActive: true),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          }
        );
      },
    );
  }

  // --- BOUTON CONTINUER RÉDUIT ---
  Widget _buildContinueButton(BuildContext context, {required bool isActive}) {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final primaryColor = colorScheme.primary;

    return SizedBox(
      width: double.infinity,
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
    );
  }
  
  
   Widget _buildLocationCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required TextEditingController controller,
    required String hintText,
    required VoidCallback onTap,
  }) {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest, // Remplaçant de surfaceVariant dans M3
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: _isRtl(l10n.localeName) ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface.withOpacity(0.6),
            ),
            textAlign: _isRtl(l10n.localeName) ? TextAlign.end : TextAlign.start,
          ),
          const SizedBox(height: 8),
          _buildTextField(
            context: context,
            controller: controller,
            hintText: hintText,
            icon: icon,
            onTap: onTap,
          ),
        ],
      ),
    );
  }


  Widget _buildTextField({
    required BuildContext context,
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;

    return TextField(
      controller: controller,
      readOnly: true,
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: Icon(icon, color: colorScheme.primary, size: 24),
        filled: true,
        fillColor: colorScheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      ),
      style: TextStyle(fontSize: 16, color: colorScheme.onSurface),
      textDirection: _isRtl(l10n.localeName) ? TextDirection.rtl : TextDirection.ltr,
    );
  }

 
  Widget _buildDotsAndLines(int index, int total, Color primaryColor) {
    return Column(
      children: [
        if (index == 0)
          Icon(Icons.circle, size: 12, color: primaryColor)
        else
          Icon(Icons.circle, size: 12, color: primaryColor),
        if (index < total - 1)
          Container(
            height: 32,
            width: 2,
            color: primaryColor.withOpacity(0.5),
          ),
      ],
    );
  }

  Widget _buildAddDestinationButton(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return const SizedBox.shrink();

    final primaryColor = Theme.of(context).colorScheme.primary;

    return Align(
      alignment: _isRtl(l10n.localeName) ? Alignment.centerRight : Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () {
          HapticFeedback.lightImpact();
          _addDropOffField();
        },
        icon: Icon(Icons.add_location_alt_rounded, color: primaryColor),
        label: Text(
          l10n.addDestination,
          style: TextStyle(
            color: primaryColor,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
        ),
      ),
    );
  }

}