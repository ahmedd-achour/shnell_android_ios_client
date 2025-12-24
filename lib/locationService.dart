import 'dart:async';
import 'dart:convert';
import 'package:shnell/dots.dart'; // Ensure this exists in your project
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:latlong2/latlong.dart' as lt;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/services.dart';
import 'package:shnell/location_utils.dart'; // Ensure this contains the updated logic
import 'package:shnell/googlePlaces.dart'; // Ensure this model exists
import 'dart:ui' show TextDirection;

class SearchLocationScreen extends StatefulWidget {
  final String hintText;
  final bool isPickup; 

  const SearchLocationScreen({
    super.key, 
    this.hintText = "Search for a location",
    this.isPickup = true, 
  });

  @override
  State<SearchLocationScreen> createState() => _SearchLocationScreenState();
}

class _SearchLocationScreenState extends State<SearchLocationScreen> with TickerProviderStateMixin {
  // Controllers & State
  final TextEditingController _searchController = TextEditingController();
  List<GooglePlacePrediction> _searchResults = [];
  bool _isLoading = false;
  String? _errorMessage;
  Timer? _debounce;
  
  static const String _hereApiKey = "b2zG0dap6jOlqXTOvF2HWrHRq-QFvkcoGjogNxUr-EE"; 
  static const String _googleApiKey = "AIzaSyCPNt6re39yO5lhlD-H1eXWmRs4BAp_y6w"; 

  bool _isMapView = false;
  final Completer<GoogleMapController> _mapController = Completer();
  lt.LatLng _currentPinLocation = const lt.LatLng(36.8065, 10.1815);
  String? _currentPinAddress;
  final Map<lt.LatLng, String> _geocodeCache = {};
  Timer? _reverseGeocodeDebounce;

