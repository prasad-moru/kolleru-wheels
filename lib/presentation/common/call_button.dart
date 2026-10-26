import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_strings.dart';
import '../../core/constants/app_colors.dart';
import '../../core/localization/app_language_provider.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/telemetry_repository.dart';

class CallButton extends StatefulWidget {
  const CallButton({
    super.key,
    required this.phone,
    this.isDemo = false,
    this.beforeCall,
    this.onConnect,
    this.onCallLaunched,
    this.label = AppStrings.call,
    this.contextNote = 'directory',
    this.callerPhone,
    this.callerRole,
    this.telemetryRepository,
    this.launcher,
    this.compact = false,
    this.backgroundColor,
    this.elevated = false,
    this.borderRadius,
    this.maxLabelLines = 2,
  });
  final Future<bool> Function()? beforeCall;
  final Future<void> Function()? onConnect;
  final VoidCallback? onCallLaunched;
  final String phone;
  final bool isDemo;
  final String label;
  final String contextNote;
  final String? callerPhone;
  final String? callerRole;
  final TelemetryRepository? telemetryRepository;
  final Future<bool> Function(Uri)? launcher;
  final bool compact;
  final Color? backgroundColor;
  final bool elevated;
  final double? borderRadius;
  final int? maxLabelLines;
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

  String _label(String paired) =>
      AppLanguageScope.maybeOf(context)?.label(paired) ?? paired;

  Future<void> _call() async {
    if (_launching) return;
    setState(() => _launching = true);
    if (widget.onConnect != null) {
      try {
        await widget.onConnect!();
      } finally {
        if (mounted) setState(() => _launching = false);
      }
      return;
    }
    if (widget.beforeCall != null) {
      final allowed = await widget.beforeCall!();
      if (!mounted) return;
      if (!allowed) {
        setState(() => _launching = false);
        return;
      }
    }
    if (widget.isDemo) {
      setState(() => _launching = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_label(AppStrings.demoCall))));
      return;
    }
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
    if (launched) widget.onCallLaunched?.call();
    if (!launched) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_label(AppStrings.callFailed))));
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: widget.backgroundColor ?? AppColors.green,
          foregroundColor: Colors.white,
          elevation: widget.elevated ? 2 : 0,
          shape: widget.borderRadius == null
              ? null
              : RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(widget.borderRadius!),
                ),
          shadowColor: const Color(0x33059669),
          minimumSize: Size.fromHeight(widget.compact ? 58 : 64),
          padding: EdgeInsets.symmetric(horizontal: widget.compact ? 10 : 20),
        ),
        onPressed: _launching ? null : _call,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.call, size: 24),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                _label(widget.label),
                maxLines: widget.maxLabelLines,
                overflow: widget.maxLabelLines == null
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
      if (widget.isDemo && !widget.compact) Text(_label(AppStrings.demoCall)),
    ],
  );
}
