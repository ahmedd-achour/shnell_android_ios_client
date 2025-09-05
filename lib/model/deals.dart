import 'package:cloud_firestore/cloud_firestore.dart';

class Deals {
String idOrder;
String idDriver;
String idUser;
String idVehicle;
String status;

  Deals({
    required this.idDriver,
    required this.idOrder,
    required this.idUser,
    required this.idVehicle,
    required this.status,

  });

  
  Map<String, dynamic> toJson() {
    return {
      'idDriver' :idDriver,
      'idOrder' :idOrder,
      'idUser' :idUser,
      'idVehicle' :idVehicle,
      'status' : status,
      'timestamp': Timestamp.now(),
    
    };
  }
}