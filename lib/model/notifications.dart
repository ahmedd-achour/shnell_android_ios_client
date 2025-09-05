class Notifications {
  final String fcmToken;
  final String userId;


  Notifications({
    required this.fcmToken,
    required this.userId
  });


  toJson(){
    return {
      'userId' : userId,
      'fcmToken' : fcmToken
    };
  }
  
}