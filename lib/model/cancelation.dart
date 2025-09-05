import 'package:cloud_firestore/cloud_firestore.dart';

class Cancelation {
 String idDeal;
 String cancelledBy;
  Timestamp? time;
 String? reason;


  Cancelation({
   required this.cancelledBy,
   required this.idDeal,
    this.reason,

   
   });

 
  Map<String, dynamic> toJson() {
    return {
      'cancelledBy': cancelledBy,
      'idDeal': idDeal,
      'reason': reason,
      'time': Timestamp.now(),

    };
  }
}