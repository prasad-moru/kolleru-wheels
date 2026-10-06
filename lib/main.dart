import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/constants/supabase_config.dart';
import 'data/repositories/load_request_repository.dart';
import 'data/repositories/supabase_load_request_repository.dart';

import 'core/theme/app_theme.dart';
import 'presentation/farmer/home_directory_screen.dart';

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
      /* Local browsing remains available if SDK startup fails. */
    }
  }
  LoadRequestRepository.instance = SupabaseLoadRequestRepository();
  runApp(const KolleruWheelsApp());
}

class KolleruWheelsApp extends StatelessWidget {
  const KolleruWheelsApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Kolleru Wheels',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: const HomeDirectoryScreen(),
  );
}
