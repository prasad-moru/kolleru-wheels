import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/supabase_config.dart';
import 'auth_repository.dart';

class TelemetryRepository {
  TelemetryRepository({SupabaseClient? client, DateTime Function()? now})
    : _client = client ?? SupabaseConfig.client,
      _now = now ?? DateTime.now;
  static final instance = TelemetryRepository();
  final SupabaseClient? _client;
  final DateTime Function() _now;
  Future<void> logCallIntent({
    String? callerPhone,
    required String receiverPhone,
    String? callerRole,
    String contextNote = 'directory',
  }) async {
    try {
      if (_client == null) return;
      await _client
          .from('call_telemetry')
          .insert({
            'caller_phone': callerPhone,
            'receiver_phone': receiverPhone,
            'caller_role': callerRole ?? 'guest',
            'context_note': contextNote,
          })
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      /* Observability must never interfere with calling. */
    }
  }

  Future<Map<String, dynamic>> getAdminSnapshot(AuthRepository auth) async {
    if (!await auth.isLiveAdmin() || _client == null) {
      throw StateError('Admin access requires an online authorized session');
    }
    const offset = Duration(hours: 5, minutes: 30);
    final local = _now().toUtc().add(offset);
    final start = DateTime.utc(
      local.year,
      local.month,
      local.day,
    ).subtract(offset);
    final end = start.add(const Duration(days: 1));
    final results = await Future.wait<Object>([
      _client.from('drivers').count(CountOption.exact).then((value) => value),
      _client
          .from('drivers')
          .count(CountOption.exact)
          .eq('is_available', true)
          .then((value) => value),
      _client
          .from('load_requests')
          .count(CountOption.exact)
          .gte('created_at', start.toIso8601String())
          .lt('created_at', end.toIso8601String())
          .then((value) => value),
      _client
          .from('call_telemetry')
          .select()
          .order('created_at', ascending: false)
          .limit(50)
          .then((value) => value),
    ]).timeout(const Duration(seconds: 10));
    return {
      'total': results[0],
      'active': results[1],
      'loads': results[2],
      'calls': results[3],
    };
  }
}
