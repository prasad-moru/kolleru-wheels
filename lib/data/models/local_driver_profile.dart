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
    this.avatarUrl,
    this.isPhoneVerified = false,
    this.cardStyle = 'classic_delta',
  }) : specializations = List.unmodifiable(specializations),
       currentSpotLabel = currentSpotLabel ?? currentSpotVillage.label;

  final String cardStyle;
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
  final String? avatarUrl;
  final bool isPhoneVerified;

  factory LocalDriverProfile.fromDriverModel(DriverModel driver) {
    final spot =
        KolleruVillages.find(driver.currentSpotVillageId) ?? driver.village;
    final profile = LocalDriverProfile(
      id: driver.id,
      name: driver.name,
      phone: driver.phone,
      baseVillage: driver.village,
      currentSpotVillage: spot,
      currentSpotLabel: driver.currentSpot,
      vehicleType: driver.vehicleType,
      capacityTons: driver.capacityTons!,
      specializations: driver.specializations,
      vehicleNumber: driver.vehicleNumber,
      isAvailable: driver.isAvailable,
      avatarUrl: driver.avatarUrl,
      isPhoneVerified: driver.isPhoneVerified,
      cardStyle: driver.cardStyle,
    );
    return LocalDriverProfile.fromJson(profile.toJson());
  }

  LocalDriverProfile copyWith({
    String? cardStyle,
    bool? isAvailable,
    Village? currentSpotVillage,
    String? currentSpotLabel,
    String? avatarUrl,
    bool? isPhoneVerified,
  }) => LocalDriverProfile(
    cardStyle: cardStyle ?? this.cardStyle,
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
    avatarUrl: avatarUrl ?? this.avatarUrl,
    isPhoneVerified: isPhoneVerified ?? this.isPhoneVerified,
  );

  DriverModel toDriverModel() => DriverModel(
    cardStyle: cardStyle,
    id: id,
    name: name,
    phone: phone,
    village: baseVillage,
    currentSpot: currentSpotLabel,
    currentSpotVillageId: currentSpotVillage.id,
    vehicleType: vehicleType,
    capacity: '$capacityTons టన్నులు / $capacityTons Tons',
    capacityTons: capacityTons,
    isAvailable: isAvailable,
    vehicleNumber: vehicleNumber,
    specializations: specializations,
    avatarUrl: avatarUrl,
    isPhoneVerified: isPhoneVerified,
  );

  Map<String, Object?> toJson() => {
    'cardStyle': cardStyle,
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
    'avatarUrl': avatarUrl,
    'isPhoneVerified': isPhoneVerified,
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
      cardStyle: json['cardStyle'] as String? ?? 'classic_delta',
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
      avatarUrl: json['avatarUrl'] as String?,
      isPhoneVerified: json['isPhoneVerified'] as bool? ?? false,
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
