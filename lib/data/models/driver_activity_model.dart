import '../../core/constants/villages.dart';

class DriverInquiry {
  const DriverInquiry({
    required this.id,
    required this.createdAt,
    this.callerVillageId,
    this.location,
    this.loadDetail,
  });
  final String id;
  final DateTime createdAt;
  final String? callerVillageId;
  final String? location;
  final String? loadDetail;
  Village? get village => KolleruVillages.find(callerVillageId);

  factory DriverInquiry.fromJson(Map<String, dynamic> json) => DriverInquiry(
    id: json['id'] as String,
    createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
    callerVillageId: json['caller_village_id'] as String?,
    location: json['location'] as String?,
    loadDetail: json['load_detail'] as String?,
  );
}

class DriverActivity {
  const DriverActivity({required this.callsToday, required this.recentCalls});
  final int callsToday;
  final List<DriverInquiry> recentCalls;

  factory DriverActivity.fromJson(Map<String, dynamic> json) {
    final count = (json['calls_today'] as num).toInt();
    if (count < 0) throw const FormatException('Invalid inquiry count');
    return DriverActivity(
      callsToday: count,
      recentCalls: List.unmodifiable(
        (json['recent_calls'] as List).map(
          (row) =>
              DriverInquiry.fromJson(Map<String, dynamic>.from(row as Map)),
        ),
      ),
    );
  }
}
