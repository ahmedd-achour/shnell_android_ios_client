import 'dart:async';
import 'dart:convert';
import 'package:shnell/dots.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shnell/googlePlaces.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:latlong2/latlong.dart' as lt;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/services.dart';
import 'package:shnell/location_utils.dart';
import 'dart:ui' show TextDirection;

class SearchLocationScreen extends StatefulWidget {
  final String hintText;
  const SearchLocationScreen({super.key, this.hintText = "Search for a location"});

  @override
  State<SearchLocationScreen> createState() => _SearchLocationScreenState();
}

class _SearchLocationScreenState extends State<SearchLocationScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<GooglePlacePrediction> _searchResults = [];
  bool _isLoading = false;
  String? _errorMessage;
  Timer? _debounce;
  String? _sessionToken;
  static const String _googleApiKey = "AIzaSyCPNt6re39yO5lhlD-H1eXWmRs4BAp_y6w";
  bool _isMapView = false;

  // Map view-specific variables
  final Completer<GoogleMapController> _mapController = Completer();
  lt.LatLng _currentPinLocation = const lt.LatLng(36.8065, 10.1815);
  String? _currentPinAddress;
  final Map<lt.LatLng, String> _geocodeCache = {};
  Timer? _reverseGeocodeDebounce;

  @override
  void initState() {
    super.initState();
    _sessionToken = const Uuid().v4();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _reverseGeocodeDebounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  bool _isRtl(String? localeName) {
    const rtlLanguages = ['ar', 'he', 'fa', 'ur'];
    return localeName != null && rtlLanguages.contains(localeName);
  }

  /// Debounces the search input to avoid making too many API calls.
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

  /// Calls the Google Places Autocomplete API to get location suggestions.
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

  /// Fetches the place details (including coordinates) for a selected place.
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
              _sessionToken = const Uuid().v4(); // Reset session token for the next search
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
        _searchController.clear();
        _searchResults = [];
        _updatePinAddress();
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
  }


  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return const Scaffold(body: Center(child: Text('Localization not available')));

    return Scaffold(
      extendBodyBehindAppBar: _isMapView,
      appBar: AppBar(
        title: _isMapView
            ? SizedBox.shrink()            : TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  icon: GestureDetector(
                    onTap: _toggleMapView,
                    child: const Icon(Icons.my_location, color: Colors.blue),
                  ),
                  hintText: widget.hintText,
                  hintStyle: const TextStyle(fontSize: 16, color: Colors.white70),
                  border: InputBorder.none,
                ),
                style: const TextStyle(fontSize: 18, color: Colors.white),
                textDirection: _isRtl(l10n.localeName) ? TextDirection.rtl : TextDirection.ltr,
              ),
        backgroundColor: _isMapView ? Colors.transparent : Colors.amberAccent,
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
    return _isLoading
        ? const Center(child: RotatingDotsIndicator())
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
                        leading: const Icon(Icons.location_on, color: Colors.amber, size: 24),
                        title: Text(
                          place.description ?? l10n.untitledSection,
                          style: TextStyle(fontSize: 16, color: colorScheme.onSurface),
                        ),
                        onTap: () => _onPlaceSelected(place),
                      );
                    },
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
          myLocationButtonEnabled: true,
          compassEnabled: true,
          zoomControlsEnabled: false,
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_pin, color: Colors.red, size: 48.0),
              // This is a placeholder for the animated pin drop effect
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
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
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Choisir position de chargement",
                  style: TextStyle(fontSize: 16, color: Colors.grey),
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
                      Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).primaryColor),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _toggleMapView, // Navigate back to the search view
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
                        child: const Text("Retour", style: TextStyle(fontSize: 16)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _confirmMapSelection,
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor:  Colors.amber, // Dark blue
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: const Text("Confirmer la position", style: TextStyle(fontSize: 16)),
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
