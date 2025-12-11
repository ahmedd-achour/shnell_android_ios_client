import 'package:cloud_firestore/cloud_firestore.dart';

class Deals {
  String idOrder;
  String idDriver;
  String idUser;
  String idVehicle;
  String status;
  DateTime? timestamp; // Added to allow sorting history by date

  Deals({
    required this.idDriver,
    required this.idOrder,
    required this.idUser,
    required this.idVehicle,
    required this.status,
    this.timestamp,
  });

  // --- THE MISSING PART ---
  factory Deals.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    return Deals(
      idDriver: data['idDriver'] ?? '',
      idOrder: data['idOrder'] ?? '',
      idUser: data['idUser'] ?? '',
      idVehicle: data['idVehicle'] ?? '',
      status: data['status'] ?? 'pending',
      // Safe conversion from Firestore Timestamp to Dart DateTime
      timestamp: (data['timestamp'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'idDriver': idDriver,
      'idOrder': idOrder,
      'idUser': idUser,
      'idVehicle': idVehicle,
      'status': status,
      // Automatically sets server time when you upload
      'timestamp': FieldValue.serverTimestamp(), 
    };
  }
}