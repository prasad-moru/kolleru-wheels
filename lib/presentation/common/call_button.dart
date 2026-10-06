import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_strings.dart';

class CallButton extends StatefulWidget {
  const CallButton({super.key, required this.phone, this.isDemo = false});
  final String phone;
  final bool isDemo;
  @override
  State<CallButton> createState() => _CallButtonState();
}

class _CallButtonState extends State<CallButton> {
  bool _launching = false;
  Future<void> _call() async {
    setState(() => _launching = true);
    bool launched = false;
    try {
      launched = await launchUrl(Uri(scheme: 'tel', path: widget.phone));
    } catch (_) {
      /* Recoverable platform failure. */
    }
    if (!mounted) return;
    setState(() => _launching = false);
    if (!launched) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(AppStrings.callFailed)));
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FilledButton.icon(
        onPressed: widget.isDemo || _launching ? null : _call,
        icon: const Icon(Icons.call, size: 28),
        label: const Text(AppStrings.call),
      ),
      if (widget.isDemo) const Text(AppStrings.demoCall),
    ],
  );
}
