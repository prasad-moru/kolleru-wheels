import '../../core/constants/villages.dart';
import 'driver_verification.dart';
import 'vehicle_type.dart';

class AdminAnalyticsModel {
  const AdminAnalyticsModel({
    required this.totalUsers,
    required this.activeFarmers,
    required this.registeredDrivers,
    required this.activeDrivers,
    required this.callsPlacedToday,
    required this.activeLoads,
    required this.mandals,
    required this.recentCalls,
    required this.liveLoads,
    this.fleet = const [],
  });

  final List<AdminFleetDriver> fleet;
  List<AdminFleetDriver> get pendingDrivers => fleet
      .where((d) => d.verification == DriverVerification.pending)
      .toList(growable: false);

  final int totalUsers;
  final int activeFarmers;
  final int registeredDrivers;
  final int activeDrivers;
  final int callsPlacedToday;
  final int activeLoads;
  final List<MandalActivity> mandals;
  final List<AdminCallLogItem> recentCalls;
  final List<AdminLoadFeedItem> liveLoads;

  factory AdminAnalyticsModel.aggregate({
    required List<Map<String, dynamic>> profiles,
    required List<Map<String, dynamic>> drivers,
    required List<Map<String, dynamic>> callsToday,
    required List<Map<String, dynamic>> recentTelemetry,
    required List<Map<String, dynamic>> loads,
    required DateTime now,
  }) {
    final callCounts = <String, int>{};
    final profileMandalByPhone = <String, String>{};
    final driverCounts = <String, int>{};
    final activeDriverCounts = <String, int>{};
    final farmerCounts = <String, int>{};

    String? mandalForVillage(Object? villageId) {
      for (final mandal in KolleruVillages.mandals) {
        if (mandal.villages.any((village) => village.id == villageId)) {
          return mandal.id;
        }
      }
      return null;
    }

    for (final profile in profiles) {
      final phone = _phoneDigits(profile['phone'] as String? ?? '');
      final mandal = mandalForVillage(profile['village_id']);
      if (phone.isNotEmpty && mandal != null) {
        profileMandalByPhone[phone] = mandal;
      }
      if (profile['role'] == 'shipper' && mandal != null) {
        farmerCounts.update(mandal, (value) => value + 1, ifAbsent: () => 1);
      }
    }

    for (final driver in drivers) {
      final mandal = mandalForVillage(driver['base_village_id']);
      if (mandal != null) {
        driverCounts.update(mandal, (value) => value + 1, ifAbsent: () => 1);
        if (driver['is_available'] == true &&
            DriverVerification.fromValue(driver['verification_status']) ==
                DriverVerification.approved) {
          activeDriverCounts.update(
            mandal,
            (value) => value + 1,
            ifAbsent: () => 1,
          );
        }
      }
    }

    for (final call in callsToday) {
      final phone = _phoneDigits(call['caller_phone'] as String? ?? '');
      final mandal = profileMandalByPhone[phone];
      if (mandal != null) {
        callCounts.update(mandal, (value) => value + 1, ifAbsent: () => 1);
      }
    }

    final mandalOrder = [
      'akividu',
      'kaikaluru',
      'bhimavaram',
      'mandavalli',
      'kalidindi',
    ];
    final mandals =
        KolleruVillages.mandals
            .where((mandal) => mandalOrder.contains(mandal.id))
            .toList()
          ..sort(
            (a, b) =>
                mandalOrder.indexOf(a.id).compareTo(mandalOrder.indexOf(b.id)),
          );
    final mandalActivity = mandals
        .map(
          (mandal) => MandalActivity(
            id: mandal.id,
            name: mandal.name,
            teluguName: mandal.teluguName,
            driverCount: driverCounts[mandal.id] ?? 0,
            activeDriverCount: activeDriverCounts[mandal.id] ?? 0,
            farmerCount: farmerCounts[mandal.id] ?? 0,
            callTally: callCounts[mandal.id] ?? 0,
          ),
        )
        .toList(growable: false);

    final activeRows =
        loads.where((row) {
          if (row['is_closed'] == true) return false;
          final createdAt = DateTime.tryParse(
            row['created_at'] as String? ?? '',
          );
          return createdAt != null &&
              !createdAt.isAfter(now) &&
              now.isBefore(createdAt.add(const Duration(minutes: 30)));
        }).toList()..sort(
          (a, b) =>
              b['created_at'].toString().compareTo(a['created_at'].toString()),
        );

    final activeFarmerPhones = <String>{
      for (final call in callsToday)
        if ((call['caller_phone'] as String?)?.isNotEmpty == true)
          _phoneDigits(call['caller_phone'] as String),
      for (final load in activeRows)
        if ((load['poster_phone'] as String?)?.isNotEmpty == true)
          _phoneDigits(load['poster_phone'] as String),
    };
    final fleet = drivers.map(AdminFleetDriver.fromRow).toList(growable: false);
    final calls = recentTelemetry
        .map((row) {
          final originId =
              profileMandalByPhone[_phoneDigits(
                row['caller_phone'] as String? ?? '',
              )];
          final target = fleet
              .where(
                (driver) =>
                    _phoneDigits(driver.phone) ==
                    _phoneDigits(row['receiver_phone'] as String? ?? ''),
              )
              .firstOrNull;
          final context = row['context_note'] as String? ?? '';
          final linkedLoad = context.startsWith('urgent_load:')
              ? loads
                    .where(
                      (load) =>
                          load['id'] ==
                          context.substring('urgent_load:'.length),
                    )
                    .firstOrNull
              : null;
          return AdminCallLogItem.fromRow({
            ...row,
            'load_category': linkedLoad?['material_type'],
            'origin_mandal_id': originId,
            'driver_name': target?.name,
            'vehicle_type': target?.vehicleType.name,
          });
        })
        .toList(growable: false);

    return AdminAnalyticsModel(
      fleet: fleet,
      totalUsers: profiles.length,
      activeFarmers: profiles
          .where(
            (row) =>
                row['role'] == 'shipper' &&
                activeFarmerPhones.contains(
                  _phoneDigits(row['phone'] as String? ?? ''),
                ),
          )
          .length,
      registeredDrivers: drivers.length,
      activeDrivers: drivers
          .where(
            (row) =>
                row['is_available'] == true &&
                DriverVerification.fromValue(row['verification_status']) ==
                    DriverVerification.approved,
          )
          .length,
      callsPlacedToday: callsToday.length,
      activeLoads: activeRows.length,
      mandals: mandalActivity,
      recentCalls: calls,
      liveLoads: activeRows
          .map(AdminLoadFeedItem.fromRow)
          .toList(growable: false),
    );
  }

