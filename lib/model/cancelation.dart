import 'package:cloud_firestore/cloud_firestore.dart';

class Cancelation {
 String idDeal;
 String cancelledBy;
  Timestamp? time;
 int? points;


  Cancelation({
   required this.cancelledBy,
   required this.idDeal,
    this.points
,

   
   });

 
  Map<String, dynamic> toJson() {
    return {
      'cancelledBy': cancelledBy,
      'idDeal': idDeal,
      'reason': points,
      'time': Timestamp.now(),

    };
  }
}