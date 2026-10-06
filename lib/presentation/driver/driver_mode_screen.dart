import 'package:flutter/material.dart';

import '../../core/constants/app_strings.dart';
import '../../data/models/local_driver_profile.dart';
import '../../data/repositories/local_driver_repository.dart';
import 'driver_dashboard_screen.dart';
import 'driver_registration_screen.dart';

/// Resolves the saved profile once per visit; storage errors offer a retry.
class DriverModeScreen extends StatefulWidget {
  const DriverModeScreen({super.key, required this.repository});
  final LocalDriverRepository repository;
  @override
  State<DriverModeScreen> createState() => _DriverModeScreenState();
}

class _DriverModeScreenState extends State<DriverModeScreen> {
  late Future<LocalDriverProfile?> _profile;
  @override
  void initState() {
    super.initState();
    _profile = widget.repository.getProfile();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<LocalDriverProfile?>(
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
      final profile = snapshot.data;
      return profile == null
          ? DriverRegistrationScreen(
              repository: widget.repository,
              onRegistered: (profile) => setState(() {
                _profile = Future.value(profile);
              }),
            )
          : DriverDashboardScreen(
              profile: profile,
              repository: widget.repository,
            );
    },
  );
}
