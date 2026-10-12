import 'package:flutter/material.dart';

import '../../data/repositories/auth_repository.dart';
import 'session_router.dart';

/// Clear the registration stack and verified draft before opening the directory.
Future<void> leaveOnboarding(BuildContext context, AuthRepository auth) async {
  FocusScope.of(context).unfocus();
  try {
    await auth.browseAsGuest();
  } catch (_) {
    // browseAsGuest clears the local identity even if remote sign-out fails.
  }
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute<void>(builder: (_) => SessionRouter(repository: auth)),
    (_) => false,
  );
}

class OnboardingBackScope extends StatelessWidget {
  const OnboardingBackScope({
    super.key,
    required this.child,
    required this.onExit,
    this.enabled = true,
  });
  final Widget child;
  final VoidCallback onExit;
  final bool enabled;

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && enabled) onExit();
    },
    child: child,
  );
}
