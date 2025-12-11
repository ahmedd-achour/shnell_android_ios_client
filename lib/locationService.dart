import 'dart:async';
import 'dart:convert';
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

class SearchLocationScreen extends StatefulWidget {
  final String hintText;
  const SearchLocationScreen({super.key, this.hintText = "Search for a location"});

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
  
  // API Config
  
  // Map State
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
    // 1. Pin Drop Animation
    _pinDropController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _pinDropAnimation = Tween<double>(begin: -100.0, end: 0.0).animate(
      CurvedAnimation(parent: _pinDropController, curve: Curves.bounceOut),
    );

    // 2. Pulse Animation (Ring effect under pin)
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _pulseScaleAnimation = Tween<double>(begin: 1.0, end: 3.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );
    _pulseOpacityAnimation = Tween<double>(begin: 0.5, end: 0.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );

    // 3. Selection Animation (Jump on confirm)
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

  // --- SEARCH LOGIC ---

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
/*
this is expensive aproach we prefer the worker one cheap for up to 250 k requests per month free 
  Future<void> _performAutocompleteSearch(String query) async {
    final l10n = AppLocalizations.of(context);
    if (!mounted || l10n == null) return;
    
    setState(() => _isLoading = true);

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
            _searchResults = (data['predictions'] as List)
                .map((item) => GooglePlacePrediction.fromJson(item))
                .toList();
            _errorMessage = null;
          });
        } else {
          setState(() => _errorMessage = l10n.googleDirectionsError(data['status']));
        }
      } else {
        setState(() => _errorMessage = l10n.googleHttpError(response.statusCode.toString()));
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = l10n.googleNetworkError(e.toString()));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
*/

// 1. Add your HERE API Key at the top of the class

// 2. Replace the Google Autocomplete function with this:
// 1. Add your HERE API Key at the top of the class
static const String _hereApiKey = "b2zG0dap6jOlqXTOvF2HWrHRq-QFvkcoGjogNxUr-EE"; 

// 2. Replace the Google Autocomplete function with this:
Future<void> _performAutocompleteSearch(String query) async {
  if (!mounted) return;
  setState(() => _isLoading = true);

  // We prioritize search around Tunisia (Lat 34, Lng 9) for better relevance
  // q = query text
  // at = focus coordinates
  // limit = number of results
  final url = Uri.parse(
    'https://autosuggest.search.hereapi.com/v1/autosuggest?'
    'at=36.8065,10.1815&' // Focus on Tunis
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
        // Map HERE data to your existing GooglePlacePrediction object
        // So the rest of your app doesn't break!
        _searchResults = items.map((item) {
          return GooglePlacePrediction(
            // HERE uses 'id', Google uses 'place_id'
            placeId: item['id'], 
            // HERE uses 'title' + 'address', Google uses 'description'
            description: item['title'] + ", " + (item['address']['label'] ?? ""),
            // HERE gives coordinates immediately! Google requires a second call.
            // This saves you even more complexity.
            lat: item['position'] != null ? item['position']['lat'] : 0.0,
            lng: item['position'] != null ? item['position']['lng'] : 0.0,
          );
        }).toList();
        _errorMessage = null;
      });
    } else {
      // Handle HERE API specific errors
      setState(() => _errorMessage = "Error: ${response.statusCode}");
    }
  } catch (e) {
    if (mounted) setState(() => _errorMessage = "Network Error");
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}
 
 
// REMPLACEZ VOTRE FONCTION _onPlaceSelected ACTUELLE PAR CELLE-CI
  void _onPlaceSelected(GooglePlacePrediction place) {
    // 1. Vérification : Est-ce qu'on a déjà les coordonnées ?
    // (L'API HERE les fournit directement dans la recherche, donc c'est oui)
    if (place.lat != 0.0 && place.lng != 0.0) {
      
      // 2. Feedback Tactile (Optionnel mais agréable)
      HapticFeedback.lightImpact();

      // 3. Retour immédiat
      // On n'appelle PAS Google. On renvoie juste l'objet qu'on a déjà.
      if (mounted) {
        Navigator.pop(context, place);
        
        // On régénère le token session pour la prochaine fois
      }
    } else {
      // Cas rare où l'API de recherche n'a pas donné de coordonnées
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n?.locationCoordinatesError ?? "Coordonnées introuvables"),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
  // --- MAP LOGIC ---

  void _toggleMapView() {
    setState(() {
      _isMapView = !_isMapView;
      if (_isMapView) {
        // Start animations only when entering map view
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

// Remplacez votre fonction _onMapCameraMove actuelle par celle-ci
void _onMapCameraMove(CameraPosition position) {
  // On met juste à jour les coordonnées locales (Gratuit)
  _currentPinLocation = lt.LatLng(position.target.latitude, position.target.longitude);
  
  // Optionnel : On peut mettre un texte générique pour dire que ça a bougé
  if (_currentPinAddress != null) {
     setState(() {
       _currentPinAddress = null; // Cela affichera "Position sur la carte" dans l'UI
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

// Remplacez votre fonction _confirmMapSelection par celle-ci
Future<void> _confirmMapSelection() async {
  final l10n = AppLocalizations.of(context);
  if (l10n == null) return;

  // 1. Démarrer le chargement (Feedback visuel important)
  setState(() => _isLoading = true);

  try {
    // 2. C'est ICI qu'on paie l'appel API (Une seule fois !)
    // On utilise votre utilitaire existant
    String? finalAddress = await LocationUtils.reverseGeocode(
      _currentPinLocation, 
      context, 
      _geocodeCache
    );

    // Fallback si l'API échoue ou ne trouve rien
    finalAddress ??= "${_currentPinLocation.latitude.toStringAsFixed(5)}, ${_currentPinLocation.longitude.toStringAsFixed(5)}";

    if (!mounted) return;

    // 3. Animation de confirmation
    HapticFeedback.mediumImpact();
    await _selectController.forward(); // Attendre la fin de l'animation

    // 4. Renvoyer le résultat
    final resultPlace = GooglePlacePrediction(
      placeId: null, // Pas de placeId pour une coordonnée manuelle
      description: finalAddress,
      lat: _currentPinLocation.latitude,
      lng: _currentPinLocation.longitude,
    );
    
    Navigator.pop(context, resultPlace);
    // On renouvelle le token pour la prochaine fois

  } catch (e) {
    // Gestion d'erreur basique
    if (mounted) {
       ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur de connexion: $e")),
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

  // --- UI CONSTRUCTION ---

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
          // Add shadow to back button in map view so it's visible over map
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
              ? RotatingDotsIndicator()
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
      // 1. Map Layer
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
        onCameraMove: _onMapCameraMove, // Ne coûte plus rien maintenant
        myLocationEnabled: true,
        myLocationButtonEnabled: false,
        compassEnabled: true,
        zoomControlsEnabled: false,
      ),

      // 2. Animated Pin Layer
      Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Pulse Ring (Animation)
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
            // Pin Icon + Shadow
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
                    child: Icon(Icons.location_on, color: colorScheme.primary, size: 48.0),
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

      // 3. Bottom Control Panel (Interface corrigée)
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
            mainAxisSize: MainAxisSize.min, // Important pour éviter l'overflow
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.chooseLoadingPosition, // "Choisir le point de prise en charge"
                style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              
              // Affichage de l'adresse (ou texte générique)
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
                        // Affiche "Position sur la carte" tant qu'on n'a pas confirmé
                        _currentPinAddress ?? "Position sélectionnée sur la carte",
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
              
              // Boutons d'action (Retour / Confirmer)
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
                      // Si c'est en chargement, on désactive le bouton
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
}}