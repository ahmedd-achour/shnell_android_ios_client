import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shnell/VehiculeDetail.dart';
/// Country-specific service area
class CountryServiceArea {
  final String name;
  final bool active;
  final List<String> governorates;

  CountryServiceArea({
    required this.name,
    required this.active,
    required this.governorates,
  });

  factory CountryServiceArea.fromMap(String name, Map<String, dynamic> map) {
    return CountryServiceArea(
      name: name,
      active: map['active'] as bool? ?? false,
      governorates: List<String>.from(map['governorates'] ?? []),
    );
  }

  bool isGovernorateActive(String governorate) {
    return active && governorates.contains(governorate);
  }
}

/// Global configuration with multi-country support
class GlobalConfig {
  GlobalConfig._internal({
    required this.customerAppVersion,
    required this.driverAppVersion,
    required this.commissionPercentage,
    required this.stopFee,
    required this.customerAppUpdateLink,
    required this.driverAppUpdateLink,
    required this.vehicles,
    required this.serviceTypes,
    required this.countries,
    required this.serviceUnavailableMessages,
  });

  static GlobalConfig? _instance;

  static GlobalConfig get instance {
    if (_instance == null) {
      throw Exception('GlobalConfig not initialized. Call GlobalConfig.setGlobalConfig() first.');
    }
    return _instance!;
  }

  final String customerAppVersion;
  final String driverAppVersion;
  final double commissionPercentage;
  final double stopFee;
  final String customerAppUpdateLink;
  final String driverAppUpdateLink;

  final Map<String, VehicleSettings> vehicles;
  final List<ServiceType> serviceTypes;

  // NEW: Multi-country support
  final Map<String, CountryServiceArea> countries;
  final Map<String, String> serviceUnavailableMessages;

  /// One-time init
  static Future<void> setGlobalConfig() async {
    if (_instance != null) return;

    try {
      final firestore = FirebaseFirestore.instance;
      final results = await Future.wait([
        firestore.collection('settings').doc('config').get(),
        firestore.collection('settings').doc('vehicles').get(),
        firestore.collection('settings').doc('service_types').get(),
        firestore.collection('settings').doc('service_areas').get(),
      ]);

      final configDoc = results[0];
      final vehiclesDoc = results[1];
      final serviceTypesDoc = results[2];
      final areasDoc = results[3];

      if (!configDoc.exists || !vehiclesDoc.exists || !serviceTypesDoc.exists || !areasDoc.exists) {
        throw Exception('Missing config documents');
      }

      final configData = configDoc.data()  ?? {};
      final vehiclesData = vehiclesDoc.data()  ?? {};
      final serviceTypesData = serviceTypesDoc.data()  ?? {};
      final areasData = areasDoc.data()  ?? {};

      // Parse vehicles
      final Map<String, VehicleSettings> parsedVehicles = {};
      vehiclesData.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          parsedVehicles[key] = VehicleSettings.fromMap(value);
        }
      });

      // Parse service types
      final List<ServiceType> parsedServiceTypes = [];
      final rawTypes = serviceTypesData['types'];
      if (rawTypes is List) {
        for (var item in rawTypes) {
          if (item is Map<String, dynamic>) {
            parsedServiceTypes.add(ServiceType.fromMap(item));
          }
        }
      }

      // Parse countries
      final Map<String, CountryServiceArea> parsedCountries = {};
      final rawCountries = areasData['countries']  ?? {};
      rawCountries.forEach((countryName, countryData) {
        if (countryData is Map<String, dynamic>) {
          parsedCountries[countryName] = CountryServiceArea.fromMap(countryName, countryData);
        }
      });

      // Parse messages
      final Map<String, String> messages = Map<String, String>.from(areasData['messages'] ?? {});

      _instance = GlobalConfig._internal(
        customerAppVersion: configData['version_customer_app']?.toString() ?? '1.0.0',
        driverAppVersion: configData['version_driver_app']?.toString() ?? '1.0.0',
        commissionPercentage: (configData['commission_percentage'] ?? 0.15).toDouble(),
        stopFee: (configData['stop_fee'] ?? 0.4).toDouble(),
        customerAppUpdateLink: configData['update_link_customer_app']?.toString() ?? '',
        driverAppUpdateLink: configData['update_link_driver_app']?.toString() ?? '',
        vehicles: parsedVehicles,
        serviceTypes: parsedServiceTypes,
        countries: parsedCountries,
        serviceUnavailableMessages: messages,
      );

      debugPrint('GlobalConfig loaded: ${parsedCountries.keys.join(", ")} countries');
    } catch (e, st) {
      debugPrint('Config load failed: $e\n$st');
      rethrow;
    }
  }

  /// Check if a location (with governorate) is supported
  bool isLocationSupported(String country, String governorate) {
    final countryArea = countries[country];
    if (countryArea == null) return false;
    return countryArea.isGovernorateActive(governorate);
  }

  String getServiceUnavailableMessage(String locale) {
    return serviceUnavailableMessages[locale] ??
        serviceUnavailableMessages['en'] ??
        "Service not available in your area yet.";
  }


}