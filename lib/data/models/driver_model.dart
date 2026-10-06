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
  });
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
}