  static String maskPhone(String? phone) {
    if (phone == null || phone.trim().isEmpty) return 'Guest';
    final digits = _phoneDigits(phone);
    final national = digits.startsWith('91') && digits.length == 12
        ? digits.substring(2)
        : digits;
    if (national.length < 7) return '***';
    return '+91 ${national.substring(0, 4)}***${national.substring(national.length - 3)}';
  }

  static String _phoneDigits(String value) =>
      value.replaceAll(RegExp(r'\D'), '');
}

class MandalActivity {
  const MandalActivity({
    required this.id,
    required this.name,
    required this.teluguName,
    required this.driverCount,
    required this.farmerCount,
    required this.callTally,
    this.activeDriverCount = 0,
  });

  final String id;
  final String name;
  final String teluguName;
  final int driverCount;
  final int farmerCount;
  final int callTally;
  final int activeDriverCount;
}

class AdminCallLogItem {
  const AdminCallLogItem({
    required this.createdAt,
    required this.callerRole,
    required this.callerPhone,
    required this.receiverPhone,
    required this.contextNote,
    this.originMandalId,
    this.loadCategory,
    this.driverName,
    this.vehicleType,
  });

  final DateTime createdAt;
  final String callerRole;
  final String callerPhone;
  final String receiverPhone;
  final String contextNote;
  final String? originMandalId;
  final String? loadCategory;
  final String? driverName;
  final VehicleType? vehicleType;

