import 'package:flutter/material.dart';

import '../../data/models/driver_model.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/telemetry_repository.dart';
import '../directory/widgets/driver_visiting_card.dart';

/// Compatibility entry point for existing directory consumers and finder keys.
class DriverDirectoryCard extends StatelessWidget {
  const DriverDirectoryCard({
    super.key,
    required this.driver,
    required this.onOpen,
    required this.onWhatsApp,
    this.callerPhone,
    this.callerRole = 'shipper',
    this.beforeCall,
    this.onCallLaunched,
    this.authRepository,
    this.telemetryRepository,
    this.launcher,
  });
  final AuthRepository? authRepository;
  final TelemetryRepository? telemetryRepository;
  final Future<bool> Function(Uri)? launcher;
  final DriverModel driver;
  final VoidCallback onOpen;
  final VoidCallback onWhatsApp;
  final String? callerPhone;
  final String callerRole;
  final Future<bool> Function()? beforeCall;
  final VoidCallback? onCallLaunched;

  @override
  Widget build(BuildContext context) => DriverVisitingCard(
    driver: driver,
    authRepository: authRepository,
    telemetryRepository: telemetryRepository,
    launcher: launcher,
    onOpen: onOpen,
    onWhatsApp: onWhatsApp,
    callerPhone: callerPhone,
    callerRole: callerRole,
    beforeCall: beforeCall,
    onCallLaunched: onCallLaunched,
  );
}
