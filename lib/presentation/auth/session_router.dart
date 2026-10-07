import 'package:flutter/material.dart';

import '../../data/repositories/auth_repository.dart';
import 'phone_otp_screen.dart';
import 'role_destination.dart';

class SessionRouter extends StatefulWidget {
  const SessionRouter({super.key, this.repository});
  final AuthRepository? repository;
  @override
  State<SessionRouter> createState() => _SessionRouterState();
}

class _SessionRouterState extends State<SessionRouter> {
  late final _auth = widget.repository ?? AuthRepository.instance;
  bool _restoring = false;
  @override
  void initState() {
    super.initState();
    _auth.addListener(_changed);
    if (_auth.currentProfile == null && _auth.onboardingPhone == null) {
      _restore();
    }
  }

  Future<void> _restore() async {
    _restoring = true;
    await _auth.restoreSession();
    if (mounted) setState(() => _restoring = false);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _auth.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_restoring) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final profile = _auth.currentProfile;
    if (profile != null) {
      return RoleDestination(profile: profile, authRepository: _auth);
    }
    return PhoneOtpScreen(repository: _auth, onVerified: (_) => _changed());
  }
}
