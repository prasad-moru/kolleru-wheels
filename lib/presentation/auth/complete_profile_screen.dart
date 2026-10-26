import 'package:flutter/material.dart';

import '../../data/models/user_profile_model.dart';
import '../../data/repositories/auth_repository.dart';
import 'role_selection_screen.dart';

/// Compatibility entry point for existing post-verification callers.
class CompleteProfileScreen extends StatelessWidget {
  const CompleteProfileScreen({
    super.key,
    required this.phone,
    this.repository,
    this.onCompleted,
  });
  final String phone;
  final AuthRepository? repository;
  final ValueChanged<UserProfile>? onCompleted;

  @override
  Widget build(BuildContext context) => RoleSelectionScreen(
    phone: phone,
    repository: repository,
    onCompleted: onCompleted,
  );
}
