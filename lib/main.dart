import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/constants/supabase_config.dart';
import 'data/repositories/load_request_repository.dart';
import 'data/repositories/supabase_load_request_repository.dart';
import 'data/repositories/auth_repository.dart';
import 'presentation/auth/session_router.dart';

import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (SupabaseConfig.isConfigured) {
    try {
      await Supabase.initialize(
        url: SupabaseConfig.supabaseUrl,
        publishableKey: SupabaseConfig.supabaseAnonKey,
      );
      SupabaseConfig.client = Supabase.instance.client;
    } catch (_) {
      /* Sign-in remains gated if SDK startup fails. */
    }
  }
  LoadRequestRepository.instance = SupabaseLoadRequestRepository();
  await AuthRepository.instance.restoreSession();
  runApp(const KolleruWheelsApp());
}

class KolleruWheelsApp extends StatelessWidget {
  const KolleruWheelsApp({super.key, this.authRepository});
  final AuthRepository? authRepository;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Kolleru Wheels',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    // Guests enter the Login/Register gateway; completed sessions stay isolated
    // by their authoritative profile role.
    home: SessionRouter(repository: authRepository),
  );
}
