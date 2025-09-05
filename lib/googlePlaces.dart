class GooglePlacePrediction {
  final String? placeId;
  final String? description;
  final double? lat;
  final double? lng;

  GooglePlacePrediction({this.placeId, this.description, this.lat, this.lng});

  factory GooglePlacePrediction.fromJson(Map<String, dynamic> json) {
    return GooglePlacePrediction(
      placeId: json['place_id'],
      description: json['description'],
    );
  }
}