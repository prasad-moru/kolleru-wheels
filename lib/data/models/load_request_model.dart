import '../models/vehicle_type.dart';
import '../../core/constants/villages.dart';

enum LoadRequestStatus { open, closed }

class LoadRequestModel {
  LoadRequestModel({
    required this.id,
    required this.posterName,
    required this.posterPhone,
    required this.fromLocation,
    String? toVillageId,
    Village? toVillage,
    required this.materialType,
    required this.vehicleTypeNeeded,
    required this.createdAt,
    LoadRequestStatus status = LoadRequestStatus.open,
    bool? isClosed,
  }) : toVillageId =
           toVillage?.id ??
           toVillageId ??
           (throw ArgumentError('A destination village is required')),
       status = isClosed == null
           ? status
           : isClosed
           ? LoadRequestStatus.closed
           : LoadRequestStatus.open;
  static const lifetime = Duration(minutes: 30);
  final String id;
  final String posterName;
  final String posterPhone;
  final String fromLocation;
  final String toVillageId;
  final String materialType;
  final VehicleType? vehicleTypeNeeded; // null means any vehicle.
  final DateTime createdAt;
  final LoadRequestStatus status;
  Village get toVillage => KolleruVillages.find(toVillageId)!;
  bool get isClosed => status == LoadRequestStatus.closed;
  DateTime get expiresAt => createdAt.add(lifetime);
  bool isActiveAt(DateTime now) =>
      !isClosed && !createdAt.isAfter(now) && now.isBefore(expiresAt);
  LoadRequestModel close() => LoadRequestModel(
    id: id,
    posterName: posterName,
    posterPhone: posterPhone,
    fromLocation: fromLocation,
    toVillageId: toVillageId,
    materialType: materialType,
    vehicleTypeNeeded: vehicleTypeNeeded,
    createdAt: createdAt,
    status: LoadRequestStatus.closed,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'posterName': posterName,
    'posterPhone': posterPhone,
    'fromLocation': fromLocation,
    'toVillageId': toVillageId,
    'toVillage': toVillageId,
    'materialType': materialType,
    'vehicleTypeNeeded': vehicleTypeNeeded?.name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'status': status.name,
    'isClosed': isClosed,
  };
  factory LoadRequestModel.fromJson(Map<String, dynamic> json) {
    final request = LoadRequestModel(
      id: json['id'] as String,
      posterName: json['posterName'] as String,
      posterPhone: json['posterPhone'] as String,
      fromLocation: json['fromLocation'] as String,
      toVillageId: (json['toVillage'] ?? json['toVillageId']) as String,
      materialType: json['materialType'] as String,
      vehicleTypeNeeded: json['vehicleTypeNeeded'] == null
          ? null
          : VehicleType.values.byName(json['vehicleTypeNeeded'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      isClosed: json['isClosed'] as bool?,
      status: LoadRequestStatus.values.byName(
        (json['status'] ?? 'open') as String,
      ),
    );
    if (request.id.isEmpty ||
        request.posterName.trim().isEmpty ||
        request.posterPhone.isEmpty ||
        request.fromLocation.trim().isEmpty ||
        request.materialType.isEmpty ||
        KolleruVillages.find(request.toVillageId) == null) {
      throw const FormatException('Invalid load request');
    }
    return request;
  }
}
