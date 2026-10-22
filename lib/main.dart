import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/constants/supabase_config.dart';
import 'core/localization/app_language_provider.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/load_request_repository.dart';
import 'data/repositories/supabase_load_request_repository.dart';
import 'presentation/onboarding/welcome_gate.dart';

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
  runApp(const KolleruWheelsApp());
}

class KolleruWheelsApp extends StatefulWidget {
  const KolleruWheelsApp({super.key, this.authRepository, this.languageProvider});
  final AuthRepository? authRepository;
  final AppLanguageProvider? languageProvider;

  @override
  State<KolleruWheelsApp> createState() => _KolleruWheelsAppState();
}

class _KolleruWheelsAppState extends State<KolleruWheelsApp> {
  late final AppLanguageProvider _language;
  late final Future<void> _ready;
  late final bool _ownsLanguage;

  @override
  void initState() {
    super.initState();
    _ownsLanguage = widget.languageProvider == null;
    _language = widget.languageProvider ?? AppLanguageProvider();
    _ready = _language.load();
  }

  @override
  void dispose() {
    if (_ownsLanguage) _language.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppLanguageScope(
    language: _language,
    child: MaterialApp(
      title: 'Kolleru Wheels',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: FutureBuilder<void>(
        future: _ready,
        builder: (context, snapshot) =>
            snapshot.connectionState == ConnectionState.done
            ? WelcomeGate(authRepository: widget.authRepository)
            : const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
    ),
  );
}
