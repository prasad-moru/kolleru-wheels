import '../../core/constants/villages.dart';

class LoadRequest {
  const LoadRequest({
    required this.id,
    required this.posterPhone,
    required this.fromVillage,
    required this.toVillage,
    required this.materialType,
    required this.createdAt,
  });
  final String id;
  final String posterPhone;
  final Village fromVillage;
  final Village toVillage;
  final String materialType;
  final DateTime createdAt;
}
