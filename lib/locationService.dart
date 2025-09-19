import 'dart:async';
import 'dart:convert';
import 'package:shnell/dots.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:latlong2/latlong.dart' as lt;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/services.dart';
import 'package:shnell/location_utils.dart';
import 'package:shnell/googlePlaces.dart';
import 'dart:ui' show TextDirection;

class SearchLocationScreen extends StatefulWidget {
  final String hintText;
  const SearchLocationScreen({super.key, this.hintText = "Search for a location"});

  @override
  State<SearchLocationScreen> createState() => _SearchLocationScreenState();
}

class _SearchLocationScreenState extends State<SearchLocationScreen> with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  List<GooglePlacePrediction> _searchResults = [];
  bool _isLoading = false;
  String? _errorMessage;
  Timer? _debounce;
  String? _sessionToken;
  static const String _googleApiKey = "AIzaSyCPNt6re39yO5lhlD-H1eXWmRs4BAp_y6w";
  bool _isMapView = false;
  final Completer<GoogleMapController> _mapController = Completer();
  lt.LatLng _currentPinLocation = const lt.LatLng(36.8065, 10.1815);
  String? _currentPinAddress;
  final Map<lt.LatLng, String> _geocodeCache = {};
  Timer? _reverseGeocodeDebounce;

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
    _sessionToken = const Uuid().v4();
    _searchController.addListener(_onSearchChanged);

    _pinDropController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _pinDropAnimation = Tween<double>(begin: -100.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _pinDropController,
        curve: Curves.bounceOut,
      ),
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _pulseScaleAnimation = Tween<double>(begin: 1.0, end: 3.0).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeOut,
      ),
    );

    _pulseOpacityAnimation = Tween<double>(begin: 0.5, end: 0.0).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeOut,
      ),
    );

    _selectController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _selectAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: -30.0), weight: 40),
      TweenSequenceItem(tween: Tween<double>(begin: -30.0, end: 0.0), weight: 60),
    ]).animate(
      CurvedAnimation(parent: _selectController, curve: Curves.easeInOut),
    );
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
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
    }
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (_searchController.text.length > 2) {
        _performAutocompleteSearch(_searchController.text);
      } else if (mounted) {
        setState(() {
          _searchResults = [];
        });
      }
    });
  }

  Future<void> _performAutocompleteSearch(String query) async {
    final l10n = AppLocalizations.of(context);
    if (!mounted || l10n == null) return;
    setState(() {
      _isLoading = true;
    });

    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/autocomplete/json?'
      'input=${Uri.encodeComponent(query)}&components=country:tn&language=${l10n.localeName}&sessiontoken=$_sessionToken&key=$_googleApiKey',
    );
    try {
      final response = await http.get(url);
      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          setState(() {
            _searchResults = (data['predictions'] as List).map((item) => GooglePlacePrediction.fromJson(item)).toList();
            _errorMessage = null;
          });
        } else {
          setState(() {
            _errorMessage = l10n.googleDirectionsError(data['status']);
          });
        }
      } else {
        setState(() {
          _errorMessage = l10n.googleHttpError(response.statusCode.toString());
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = l10n.googleNetworkError(e.toString());
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _onPlaceSelected(GooglePlacePrediction place) async {
    final l10n = AppLocalizations.of(context);
    if (!mounted || place.placeId == null || l10n == null) return;

    setState(() {
      _isLoading = true;
    });

    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/details/json?'
      'place_id=${place.placeId}&fields=geometry,name&sessiontoken=$_sessionToken&key=$_googleApiKey',
    );
    try {
      final response = await http.get(url);
      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final location = data['result']['geometry']['location'];
          final resultPlace = GooglePlacePrediction(
            placeId: place.placeId,
            description: data['result']['name'] ?? place.description,
            lat: location['lat'],
            lng: location['lng'],
          );
          if (mounted) {
            Navigator.pop(context, resultPlace);
            setState(() {
              _sessionToken = const Uuid().v4();
            });
          }
        } else {
          setState(() {
            _isLoading = false;
            _errorMessage = l10n.googleDirectionsError(data['status']);
          });
        }
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = l10n.googleHttpError(response.statusCode.toString());
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = l10n.googleNetworkError(e.toString());
        });
      }
    }
  }

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
    _updatePinAddress();
  }

  Future<void> _updatePinAddress() async {
    if (_reverseGeocodeDebounce?.isActive ?? false) {
      _reverseGeocodeDebounce!.cancel();
    }
    _reverseGeocodeDebounce = Timer(const Duration(milliseconds: 500), () async {
      final address = await LocationUtils.reverseGeocode(_currentPinLocation, context, _geocodeCache);
      if (mounted) {
        setState(() {
          _currentPinAddress = address;
        });
      }
    });
  }

  void _confirmMapSelection() {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return;
    if (_currentPinAddress == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.locationCoordinatesError),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }
    HapticFeedback.mediumImpact();
    _selectController.reset();
    _selectController.forward().whenComplete(() {
      final resultPlace = GooglePlacePrediction(
        placeId: null,
        description: _currentPinAddress!,
        lat: _currentPinLocation.latitude,
        lng: _currentPinLocation.longitude,
      );
      Navigator.pop(context, resultPlace);
      setState(() {
        _sessionToken = const Uuid().v4();
      });
    });
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
          _errorMessage = "err";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return const Scaffold(body: Center(child: Text('Localization not available')));

    return Scaffold(
      extendBodyBehindAppBar: _isMapView,
      appBar: AppBar(
        title: _isMapView
            ? const SizedBox.shrink()
            : TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  hintStyle: const TextStyle(fontSize: 16),
                  border: InputBorder.none,
                ),
                style: const TextStyle(fontSize: 18),
                textDirection: _isRtl(l10n.localeName) ? TextDirection.rtl : TextDirection.ltr,
              ),
        backgroundColor: _isMapView ? Colors.transparent : Theme.of(context).colorScheme.surface,
        elevation: 0,
      ),
      body: Directionality(
        textDirection: _isRtl(l10n.localeName) ? TextDirection.rtl : TextDirection.ltr,
        child: _isMapView ? _buildMapView() : _buildSearchView(),
      ),
    );
  }

  Widget _buildSearchView() {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.my_location, color: Colors.amber, size: 24),
          title: Text(
            l10n.currentLocation,
            style: const TextStyle(fontSize: 16),
          ),
          onTap: _useCurrentLocation,
        ),
        ListTile(
          leading: const Icon(Icons.map_outlined, color: Colors.amber, size: 24),
          title: Text(
            l10n.search,
            style: const TextStyle(fontSize: 16),
          ),
          onTap: _toggleMapView,
        ),
        const Divider(),
        Expanded(
          child: _isLoading
              ? const Center(child: RotatingDotsIndicator()) // Replace with your custom indicator
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
                              leading: const Icon(Icons.location_pin, color: Colors.amber, size: 24),
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

  Widget _buildMapView() {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return const SizedBox.shrink();

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
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.amber,
                        ),
                      ),
                    ),
                  );
                },
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.translate(
                    offset: Offset(0, _pinDropAnimation.value + _selectAnimation.value),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 24.0),
                      child: const Icon(Icons.location_on, color: Colors.amber, size: 48.0),
                    ),
                  ),
                  Container(
                    width: 20,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.9),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.chooseLoadingPosition,
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _currentPinAddress ?? "Chargement...",
                          style: const TextStyle(fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (_isLoading)
                      Center(child: RotatingDotsIndicator()),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _toggleMapView,
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.amber,
                          backgroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: Colors.amber),
                          ),
                          elevation: 0,
                        ),
                        child: Text(l10n.back, style: const TextStyle(fontSize: 16, color: Colors.black)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _confirmMapSelection,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: Text(l10n.confirmPosition, style: const TextStyle(fontSize: 16, color: Colors.white)),
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