import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/supabase_config.dart';
import '../models/driver_activity_model.dart';
import 'auth_repository.dart';

/// The RPC derives the receiver from the authenticated identity, never a client phone filter.
class DriverActivityRepository {
  DriverActivityRepository({SupabaseClient? client, DateTime Function()? now})
    : _client = client ?? SupabaseConfig.client,
      _now = now ?? DateTime.now;
  final SupabaseClient? _client;
  final DateTime Function() _now;
  DateTime get currentTime => _now().toUtc();
  bool get isConfigured => _client != null;

  Future<DriverActivity> fetchActivity(AuthRepository auth) async {
    if (auth.isGuest || auth.currentProfile?.role != 'driver') {
      throw StateError('Driver identity required');
    }
    final client = _client;
    if (client == null) {
      return const DriverActivity(callsToday: 0, recentCalls: []);
    }
    final response = await client
        .rpc('driver_activity_snapshot')
        .timeout(const Duration(seconds: 12));
    return DriverActivity.fromJson(Map<String, dynamic>.from(response as Map));
  }
}
