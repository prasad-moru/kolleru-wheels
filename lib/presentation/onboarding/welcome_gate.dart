import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/repositories/auth_repository.dart';
import '../auth/session_router.dart';
import 'welcome_discovery_screen.dart';

class WelcomeGate extends StatefulWidget {
  const WelcomeGate({super.key, this.authRepository});
  final AuthRepository? authRepository;

  @override
  State<WelcomeGate> createState() => _WelcomeGateState();
}

class _WelcomeGateState extends State<WelcomeGate> {
  late final Future<bool> _hasSeenWelcome = _readPreference();

  Future<bool> _readPreference() async {
    try {
      return (await SharedPreferences.getInstance())
              .getBool(WelcomeDiscoveryScreen.preferenceKey) ??
          false;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _hasSeenWelcome,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return snapshot.data == true
          ? SessionRouter(repository: widget.authRepository)
          : WelcomeDiscoveryScreen(authRepository: widget.authRepository);
    },
  );
}
