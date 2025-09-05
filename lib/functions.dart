import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as lt;

class Maptools {





  Future<double?> getMapboxRoadDistanceMeters(
  lt.LatLng origin,
  lt.LatLng destination,
  
) async {
  

  // Profil de routage : 'driving' est le plus courant pour la voiture.
  // D'autres profils existent : 'walking', 'cycling', 'driving-traffic'.
  final String profile = 'driving';
   
final  String token =  "pk.eyJ1IjoibW91dmltYXAiLCJhIjoiY201cXpxam9pMDU1ZjJpcXVmaG4yZW02NCJ9.W1JxwKjggsdRwtyBW2G1fw";
  // Construction de l'URL de l'API Mapbox Directions
  final String url = 'https://api.mapbox.com/directions/v5/mapbox/$profile/'
      '${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}'
      '?alternatives=false'      // Ne pas chercher d'itinéraires alternatifs
      '&geometries=polyline'     // Demander la géométrie de l'itinéraire (nécessaire pour certains détails)
      '&steps=false'             // Ne pas inclure les étapes détaillées
      '&annotations=distance'    // Demander explicitement l'annotation de distance
      '&access_token=$token';

  try {
    print('DEBUG: Appel de l\'API Mapbox Directions pour la distance: $url');
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(response.body);

      // Vérifier si des itinéraires ont été trouvés et si la distance est disponible
      if (data['routes'] != null && data['routes'].isNotEmpty) {
        final double distance = data['routes'][0]['distance']; // Distance en mètres
        print('DEBUG: Distance API Mapbox reçue: $distance mètres');
        return distance;
      } else {
        print('DEBUG: API Mapbox Directions: Aucun itinéraire trouvé ou distance non disponible.');
        return null;
      }
    } else {
      print('ERREUR: API Mapbox Directions a retourné un statut ${response.statusCode}: ${response.body}');
      return null;
    }
  } catch (e) {
    print('ERREUR: Erreur lors de l\'appel de l\'API Mapbox Directions: $e');
    return null;
  }
}

// pour la simplicitée des retour des valeurs from firebase 
 Future<dynamic> getFieldValue({
    required String collectionName,
    required String documentId,
    required String fieldName,
  }) async {
    try {
      final docSnapshot = await FirebaseFirestore.instance
          .collection(collectionName)
          .doc(documentId)
          .get();

      if (docSnapshot.exists) {
        final data = docSnapshot.data() as Map<String, dynamic>;
        return data[fieldName];
      }
      return null;
    } catch (e) {
      print("Erreur dans ShnellDealsOrders.getFieldValue: $e");
      return null;
    }
  }
  

   Future<bool> updateFieldValue({
  required String collectionName,
  required String documentId,
  required String fieldName,
  required dynamic newValue
}) async {
  try {
    await FirebaseFirestore.instance
        .collection(collectionName)
        .doc(documentId)
        .update({fieldName: newValue});

    return true; // Succès
  } catch (e) {
    print("Erreur dans updateFieldValue: $e");
    return false; // Échec
  }
}

}
  

