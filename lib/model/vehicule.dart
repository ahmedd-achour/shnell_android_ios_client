class Vehicle {
 String carteGriseFront;
 String carteGriseBack;
 String carteIdentityFront;
 String carteIdentityBack;
 String cin;
 String matVehicle;
 String idDriver;
 double maxWeight;
 double maxVolume;
 String type;
 String vehicleImage;


  Vehicle({
    required this.carteGriseFront,
    required this.carteGriseBack,
    required this.carteIdentityFront ,
    required this.carteIdentityBack,
    required this.cin,
    required this.idDriver,
    required this.matVehicle,
    required this.maxWeight,
    required this.maxVolume,
    required this.type ,
    required this.vehicleImage,
  });



  Map<String, dynamic> toJson() {
    return {
      'carteGriseFront': carteGriseFront,
      'carteGriseBack': carteGriseBack,
      'carteIdentityFront': carteIdentityFront,
      'carteIdentityBack': carteIdentityBack,
      'cin': cin,
      'idDriver': idDriver,
      'matVehicle': matVehicle,
      'maxWeight': maxWeight,
      'maxVolume': maxVolume,
      'type' : type,
      'isAdminApproved': false,
      'vehicleImage' : vehicleImage
    };
  }
}