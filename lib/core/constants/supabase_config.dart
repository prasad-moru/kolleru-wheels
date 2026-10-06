import 'package:supabase_flutter/supabase_flutter.dart';

abstract final class SupabaseConfig {
  // Configure with --dart-define. Never put a service-role/secret key here.
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static bool get isConfigured {
    final url = Uri.tryParse(supabaseUrl);
    return url != null &&
        url.scheme == 'https' &&
        url.host.isNotEmpty &&
        supabaseAnonKey.isNotEmpty;
  }

  static SupabaseClient? client;
}
