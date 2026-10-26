import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/localization/app_language_provider.dart';
import '../../../core/theme/driver_card_style.dart';
import '../../../data/models/driver_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/telemetry_repository.dart';
import 'direct_call_modal.dart';
import '../../common/call_button.dart';
import '../../common/driver_avatar_picker.dart';

/// Reusable directory card; exported/shareable cards retain their own layout.
class DriverVisitingCard extends StatefulWidget {
  const DriverVisitingCard({
    super.key,
    required this.driver,
    required this.onOpen,
    required this.onWhatsApp,
    this.callerPhone,
    this.callerRole = 'shipper',
    this.beforeCall,
    this.onCallLaunched,
    this.previewOnly = false,
    this.authRepository,
    this.telemetryRepository,
    this.launcher,
  });
  final AuthRepository? authRepository;
  final TelemetryRepository? telemetryRepository;
  final Future<bool> Function(Uri)? launcher;
  final bool previewOnly;
  final DriverModel driver;
  final VoidCallback onOpen;
  final VoidCallback onWhatsApp;
  final String? callerPhone;
  final String callerRole;
  final Future<bool> Function()? beforeCall;
  final VoidCallback? onCallLaunched;
  @override
  State<DriverVisitingCard> createState() => _DriverVisitingCardState();
}

class _DriverVisitingCardState extends LanguageAwareState<DriverVisitingCard> {
  static const _green = Color(0xFF0A6836);
  DriverModel get driver => widget.driver;

  bool _connecting = false;

  Future<void> _openConnect() async {
    if (_connecting || widget.previewOnly) return;
    setState(() => _connecting = true);
    try {
      if (!driver.isDemo &&
          widget.beforeCall != null &&
          !await widget.beforeCall!()) {
        return;
      }
      if (!mounted) return;
      await showDirectCallModal(
        context: context,
        driver: driver,
        language: language,
        authRepository: widget.authRepository,
        telemetryRepository: widget.telemetryRepository,
        launcher: widget.launcher,
        beforeContact: widget.beforeCall,
        callerPhone: widget.callerPhone,
        callerRole: widget.callerRole,
        onCallLaunched: widget.onCallLaunched,
        onWhatsAppLaunched: widget.onWhatsApp,
      );
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = DriverCardStyle.resolve(driver.cardStyle).accent;
    var tons = driver.capacityTons;
    if (tons == null) {
      tons = double.tryParse(
        RegExp(r'[0-9]+(?:\.[0-9]+)?').firstMatch(driver.capacity)?.group(0) ??
            '',
      );
      if (tons != null &&
          (driver.capacity.contains('కిలో') ||
              driver.capacity.toLowerCase().contains('kg'))) {
        tons /= 1000;
      }
    }
    final capacity = tons == null
        ? tr(te: 'సామర్థ్యం నమోదు కాలేదు', en: 'Capacity not provided')
        : '${tons.toStringAsFixed(tons % 1 == 0
              ? 0
              : (tons * 10) % 1 == 0
              ? 1
              : 2)} ${tr(te: 'టన్నులు', en: 'Tons')}';
    final status = Container(
      key: ValueKey('availability-${driver.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: driver.isAvailable
            ? const Color(0xFFE2F7EA)
            : const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        driver.isAvailable
            ? tr(te: '🟢 అందుబాటులో ఉంది', en: '🟢 Available Now')
            : widget.previewOnly
            ? tr(te: 'ఆఫ్‌లైన్', en: 'Offline')
            : tr(te: 'బిజీ', en: 'Busy'),
        style: TextStyle(
          color: driver.isAvailable ? _green : const Color(0xFF92400E),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    final identity = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DriverAvatarPicker(
          name: language.label(driver.name),
          imageUrl: driver.avatarUrl,
          size: 52,
          editable: false,
          language: language,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            children: [
              Text(
                language.label(driver.name),
                style: const TextStyle(
                  color: _green,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (driver.isPhoneVerified)
                Tooltip(
                  message: tr(te: 'ధృవీకరించిన ఫోన్', en: 'Verified phone'),
                  child: const Icon(Icons.verified, color: _green, size: 18),
                ),
            ],
          ),
        ),
      ],
    );
    return AppLanguageScope(
      language: language,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFCDEBDA)),
          boxShadow: [
            BoxShadow(
              color: _green.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Material(
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  key: ValueKey('style-strip-${driver.id}'),
                  height: 3,
                  color: accent,
                ),
                InkWell(
                  onTap: widget.previewOnly ? null : widget.onOpen,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) {
                            if (constraints.maxWidth < 420 ||
                                MediaQuery.textScalerOf(context).scale(14) >
                                    20) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  identity,
                                  const SizedBox(height: 10),
                                  status,
                                ],
                              );
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: identity),
                                const SizedBox(width: 8),
                                status,
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF2F7F4),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr(
                                  te: driver.vehicleType.teluguName,
                                  en: driver.vehicleType.englishName,
                                ),
                                style: const TextStyle(
                                  color: _green,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                driver.vehicleNumber.isEmpty
                                    ? tr(
                                        te: 'వాహనం నంబర్ నమోదు కాలేదు',
                                        en: 'Vehicle number not provided',
                                      )
                                    : driver.vehicleNumber,
                                style: const TextStyle(
                                  color: Color(0xFF365B47),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Container(
                                key: ValueKey('capacity-${driver.id}'),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  capacity,
                                  style: const TextStyle(
                                    color: Color(0xFF78350F),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.location_on_outlined,
                                    size: 18,
                                    color: _green,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      tr(
                                        te: '${driver.baseLocation == null ? driver.village.teluguName : language.label(driver.baseLocation!)} & చుట్టుపక్కల ప్రాంతాలు',
                                        en: '${driver.baseLocation == null ? driver.village.name : language.label(driver.baseLocation!)} & surrounding areas',
                                      ),
                                      style: const TextStyle(
                                        color: Color(0xFF365B47),
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (driver.isDemo)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              language.label(AppStrings.demoCall),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (!widget.previewOnly)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final call = CallButton(
                          key: ValueKey('call-${driver.id}'),
                          phone: driver.phone,
                          isDemo: driver.isDemo,
                          label: tr(te: 'కాల్ చేయండి', en: 'Call'),
                          compact: true,
                          backgroundColor: _green,
                          callerPhone: widget.callerPhone,
                          callerRole: widget.callerRole,
                          contextNote: 'directory:${driver.id}',
                          beforeCall: widget.beforeCall,
                          onConnect: _openConnect,
                          onCallLaunched: widget.onCallLaunched,
                        );
                        final chat = OutlinedButton.icon(
                          key: ValueKey('whatsapp-${driver.id}'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(58),
                            foregroundColor: _green,
                            side: const BorderSide(color: _green),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          onPressed: driver.isDemo || _connecting
                              ? null
                              : _openConnect,
                          icon: const Icon(Icons.chat_bubble_outline, size: 24),
                          label: Text(
                            tr(te: 'వాట్సాప్', en: 'WhatsApp'),
                            textAlign: TextAlign.center,
                          ),
                        );
                        if (constraints.maxWidth < 280 ||
                            MediaQuery.textScalerOf(context).scale(16) > 22) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [call, const SizedBox(height: 8), chat],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: call),
                            const SizedBox(width: 10),
                            Expanded(child: chat),
                          ],
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
