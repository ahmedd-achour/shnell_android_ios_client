import 'package:cloud_firestore/cloud_firestore.dart';

class Rating {
String userId;
int rating;
String driverRated;

  Rating({
    required this.userId,
    required this.rating,
    required  this.driverRated,
  });



  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'rating': rating,
      'time': Timestamp.now(),
      'driverId' : driverRated
    
    };
  }
}