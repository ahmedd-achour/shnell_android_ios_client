import 'package:cloud_firestore/cloud_firestore.dart';

class Rating {
String userId;
int rating;
String? additionalInfos;

  Rating({
    required this.userId,
    required this.rating,
     String? additionalInfos,
    

  });



  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'rating': rating,
      'time': Timestamp.now(),
      'additionalInfos' : additionalInfos
    
    };
  }
}