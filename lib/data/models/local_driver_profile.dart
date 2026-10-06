import '../../core/constants/villages.dart';
import 'driver_model.dart';
import 'vehicle_type.dart';

/// Persisted driver data uses stable village IDs and enum names.
class LocalDriverProfile {
  LocalDriverProfile({
    required this.id,
    required this.name,
    required this.phone,
    required this.baseVillage,
    required this.currentSpotVillage,
    required this.vehicleType,
    required this.capacityTons,
    required List<String> specializations,
    required this.vehicleNumber,
    required this.isAvailable,
    String? currentSpotLabel,
  }) : specializations = List.unmodifiable(specializations),
       currentSpotLabel = currentSpotLabel ?? currentSpotVillage.label;

  final String id;
  final String name;
  final String phone;
  final Village baseVillage;
  final Village currentSpotVillage;
  final String currentSpotLabel;
  final VehicleType vehicleType;
  final double capacityTons;
  final List<String> specializations;
  final String vehicleNumber;
  final bool isAvailable;

  LocalDriverProfile copyWith({
    bool? isAvailable,
    Village? currentSpotVillage,
    String? currentSpotLabel,
  }) => LocalDriverProfile(
    id: id,
    name: name,
    phone: phone,
    baseVillage: baseVillage,
    currentSpotVillage: currentSpotVillage ?? this.currentSpotVillage,
    currentSpotLabel:
        currentSpotLabel ??
        (currentSpotVillage == null
            ? this.currentSpotLabel
            : currentSpotVillage.label),
    vehicleType: vehicleType,
    capacityTons: capacityTons,
    specializations: specializations,
    vehicleNumber: vehicleNumber,
    isAvailable: isAvailable ?? this.isAvailable,
  );

  DriverModel toDriverModel() => DriverModel(
    id: id,
    name: name,
    phone: phone,
    village: baseVillage,
    currentSpot: currentSpotLabel,
    vehicleType: vehicleType,
    capacity: '$capacityTons టన్నులు / $capacityTons Tons',
    isAvailable: isAvailable,
    vehicleNumber: vehicleNumber,
    specializations: specializations,
  );

  Map<String, Object> toJson() => {
    'schemaVersion': 1,
    'id': id,
    'name': name,
    'phone': phone,
    'baseVillage': baseVillage.id,
    'currentSpotVillage': currentSpotVillage.id,
    'currentSpotLabel': currentSpotLabel,
    'vehicleType': vehicleType.name,
    'capacityTons': capacityTons,
    'specializations': specializations,
    'vehicleNumber': vehicleNumber,
    'isAvailable': isAvailable,
  };

  factory LocalDriverProfile.fromJson(Map<String, dynamic> json) {
    final base = KolleruVillages.find(json['baseVillage'] as String?);
    final spot = KolleruVillages.find(json['currentSpotVillage'] as String?);
    final capacity = (json['capacityTons'] as num).toDouble();
    if (json['schemaVersion'] != 1 ||
        base == null ||
        spot == null ||
        !capacity.isFinite ||
        capacity <= 0 ||
        capacity > 100) {
      throw const FormatException('Invalid driver profile');
    }
    final profile = LocalDriverProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String,
      baseVillage: base,
      currentSpotVillage: spot,
      currentSpotLabel: json['currentSpotLabel'] as String?,
      vehicleType: VehicleType.values.byName(json['vehicleType'] as String),
      capacityTons: capacity,
      specializations: (json['specializations'] as List).cast<String>(),
      vehicleNumber: json['vehicleNumber'] as String,
      isAvailable: json['isAvailable'] as bool,
    );
    if (profile.id.isEmpty ||
        profile.name.trim().isEmpty ||
        profile.phone.isEmpty ||
        profile.vehicleNumber.trim().isEmpty) {
      throw const FormatException('Incomplete driver profile');
    }
    return profile;
  }
}
