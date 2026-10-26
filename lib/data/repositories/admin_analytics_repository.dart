import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/supabase_config.dart';
import '../models/admin_analytics_model.dart';
import '../models/driver_verification.dart';
import 'auth_repository.dart';

class AdminAnalyticsRepository {
  AdminAnalyticsRepository({SupabaseClient? client, DateTime Function()? now})
    : _client = client ?? SupabaseConfig.client,
      _now = now ?? DateTime.now;

  static final instance = AdminAnalyticsRepository();
  final SupabaseClient? _client;
  final DateTime Function() _now;

  Future<AdminAnalyticsModel> fetchSnapshot(AuthRepository auth) async {
    final client = _client;
    if (client == null || !await auth.isLiveAdmin()) {
      throw StateError('Admin analytics requires a live admin session');
    }

    final now = _now().toUtc();
    const indiaOffset = Duration(hours: 5, minutes: 30);
    final indiaNow = now.add(indiaOffset);
    final dayStart = DateTime.utc(
      indiaNow.year,
      indiaNow.month,
      indiaNow.day,
    ).subtract(indiaOffset);
    final dayEnd = dayStart.add(const Duration(days: 1));

    final results = await Future.wait<Object>([
      client
          .from('user_profiles')
          .select('phone,role,village_id')
          .then((rows) => rows),
      client
          .from('drivers')
          .select(
            'id,name,phone,base_village_id,vehicle_type,vehicle_number,capacity_tons,is_available,verification_status',
          )
          .then((rows) => rows),
      client
          .from('load_requests')
          .select(
            'id,from_location,to_village_id,material_type,poster_phone,created_at,is_closed',
          )
          .eq('is_closed', false)
          .gte(
            'created_at',
            now.subtract(const Duration(minutes: 30)).toIso8601String(),
          )
          .lte('created_at', now.toIso8601String())
          .order('created_at', ascending: false)
          .then((rows) => rows),
      client
          .from('call_telemetry')
          .select('caller_phone,created_at')
          .gte('created_at', dayStart.toIso8601String())
          .lt('created_at', dayEnd.toIso8601String())
          .then((rows) => rows),
      client
          .from('call_telemetry')
          .select(
            'caller_phone,receiver_phone,caller_role,context_note,created_at',
          )
          .lte('created_at', now.toIso8601String())
          .order('created_at', ascending: false)
          .limit(50)
          .then((rows) => rows),
    ]).timeout(const Duration(seconds: 12));

    return AdminAnalyticsModel.aggregate(
      profiles: (results[0] as List).cast<Map<String, dynamic>>(),
      drivers: (results[1] as List).cast<Map<String, dynamic>>(),
      loads: (results[2] as List).cast<Map<String, dynamic>>(),
      callsToday: (results[3] as List).cast<Map<String, dynamic>>(),
      recentTelemetry: (results[4] as List).cast<Map<String, dynamic>>(),
      now: now,
    );
  }

  Future<void> reviewDriver(
    AuthRepository auth, {
    required String driverId,
    required DriverVerification decision,
  }) async {
    final client = _client;
    if (decision == DriverVerification.pending || driverId.isEmpty) {
      throw ArgumentError('Choose an approval decision and driver');
    }
    if (client == null || !await auth.isLiveAdmin()) {
      throw StateError('A live admin session is required');
    }
    await client
        .rpc(
          'review_kolleru_driver',
          params: {'driver_id': driverId, 'decision': decision.name},
        )
        .timeout(const Duration(seconds: 12));
  }

  /// Realtime invalidates the authorized snapshot; polling also covers offline
  /// reconnects and installations where realtime has not been enabled yet.
  Stream<void> watchChanges(AuthRepository auth) {
    final client = _client;
    if (client == null) return const Stream.empty();
    RealtimeChannel? channel;
    late final StreamController<void> controller;
    controller = StreamController<void>(
      onListen: () async {
        if (!await auth.isLiveAdmin() ||
            controller.isClosed ||
            !controller.hasListener) {
          return;
        }
        channel = client.channel('admin-desk-${identityHashCode(controller)}');
        for (final table in [
          'drivers',
          'call_telemetry',
          'user_profiles',
          'load_requests',
        ]) {
          channel!.onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: table,
            callback: (_) {
              if (!controller.isClosed) controller.add(null);
            },
          );
        }
        channel!.subscribe();
      },
      onCancel: () async {
        if (channel != null) await client.removeChannel(channel!);
      },
    );
    return controller.stream;
  }
}
