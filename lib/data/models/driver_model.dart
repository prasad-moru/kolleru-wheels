import '../../core/constants/villages.dart';
import 'vehicle_type.dart';

class DriverModel {
  const DriverModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.village,
    required this.currentSpot,
    required this.vehicleType,
    required this.capacity,
    required this.isAvailable,
    this.isDemo = false,
    this.vehicleNumber = '',
    this.specializations = const [],
    this.currentSpotVillageId,
    this.capacityTons,
    this.avatarUrl,
    this.isPhoneVerified = false,
    this.cardStyle = 'classic_delta',
  });
  final String cardStyle;
  final String id;
  final String name;
  final String phone;
  final Village village;
  final String currentSpot;
  final VehicleType vehicleType;
  final String capacity;
  final bool isAvailable;
  final bool isDemo;
  final String vehicleNumber;
  final List<String> specializations;
  final String? currentSpotVillageId;
  final double? capacityTons;
  final String? avatarUrl;
  final bool isPhoneVerified;
  DriverModel copyWith({String? cardStyle, String? avatarUrl}) => DriverModel(
    id: id,
    name: name,
    phone: phone,
    village: village,
    currentSpot: currentSpot,
    vehicleType: vehicleType,
    capacity: capacity,
    isAvailable: isAvailable,
    isDemo: isDemo,
    vehicleNumber: vehicleNumber,
    specializations: specializations,
    currentSpotVillageId: currentSpotVillageId,
    capacityTons: capacityTons,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    isPhoneVerified: isPhoneVerified,
    cardStyle: cardStyle ?? this.cardStyle,
  );
}
