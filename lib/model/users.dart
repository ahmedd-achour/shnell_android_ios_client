
class shnellUsers {
  String email;
  String name;
  String phone;
  String role;
  String? fcmToken;
  double? balance;
  String? vehicleType;
  String? vehicleId;
  String? matVehicle;
  bool? isActive;
  String? profileImage;
  bool darkMode;

  shnellUsers({
    required this.email,
    required this.name,
    required this.phone,
    required this.role,
    this.fcmToken,
    
    this.balance,
    this.vehicleType,
    this.vehicleId,
    this.matVehicle,
    this.profileImage,
    this.isActive = false,
    this.darkMode = true,
  });

  factory shnellUsers.fromJson(Map<String, dynamic> json) {
    return shnellUsers(
      email: json['email'],
      name: json['name'],
      phone: json['phone'],
      role: json['role'],
      fcmToken: json['fcmToken'],
      balance: (json['balance'] ?? 0).toDouble(),
      vehicleType: json['vehicleType'],
      vehicleId: json['vehicleId'],
      matVehicle: json['matVehicle'],
      profileImage: json['profileImage'],
      isActive: json['isActive'] ?? false,
      darkMode: json['darkMode'] ?? true,


    );
  }

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'name': name,
      'phone': phone,
      'role': role,
      'fcmToken': fcmToken,
      'balance': balance,
      'vehicleType': vehicleType,
      'vehicleId': vehicleId,
      'matVehicle': matVehicle,
      'isActive': false,
      'language': 'fr', // Default language
      'darkMode': darkMode,

      
      'profileImage': profileImage ??
          'https://firebasestorage.googleapis.com/v0/b/shnell-393a6.appspot.com/o/default.jpeg?alt=media&token=b4fed130-bb4b-4a7f-b5fe-3fba23b8f035',
    };
  }
}
