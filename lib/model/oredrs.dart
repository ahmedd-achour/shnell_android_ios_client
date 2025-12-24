import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart' as lt;

class Orders {
  double price;
  double distance;
  String namePickUp;
  lt.LatLng pickUpLocation;
  List<String> stops; // List of stop IDs
  String vehicleType;
  String userId;
  bool isAcepted;
  String id;
  Timestamp? scheduleAt;

  Orders({
    required this.price,
    required this.distance,
    required this.namePickUp,
    required this.pickUpLocation,
    required this.stops,
    required this.id,
    required this.vehicleType,
    required this.userId,
    this.isAcepted = false,
    this.scheduleAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'userID': FirebaseAuth.instance.currentUser!.uid,
      'price': price,
      'distance': distance,
      'namePickUp': namePickUp,
      'id' : id,
      'pickUpLocation': pickUpLocation.toJson(),
      'stops': stops, // Stored as a Firestore array
      'timestamp': Timestamp.now(),
      'vehicleType': vehicleType,
      'isAcepted': isAcepted,
      'scheduleAt': scheduleAt,
    };
  }

  factory Orders.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    // Parse pickup location
    Map<String, dynamic> pickUpData = data['pickUpLocation'];
    lt.LatLng pickUpLoc = lt.LatLng(
      pickUpData['coordinates'][1],
      pickUpData['coordinates'][0],
    );

    return Orders(
      userId: data['userID'],
      price: (data['price'] as num).toDouble(),
      distance: (data['distance'] as num).toDouble(),
      namePickUp: data['namePickUp'],
      pickUpLocation: pickUpLoc,
      id: data['id'],
      stops: List<String>.from(data['stops'] ?? []),
      vehicleType: data['vehicleType'],
      isAcepted: data['isAcepted'] ?? false,
      scheduleAt: data['scheduleAt']
    );
  }
}