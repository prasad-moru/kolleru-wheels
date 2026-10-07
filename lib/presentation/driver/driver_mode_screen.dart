import 'package:flutter/material.dart';

import '../../core/constants/app_strings.dart';
import '../../data/models/local_driver_profile.dart';
import '../../data/repositories/local_driver_repository.dart';
import '../../data/repositories/load_request_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../auth/session_router.dart';
import 'driver_dashboard_screen.dart';
import 'driver_registration_screen.dart';

/// Resolves the saved profile once per visit; storage errors offer a retry.
class DriverModeScreen extends StatefulWidget {
  const DriverModeScreen({
    super.key,
    required this.repository,
    this.loadRequestRepository,
    this.verifiedPhone,
    this.authRepository,
  });
  final LocalDriverRepository repository;
  final LoadRequestRepository? loadRequestRepository;
  final String? verifiedPhone;
  final AuthRepository? authRepository;
  @override
  State<DriverModeScreen> createState() => _DriverModeScreenState();
}

class _DriverModeScreenState extends State<DriverModeScreen> {
  late Future<LocalDriverProfile?> _profile;
  @override
  void initState() {
    super.initState();
    _profile =
        (widget.authRepository ?? AuthRepository.instance)
                .currentProfile
                ?.role ==
            'driver'
        ? widget.repository.getProfile()
        : Future.value(null);
  }

  @override
  Widget build(BuildContext context) =>
      (widget.authRepository ?? AuthRepository.instance).currentProfile?.role !=
          'driver'
      ? SessionRouter(repository: widget.authRepository)
      : FutureBuilder<LocalDriverProfile?>(
          future: _profile,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Scaffold(
                appBar: AppBar(title: const Text(AppStrings.driverMode)),
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(AppStrings.loadFailed),
                      FilledButton(
                        onPressed: () => setState(() {
                          _profile = widget.repository.getProfile();
                        }),
                        child: const Text(AppStrings.retry),
                      ),
                    ],
                  ),
                ),
              );
            }
            if (snapshot.connectionState != ConnectionState.done) {
              return Scaffold(
                appBar: AppBar(title: const Text(AppStrings.driverMode)),
                body: const Center(child: CircularProgressIndicator()),
              );
            }
            final saved = snapshot.data;
            final profile =
                widget.verifiedPhone == null ||
                    saved?.phone == widget.verifiedPhone
                ? saved
                : null;
            return profile == null
                ? DriverRegistrationScreen(
                    verifiedPhone: widget.verifiedPhone,
                    authRepository: widget.authRepository,
                    repository: widget.repository,
                    loadRequestRepository: widget.loadRequestRepository,
                    onRegistered: (profile) => setState(() {
                      _profile = Future.value(profile);
                    }),
                  )
                : DriverDashboardScreen(
                    profile: profile,
                    authRepository: widget.authRepository,
                    repository: widget.repository,
                    loadRequestRepository: widget.loadRequestRepository,
                  );
          },
        );
}