  // Animations
  late AnimationController _pinDropController;
  late Animation<double> _pinDropAnimation;
  late AnimationController _pulseController;
  late Animation<double> _pulseScaleAnimation;
  late Animation<double> _pulseOpacityAnimation;
  late AnimationController _selectController;
  late Animation<double> _selectAnimation;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _initAnimations();
  }

  void _initAnimations() {
    _pinDropController = AnimationController(duration: const Duration(milliseconds: 1000), vsync: this);
    _pinDropAnimation = Tween<double>(begin: -100.0, end: 0.0).animate(CurvedAnimation(parent: _pinDropController, curve: Curves.bounceOut));
    
    _pulseController = AnimationController(duration: const Duration(milliseconds: 2000), vsync: this);
    _pulseScaleAnimation = Tween<double>(begin: 1.0, end: 3.0).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeOut));
    _pulseOpacityAnimation = Tween<double>(begin: 0.5, end: 0.0).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeOut));
    
    _selectController = AnimationController(duration: const Duration(milliseconds: 600), vsync: this);
    _selectAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: -30.0), weight: 40),
      TweenSequenceItem(tween: Tween<double>(begin: -30.0, end: 0.0), weight: 60),
    ]).animate(CurvedAnimation(parent: _selectController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _reverseGeocodeDebounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _pinDropController.dispose();
    _pulseController.dispose();
    _selectController.dispose();
    super.dispose();
  }

  bool _isRtl(String? localeName) {
    const rtlLanguages = ['ar'];
    return localeName != null && rtlLanguages.contains(localeName);
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      if (_searchController.text.length > 2) {
        _performAutocompleteSearch(_searchController.text);
      } else {
        setState(() => _searchResults = []);
      }
    });
  }

  // --- 1. HERE API SEARCH ---
  Future<void> _performAutocompleteSearch(String query) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final url = Uri.parse(
      'https://autosuggest.search.hereapi.com/v1/autosuggest?'
      'at=36.8065,10.1815&' 
      'q=${Uri.encodeComponent(query)}&'
      'limit=5&'
      'apiKey=$_hereApiKey'
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['items'] as List;

        setState(() {
          _searchResults = items.map((item) {
            return GooglePlacePrediction(
              placeId: item['id'], 
              description: item['title'] + ", " + (item['address']['label'] ?? ""),
              lat: item['position'] != null ? item['position']['lat'] : 0.0,
              lng: item['position'] != null ? item['position']['lng'] : 0.0,
            );
          }).toList();
          _errorMessage = null;
        });
      } else {
        setState(() => _errorMessage = "Error: ${response.statusCode}");
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = "Network Error");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- 2. VALIDATION LOGIC (Localized) ---
  
  Future<String?> _checkZoneValidity(BuildContext context, lt.LatLng location) async {
    final l10n = AppLocalizations.of(context)!;
    
    // Get Address Components from Google Geocoding
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/geocode/json?latlng=${location.latitude},${location.longitude}&key=$_googleApiKey',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['results'].isNotEmpty) {
          final components = data['results'][0]['address_components'] as List;
          
          String countryCode = '';
          String adminArea = ''; // Governorate

          for (var c in components) {
            final types = c['types'] as List;
            if (types.contains('country')) countryCode = c['short_name']; 
            if (types.contains('administrative_area_level_1')) adminArea = c['long_name'];
          }

          // Rule 1: Must be in Tunisia
          if (countryCode != 'TN') {
            return l10n.serviceTunisiaOnly; 
          }

          // Rule 2: If Pickup, must be Greater Tunis
          if (widget.isPickup) {
             final lowerGov = adminArea.toLowerCase();
             final isGreaterTunis = 
               lowerGov.contains('tunis') || 
               lowerGov.contains('ariana') || 
               lowerGov.contains('ben arous') || 
               lowerGov.contains('manouba');
             
             if (!isGreaterTunis) {
               return l10n.pickupRestrictedError;
             }
          }

          return null; // Valid
        }
      }
    } catch (e) {
      debugPrint("Validation check failed: $e");
      return l10n.zoneValidationFailed;
    }
    return l10n.zoneValidationFailed;
  }

  // --- 3. SELECTION HANDLERS ---

  void _onPlaceSelected(GooglePlacePrediction place) async {
    if (place.lat != 0.0 && place.lng != 0.0) {
      setState(() => _isLoading = true);
      
      final errorMsg = await _checkZoneValidity(context, lt.LatLng(place.lat!, place.lng!));
      
      if (!mounted) return;
      setState(() => _isLoading = false);

      if (errorMsg != null) {
        _showUnsupportedAreaDialog(errorMsg);
      } else {
        HapticFeedback.lightImpact();
        Navigator.pop(context, place);
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Coordinates not found"),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _confirmMapSelection() async {
    setState(() => _isLoading = true);
    final l10n = AppLocalizations.of(context)!;

    try {
      final errorMsg = await _checkZoneValidity(context, _currentPinLocation);

      if (errorMsg != null) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        _showUnsupportedAreaDialog(errorMsg);
        return;
      }

      String? finalAddress = await LocationUtils.reverseGeocode(
        _currentPinLocation, 
        context, 
        _geocodeCache
      );

      finalAddress ??= "${_currentPinLocation.latitude.toStringAsFixed(5)}, ${_currentPinLocation.longitude.toStringAsFixed(5)}";

      if (!mounted) return;

      HapticFeedback.mediumImpact();
      await _selectController.forward();

      final resultPlace = GooglePlacePrediction(
        placeId: null,
        description: finalAddress,
        lat: _currentPinLocation.latitude,
        lng: _currentPinLocation.longitude,
      );
      
      Navigator.pop(context, resultPlace);

    } catch (e) {
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${l10n.zoneValidationFailed} ($e)")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _useCurrentLocation() async {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final position = await LocationUtils.getCurrentLocation();
      final latLng = lt.LatLng(position.latitude, position.longitude);
      
      final errorMsg = await _checkZoneValidity(context, latLng);
      
      if (errorMsg != null) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        _showUnsupportedAreaDialog(errorMsg);
        return;
      }

      final address = await LocationUtils.reverseGeocode(latLng, context, {});
      
      if (mounted) {
        HapticFeedback.mediumImpact();
        Navigator.pop(
          context,
          GooglePlacePrediction(
            placeId: null,
            description: address ?? l10n.currentLocation,
            lat: latLng.latitude,
            lng: latLng.longitude,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = l10n.locationPermissionDenied;
        });
      }
    }
  }

  // --- 4. UNSUPPORTED AREA DIALOG (Localized) ---

  void _showUnsupportedAreaDialog(String message) {
    final l10n = AppLocalizations.of(context)!;
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.map_outlined, color: Colors.orange, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.unsupportedAreaTitle,
                style: const TextStyle(fontSize: 18),
              )
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              style: const TextStyle(fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.withOpacity(0.3))
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 20, color: Colors.blue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.isPickup 
                        ? l10n.expansionMessagePickup
                        : l10n.expansionMessageDropoff,
                      style: TextStyle(fontSize: 13, color: Colors.blue[800]),
                    ),
                  )
                ],
              ),
            )
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.selectDifferentLocation),
          )
        ],
      ),
    );
  }

  // --- MAP & UI HELPERS ---

  void _toggleMapView() {
    setState(() {
      _isMapView = !_isMapView;
      if (_isMapView) {
        _pinDropController.reset();
        _pinDropController.forward().whenComplete(() {
          _pulseController.repeat();
        });
        _searchController.clear();
        _searchResults = [];
        _updatePinAddress();
      } else {
        _pulseController.stop();
      }
    });
  }

  void _onMapCameraMove(CameraPosition position) {
    _currentPinLocation = lt.LatLng(position.target.latitude, position.target.longitude);
    if (_currentPinAddress != null) {
       setState(() {
         _currentPinAddress = null; 
       });
    }
  }

  Future<void> _updatePinAddress() async {
    if (_reverseGeocodeDebounce?.isActive ?? false) _reverseGeocodeDebounce!.cancel();
    _reverseGeocodeDebounce = Timer(const Duration(milliseconds: 500), () async {
      final address = await LocationUtils.reverseGeocode(_currentPinLocation, context, _geocodeCache);
      if (mounted) {
        setState(() => _currentPinAddress = address);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    if (l10n == null) return const Scaffold(body: Center(child: Text('Localization not available')));

    return Scaffold(
      extendBodyBehindAppBar: _isMapView,
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: _isMapView
            ? const SizedBox.shrink()
            : TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  hintStyle: TextStyle(fontSize: 16, color: colorScheme.onSurfaceVariant),
                  border: InputBorder.none,
                ),
                style: TextStyle(fontSize: 18, color: colorScheme.onSurface),
                textDirection: _isRtl(l10n.localeName) ? TextDirection.rtl : TextDirection.ltr,
              ),
        backgroundColor: _isMapView ? Colors.transparent : colorScheme.surface,
        elevation: 0,
        iconTheme: IconThemeData(
          color: _isMapView ? colorScheme.onSurface : colorScheme.onSurface,
          shadows: _isMapView ? [const Shadow(color: Colors.black45, blurRadius: 3)] : null
        ),
      ),
      body: Directionality(
        textDirection: _isRtl(l10n.localeName) ? TextDirection.rtl : TextDirection.ltr,
        child: _isMapView ? _buildMapView(colorScheme, l10n) : _buildSearchView(colorScheme, l10n),
      ),
    );
  }

  Widget _buildSearchView(ColorScheme colorScheme, AppLocalizations l10n) {
    return Column(
      children: [
        ListTile(
          leading: Icon(Icons.my_location, color: colorScheme.primary, size: 24),
          title: Text(l10n.currentLocation, style: TextStyle(fontSize: 16, color: colorScheme.onSurface)),
          onTap: _useCurrentLocation,
        ),
        ListTile(
          leading: Icon(Icons.map_outlined, color: colorScheme.primary, size: 24),
          title: Text(l10n.search, style: TextStyle(fontSize: 16, color: colorScheme.onSurface)),
          onTap: _toggleMapView,
        ),
        Divider(color: colorScheme.outlineVariant),
        Expanded(
          child: _isLoading
              ? const RotatingDotsIndicator()
              : _errorMessage != null
                  ? Center(child: Text(_errorMessage!, style: TextStyle(fontSize: 16, color: colorScheme.error)))
                  : _searchController.text.isNotEmpty && _searchResults.isEmpty
                      ? Center(
                          child: Text(
                            l10n.noContentAvailable,
                            style: TextStyle(fontSize: 16, color: colorScheme.onSurface.withOpacity(0.4)),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            final place = _searchResults[index];
                            return ListTile(
                              leading: Icon(Icons.location_pin, color: colorScheme.secondary, size: 24),
                              title: Text(
                                place.description ?? l10n.untitledSection,
                                style: TextStyle(fontSize: 16, color: colorScheme.onSurface),
                              ),
                              onTap: () => _onPlaceSelected(place),
                            );
                          },
                        ),
        ),
      ],
    );
  }

  Widget _buildMapView(ColorScheme colorScheme, AppLocalizations l10n) {
    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: LatLng(_currentPinLocation.latitude, _currentPinLocation.longitude),
            zoom: 15.0,
          ),
          onMapCreated: (GoogleMapController controller) {
            if (!_mapController.isCompleted) {
              _mapController.complete(controller);
            }
          },
          onCameraMove: _onMapCameraMove, 
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          compassEnabled: true,
          zoomControlsEnabled: false,
        ),

        Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _pulseScaleAnimation.value,
                    child: Opacity(
                      opacity: _pulseOpacityAnimation.value,
                      child: Container(
                        width: 20, height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  );
                },
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: Listenable.merge([_pinDropController, _selectController]),
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(0, _pinDropAnimation.value + _selectAnimation.value),
                        child: child,
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 24.0),
                      child: Image.asset(
                        'assets/pin.png', 
                        width: 48.0,
                        height: 48.0,
                      ),
                    ),
                  ),
                  Container(
                    width: 20, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, spreadRadius: 2)
              ]
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min, 
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.chooseLoadingPosition, 
                  style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _currentPinAddress ?? l10n.locationSelectedOnMap, // Use localized fallback
                          style: TextStyle(
                            fontSize: 16, 
                            color: _currentPinAddress == null 
                                ? colorScheme.onSurface.withOpacity(0.6) 
                                : colorScheme.onSurface
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (_isLoading)
                      const Padding(
                        padding: EdgeInsets.only(left: 8.0),
                        child: SizedBox(width: 24, height: 24, child: RotatingDotsIndicator()),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _toggleMapView,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(l10n.back, style: const TextStyle(fontSize: 16)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FilledButton(
                        onPressed: _isLoading ? null : _confirmMapSelection,
                        style: FilledButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(l10n.confirmPosition, style: const TextStyle(fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}