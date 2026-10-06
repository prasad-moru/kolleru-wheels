import 'package:flutter/material.dart';

import '../../data/models/user_profile_model.dart';
import '../../data/repositories/local_driver_repository.dart';
import '../admin/admin_dashboard_screen.dart';
import '../driver/driver_mode_screen.dart';
import '../farmer/home_directory_screen.dart';

class RoleDestination extends StatelessWidget {
  const RoleDestination({super.key, required this.profile});
  final UserProfile profile;
  @override
  Widget build(BuildContext context) => switch (profile.role) {
    'driver' => DriverModeScreen(
      repository: LocalDriverRepository(),
      verifiedPhone: profile.phone,
    ),
    'admin' => const AdminDashboardScreen(),
    _ => const HomeDirectoryScreen(),
  };
}
