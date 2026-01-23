import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shnell/dots.dart'; 
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:latlong2/latlong.dart' as lt;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/services.dart';
import 'package:shnell/location_utils.dart'; 
import 'package:shnell/googlePlaces.dart'; 
import 'dart:ui' show TextDirection;
import 'package:shnell/main.dart';

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
  final TextEditingController _searchController = TextEditingController();
  List<GooglePlacePrediction> _searchResults = [];
  bool _isLoading = false;
  int _stackIndex = 0; // 0 for Search List, 1 for Map
  Timer? _debounce;

  // Keys preserved exactly as requested
  static const String _hereApiKey = "b2zG0dap6jOlqXTOvF2HWrHRq-QFvkcoGjogNxUr-EE"; 
  static const String _googleApiKey = "AIzaSyCPNt6re39yO5lhlD-H1eXWmRs4BAp_y6w"; 

  final Completer<GoogleMapController> _mapController = Completer();
  lt.LatLng _currentPinLocation = const lt.LatLng(36.8065, 10.1815);
  final Map<lt.LatLng, String> _geocodeCache = {};

  late AnimationController _pinDropController;
  late Animation<double> _pinDropAnimation;
  late AnimationController _pulseController;
  late Animation<double> _pulseScaleAnimation;
  late AnimationController _selectController;
  late Animation<double> _selectAnimation;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _initAnimations();
    // Pre-initialize current location if possible or use default Tunisia center
  }

  void _initAnimations() {
    _pinDropController = AnimationController(duration: const Duration(milliseconds: 1000), vsync: this);
    _pinDropAnimation = Tween<double>(begin: -100.0, end: 0.0).animate(CurvedAnimation(parent: _pinDropController, curve: Curves.bounceOut));
    
    _pulseController = AnimationController(duration: const Duration(milliseconds: 2000), vsync: this)..repeat();
    _pulseScaleAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    
    _selectController = AnimationController(duration: const Duration(milliseconds: 600), vsync: this);
    _selectAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: -30.0), weight: 40),
      TweenSequenceItem(tween: Tween<double>(begin: -30.0, end: 0.0), weight: 60),
    ]).animate(CurvedAnimation(parent: _selectController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _pinDropController.dispose();
    _pulseController.dispose();
    _selectController.dispose();
    super.dispose();
  }

  bool _isRtl(String? localeName) => localeName == 'ar';

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

  Future<void> _performAutocompleteSearch(String query) async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final url = Uri.parse('https://autosuggest.search.hereapi.com/v1/autosuggest?at=36.8065,10.1815&q=${Uri.encodeComponent(query)}&limit=5&apiKey=$_hereApiKey');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['items'] as List;
        setState(() {
          _searchResults = items.map((item) => GooglePlacePrediction(
            placeId: item['id'], 
            description: "${item['title']}, ${item['address']['label'] ?? ''}",
            lat: item['position']?['lat'] ?? 0.0,
            lng: item['position']?['lng'] ?? 0.0,
          )).toList();
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<String?> _checkZoneValidity(BuildContext context, lt.LatLng location) async {
    final l10n = AppLocalizations.of(context)!;
    final url = Uri.parse('https://maps.googleapis.com/maps/api/geocode/json?latlng=${location.latitude},${location.longitude}&key=$_googleApiKey');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['results'].isNotEmpty) {
          final components = data['results'][0]['address_components'] as List;
          String countryCode = '';
          String adminArea = '';
          for (var c in components) {
            final types = c['types'] as List;
            if (types.contains('country')) countryCode = c['short_name'];
            if (types.contains('administrative_area_level_1')) adminArea = c['long_name'];
          }

          if (countryCode != 'TN') return l10n.serviceTunisiaOnly;

          FirebaseFirestore firestore = FirebaseFirestore.instance;
          final doc = await firestore.collection('settings').doc('service_areas').get();
          bool isFullTunisia = doc.data()?['countries']['Tunisia']['active'] ?? false;

          if (!isFullTunisia) {
             final lowerGov = adminArea.toLowerCase();
             final isGreaterTunis = lowerGov.contains('tunis') || lowerGov.contains('ariana') || lowerGov.contains('ben arous') || lowerGov.contains('manouba');
             if (!isGreaterTunis) return l10n.pickupRestrictedError;
          } 
          return null; 
        }
      }
    } catch (e) { return l10n.zoneValidationFailed; }
    return l10n.zoneValidationFailed;
  }

  void _onPlaceSelected(GooglePlacePrediction place) async {
    if (place.lat != 0.0 && place.lng != 0.0) {
      setState(() => _isLoading = true);
      final errorMsg = await _checkZoneValidity(context, lt.LatLng(place.lat!, place.lng!));
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (errorMsg != null) _showUnsupportedAreaDialog(errorMsg);
      else { HapticFeedback.lightImpact(); Navigator.pop(context, place); }
    }
  }

  Future<void> _confirmMapSelection() async {
    setState(() => _isLoading = true);
    try {
      final errorMsg = await _checkZoneValidity(context, _currentPinLocation);
      if (errorMsg != null) {
        if (mounted) setState(() => _isLoading = false);
        _showUnsupportedAreaDialog(errorMsg);
        return;
      }

      String? finalAddress = await LocationUtils.reverseGeocode(_currentPinLocation, context, _geocodeCache);
      finalAddress ??= "${_currentPinLocation.latitude.toStringAsFixed(5)}, ${_currentPinLocation.longitude.toStringAsFixed(5)}";
      
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      await _selectController.forward();

      Navigator.pop(context, GooglePlacePrediction(
        placeId: null,
        description: finalAddress,
        lat: _currentPinLocation.latitude,
        lng: _currentPinLocation.longitude,
      ));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _toggleMapView() {
    setState(() {
      _stackIndex = (_stackIndex == 0) ? 1 : 0;
      if (_stackIndex == 1) {
        _pinDropController.forward(from: 0.0);
      }
    });
  }

  void _showUnsupportedAreaDialog(String message) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [const Icon(Icons.warning_amber_rounded, color: Colors.orange), const SizedBox(width: 10), Text(l10n.unsupportedAreaTitle)]),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.selectDifferentLocation))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isMapView = _stackIndex == 1;

    return Scaffold(
      extendBodyBehindAppBar: isMapView,
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: isMapView ? null : TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(hintText: widget.hintText, border: InputBorder.none),
        ),
        backgroundColor: isMapView ? Colors.transparent : theme.colorScheme.surface,
        elevation: 0,
        iconTheme: IconThemeData(
          color: theme.colorScheme.onSurface,
          shadows: isMapView ? [const Shadow(color: Colors.black45, blurRadius: 10)] : null
        ),
      ),
      body: Directionality(
        textDirection: _isRtl(l10n.localeName) ? TextDirection.rtl : TextDirection.ltr,
        child: IndexedStack(
          index: _stackIndex,
          children: [
            _buildSearchView(theme.colorScheme, l10n),
            _buildMapView(theme.colorScheme, l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchView(ColorScheme colorScheme, AppLocalizations l10n) {
    return Column(
      children: [
        ListTile(leading: Icon(Icons.my_location, color: colorScheme.primary), title: Text(l10n.currentLocation), onTap: () => _useCurrentLocation()),
        ListTile(leading: Icon(Icons.map_outlined, color: colorScheme.primary), title: Text(l10n.search), onTap: _toggleMapView),
        const Divider(),
        Expanded(
          child: _isLoading ? const Center(child: RotatingDotsIndicator()) : ListView.builder(
            itemCount: _searchResults.length,
            itemBuilder: (context, index) => ListTile(
              leading: const Icon(Icons.location_pin),
              title: Text(_searchResults[index].description ?? ""),
              onTap: () => _onPlaceSelected(_searchResults[index]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMapView(ColorScheme colorScheme, AppLocalizations l10n) {
    return Scaffold(
    extendBodyBehindAppBar: true, 
    appBar: AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: Colors.transparent, // Fully transparent
      elevation: 0,                       // Remove shadow
      scrolledUnderElevation: 0,          // Stop color change when map moves
      systemOverlayStyle: SystemUiOverlayStyle.dark, // Dark icons for light map
    ),
    
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: LatLng(_currentPinLocation.latitude, _currentPinLocation.longitude), zoom: 15.0),
            onMapCreated: (controller) {
              controller.setMapStyle(mapStyleNotifier.value);
              if (!_mapController.isCompleted) _mapController.complete(controller);
            },
            onCameraMove: (pos) => _currentPinLocation = lt.LatLng(pos.target.latitude, pos.target.longitude),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),
          
          // Accurate Pin Alignment (Anchor is the tip)
          IgnorePointer(
            child: Center(
              child: AnimatedBuilder(
                animation: Listenable.merge([_pinDropController, _selectController, _pulseController]),
                builder: (context, child) {
                  return Transform.scale(
                    scale: _pulseScaleAnimation.value,
                    child: Transform.translate(
                      offset: Offset(0, -24 + _pinDropAnimation.value + _selectAnimation.value),
                      child: Image.asset('assets/pin.png', width: 48, height: 48),
                    ),
                  );
                },
              ),
            ),
          ),
      
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: _buildBottomPanel(colorScheme, l10n),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel(ColorScheme colorScheme, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.chooseLoadingPosition, style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: colorScheme.surfaceVariant.withOpacity(0.3), borderRadius: BorderRadius.circular(12)),
            child: Text(l10n.locationSelectedOnMap, textAlign: TextAlign.center), // Budget-Friendly: No live API call
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: OutlinedButton(onPressed: _isLoading ? null : _toggleMapView, child: Text(l10n.back))),
              const SizedBox(width: 16),
              Expanded(child: FilledButton(
                onPressed: _isLoading ? null : _confirmMapSelection,
                child: _isLoading ? const SizedBox(width: 24, height: 24, child: RotatingDotsIndicator()) : Text(l10n.confirmPosition),
              )),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _useCurrentLocation() async {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final position = await LocationUtils.getCurrentLocation();
      final latLng = lt.LatLng(position.latitude, position.longitude);
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
        });
      }
    }
  }

}