  factory AdminCallLogItem.fromRow(Map<String, dynamic> row) =>
      AdminCallLogItem(
        createdAt:
            DateTime.tryParse(row['created_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        callerRole: row['caller_role'] as String? ?? 'guest',
        callerPhone: AdminAnalyticsModel.maskPhone(
          row['caller_phone'] as String?,
        ),
        receiverPhone: AdminAnalyticsModel.maskPhone(
          row['receiver_phone'] as String?,
        ),
        contextNote: row['context_note'] as String? ?? '',
        originMandalId: row['origin_mandal_id'] as String?,
        loadCategory: row['load_category'] as String?,
        driverName: row['driver_name'] as String?,
        vehicleType: VehicleType.values
            .where((v) => v.name == row['vehicle_type'])
            .firstOrNull,
      );
}

class AdminLoadFeedItem {
  const AdminLoadFeedItem({
    required this.id,
    required this.pickupLocation,
    required this.destination,
    required this.category,
    required this.createdAt,
    required this.expiresAt,
  });

  final String id;
  final String pickupLocation;
  final String destination;
  final String category;
  final DateTime createdAt;
  final DateTime expiresAt;

  factory AdminLoadFeedItem.fromRow(Map<String, dynamic> row) {
    final created =
        DateTime.tryParse(row['created_at'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final village = KolleruVillages.find(row['to_village_id'] as String?);
    final mandal = village == null
        ? null
        : KolleruVillages.mandals.firstWhere(
            (item) => item.villages.any((entry) => entry.id == village.id),
          );
    final rawPickup = row['from_location'] as String? ?? 'Unknown pickup';
    final pickupKey = rawPickup.trim().toLowerCase();
    String pickupLocation = rawPickup;
    for (final candidate in KolleruVillages.all) {
      if (candidate.id == pickupKey ||
          candidate.name.toLowerCase() == pickupKey ||
          pickupKey.contains(candidate.name.toLowerCase()) ||
          pickupKey.contains(candidate.id) ||
          candidate.teluguName == rawPickup.trim()) {
        final originMandal = KolleruVillages.mandals.firstWhere(
          (item) => item.villages.any((entry) => entry.id == candidate.id),
        );
        pickupLocation = '${originMandal.name} · ${candidate.name}';
        break;
      }
    }
    return AdminLoadFeedItem(
      id: row['id']?.toString() ?? '',
      pickupLocation: pickupLocation,
      destination: village == null
          ? 'Unknown destination'
          : '${mandal?.name ?? ''} · ${village.name}',
      category: row['material_type'] as String? ?? 'Other cargo',
      createdAt: created,
      expiresAt: created.add(const Duration(minutes: 30)),
    );
  }
}

/// Read-only admin projection; status is changed only through the review RPC.
class AdminFleetDriver {
  const AdminFleetDriver({
    required this.id,
    required this.name,
    required this.phone,
    required this.vehicleType,
    required this.vehicleNumber,
    required this.capacityTons,
    required this.verification,
    required this.isAvailable,
    this.mandal,
  });
  final String id;
  final String name;
  final String phone;
  final VehicleType vehicleType;
  final String vehicleNumber;
  final double capacityTons;
  final DriverVerification verification;
  final bool isAvailable;
  final Mandal? mandal;

  factory AdminFleetDriver.fromRow(Map<String, dynamic> row) =>
      AdminFleetDriver(
        id: row['id']?.toString() ?? '',
        name: row['name'] as String? ?? '',
        phone: row['phone'] as String? ?? '',
        vehicleType:
            VehicleType.values
                .where((v) => v.name == row['vehicle_type'])
                .firstOrNull ??
            VehicleType.boleroPickup,
        vehicleNumber: row['vehicle_number'] as String? ?? '',
        capacityTons: (row['capacity_tons'] as num?)?.toDouble() ?? 0,
        verification: DriverVerification.fromValue(row['verification_status']),
        isAvailable: row['is_available'] == true,
        mandal: KolleruVillages.mandals
            .where((m) => m.villages.any((v) => v.id == row['base_village_id']))
            .firstOrNull,
      );
}
