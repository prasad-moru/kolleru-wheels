import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/supabase_config.dart';
import '../models/admin_analytics_model.dart';
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
          .select('base_village_id,is_available')
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
}
