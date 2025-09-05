import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart' as latlong;

// DropOffData model with toFirestore and fromFirestore
class DropOffData {
  final String? customerName;
  final String? customerPhoneNumber;
  final latlong.LatLng destination;
  final String destinationName;
  final bool? isDelivered;

  DropOffData({
    this.customerName,
    this.customerPhoneNumber,
    required this.destination,
    required this.destinationName,
    this.isDelivered,
  });

  // Convert DropOffData to Firestore document format
  Map<String, dynamic> toFirestore() {
    return {
      'name': customerName,
      'phoneNumber': customerPhoneNumber,
      'destination': {
        'latitude': destination.latitude,
        'longitude': destination.longitude,
      },
      'destinationName': destinationName,
      'isdelivered': isDelivered,
    };
  }

  // Convert Firestore document to DropOffData
  factory DropOffData.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return DropOffData(
      customerName: data['name'] as String?,
      customerPhoneNumber: data['phoneNumber'] as String?,
      destination: latlong.LatLng(
        (data['destination']['latitude'] as num).toDouble(),
        (data['destination']['longitude'] as num).toDouble(),
      ),
      destinationName: data['destinationName'] as String,
      isDelivered: data['isdelivered'] as bool?,
    );
  }
}

// Fetch a stop document from Firestore by ID
Future<DocumentSnapshot> getStopsFromFirebasebyId(String id) async {
  if (id.isEmpty) {
    throw Exception('Invalid stop ID: ID cannot be empty');
  }
  return await FirebaseFirestore.instance.collection('stops').doc(id).get();
}