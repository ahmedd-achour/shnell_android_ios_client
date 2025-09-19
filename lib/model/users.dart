
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
    };
  }
}
