import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_strings.dart';
import '../../core/constants/app_colors.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/telemetry_repository.dart';

class CallButton extends StatefulWidget {
  const CallButton({
    super.key,
    required this.phone,
    this.isDemo = false,
    this.label = AppStrings.call,
    this.contextNote = 'directory',
    this.callerPhone,
    this.callerRole,
    this.telemetryRepository,
    this.launcher,
  });
  final String phone;
  final bool isDemo;
  final String label;
  final String contextNote;
  final String? callerPhone;
  final String? callerRole;
  final TelemetryRepository? telemetryRepository;
  final Future<bool> Function(Uri)? launcher;
  @override
  State<CallButton> createState() => _CallButtonState();
}

class _CallButtonState extends State<CallButton> {
  bool _launching = false;
  Future<void> _log() async {
    try {
      final profile = AuthRepository.instance.currentProfile;
      await (widget.telemetryRepository ?? TelemetryRepository.instance)
          .logCallIntent(
            callerPhone: widget.callerPhone ?? profile?.phone,
            receiverPhone: widget.phone,
            callerRole: widget.callerRole ?? profile?.role,
            contextNote: widget.contextNote,
          );
    } catch (_) {
      /* Calls continue even when a custom telemetry sink fails. */
    }
  }

  Future<void> _call() async {
    setState(() => _launching = true);
    unawaited(_log());
    bool launched = false;
    try {
      final uri = Uri(scheme: 'tel', path: widget.phone);
      launched = await (widget.launcher?.call(uri) ?? launchUrl(uri));
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
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.green,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(64),
        ),
        onPressed: _launching
            ? null
            : widget.isDemo
            ? () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text(AppStrings.demoCall)),
                );
              }
            : _call,
        icon: const Icon(Icons.call, size: 28),
        label: Text(widget.label),
      ),
      if (widget.isDemo) const Text(AppStrings.demoCall),
    ],
  );
}
