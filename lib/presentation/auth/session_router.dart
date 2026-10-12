import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/repositories/admin_analytics_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../admin/admin_dashboard_screen.dart';
import 'phone_otp_screen.dart';
import 'role_destination.dart';

class SessionRouter extends StatefulWidget {
  const SessionRouter({
    super.key,
    this.repository,
    this.adminAnalyticsRepository,
  });
  final AuthRepository? repository;
  final AdminAnalyticsRepository? adminAnalyticsRepository;
  @override
  State<SessionRouter> createState() => _SessionRouterState();
}

class _SessionRouterState extends State<SessionRouter>
    with WidgetsBindingObserver {
  late final _auth = widget.repository ?? AuthRepository.instance;
  bool _restoring = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _auth.addListener(_changed);
    if (_auth.currentProfile == null && _auth.onboardingPhone == null) {
      _restore();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_auth.onAppResumed());
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
    WidgetsBinding.instance.removeObserver(this);
    _auth.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_restoring) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final profile = _auth.currentProfile;
    final destination = profile?.role == 'admin'
        ? AdminDashboardScreen(
            authRepository: _auth,
            analyticsRepository: widget.adminAnalyticsRepository,
          )
        : profile != null
        ? RoleDestination(profile: profile, authRepository: _auth)
        : PhoneOtpScreen(repository: _auth, onVerified: (_) => _changed());
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => unawaited(_auth.recordActivity()),
      child: destination,
    );
  }
}
