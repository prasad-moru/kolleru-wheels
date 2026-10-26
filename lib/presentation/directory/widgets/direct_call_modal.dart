import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/localization/app_language_provider.dart';
import '../../../data/models/driver_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/telemetry_repository.dart';
import '../../auth/session_router.dart';
import 'connect_gate.dart';

Future<void> showDirectCallModal({
  required BuildContext context,
  required DriverModel driver,
  AuthRepository? authRepository,
  TelemetryRepository? telemetryRepository,
  Future<bool> Function(Uri)? launcher,
  Future<bool> Function()? beforeContact,
  VoidCallback? onCallLaunched,
  VoidCallback? onWhatsAppLaunched,
  String? callerPhone,
  String? callerRole,
  AppLanguageProvider? language,
}) async {
  final selectedLanguage = language ?? AppLanguageScope.maybeOf(context);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    elevation: 16,
    barrierColor: const Color(0xFF073A22).withValues(alpha: 0.45),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (_) {
      final sheet = DirectCallModal(
        driver: driver,
        authRepository: authRepository,
        telemetryRepository: telemetryRepository,
        launcher: launcher,
        beforeContact: beforeContact,
        onCallLaunched: onCallLaunched,
        onWhatsAppLaunched: onWhatsAppLaunched,
        callerPhone: callerPhone,
        callerRole: callerRole,
      );
      return selectedLanguage == null
          ? sheet
          : AppLanguageScope(language: selectedLanguage, child: sheet);
    },
  );
}

/// Contact intents are recorded only after verification and an explicit action.
class DirectCallModal extends StatefulWidget {
  const DirectCallModal({
    super.key,
    required this.driver,
    this.authRepository,
    this.telemetryRepository,
    this.launcher,
    this.beforeContact,
    this.onCallLaunched,
    this.onWhatsAppLaunched,
    this.callerPhone,
    this.callerRole,
  });
  final DriverModel driver;
  final AuthRepository? authRepository;
  final TelemetryRepository? telemetryRepository;
  final Future<bool> Function(Uri)? launcher;
  final Future<bool> Function()? beforeContact;
  final VoidCallback? onCallLaunched;
  final VoidCallback? onWhatsAppLaunched;
  final String? callerPhone;
  final String? callerRole;
  @override
  State<DirectCallModal> createState() => _DirectCallModalState();
}

class _DirectCallModalState extends LanguageAwareState<DirectCallModal> {
  static const _green = Color(0xFF0A6836);
  late final _auth = widget.authRepository ?? AuthRepository.instance;
  bool _busy = false;
  DriverContactMethod? _failed;
  bool _invalidPhone = false;

  Future<bool> _authorize() async {
    if (widget.beforeContact != null) return widget.beforeContact!();
    if (!_auth.isGuest && _auth.currentProfile != null) return true;
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AppLanguageScope(
        language: language,
        child: ConnectGate(auth: _auth),
      ),
    );
    if (!mounted) return false;
    if (_auth.onboardingPhone != null) {
      _auth.endGuestMode();
      Navigator.of(context).pushAndRemoveUntil<void>(
        MaterialPageRoute(builder: (_) => SessionRouter(repository: _auth)),
        (_) => false,
      );
      return false;
    }
    return accepted == true && _auth.currentProfile != null;
  }

  Future<void> _record(DriverContactMethod method, String phone) async {
    try {
      // Read identity after the gate so a former guest is logged as the verified shipper.
      final profile = _auth.currentProfile;
      await (widget.telemetryRepository ?? TelemetryRepository.instance)
          .logDriverInquiry(
            driverId: widget.driver.id,
            receiverPhone: phone,
            method: method,
            callerPhone: profile?.phone ?? widget.callerPhone,
            callerRole: profile?.role ?? widget.callerRole,
          );
    } catch (_) {
      /* Contacting a driver remains available while telemetry is offline. */
    }
  }

  Future<void> _contact(DriverContactMethod method) async {
    if (_busy || widget.driver.isDemo) return;
    setState(() {
      _busy = true;
      _failed = null;
      _invalidPhone = false;
    });
    try {
      if (!await _authorize() || !mounted) return;
      String phone;
      try {
        phone = AuthRepository.normalizePhone(widget.driver.phone);
      } on FormatException {
        setState(() => _invalidPhone = true);
        return;
      }
      final name = language.label(widget.driver.name);
      final greeting = tr(
        te: 'నమస్కారం $name, కొల్లేరు వీల్స్ ద్వారా సంప్రదిస్తున్నాను. కొల్లేరు డెల్టాలో సరుకు రవాణా కావాలి. సరుకు, అంచనా బరువు, లోడ్ తీసుకునే స్థలం వివరాలు పంపుతాను.',
        en: 'Hello $name, I found you on Kolleru Wheels. I need transport in the Kolleru delta. I will share my load, estimated weight and pickup location.',
      );
      final uri = method == DriverContactMethod.call
          ? Uri(scheme: 'tel', path: phone)
          : Uri.https('wa.me', '/${phone.substring(1)}', {'text': greeting});
      unawaited(_record(method, phone));
      final launched =
          await (widget.launcher?.call(uri) ??
              launchUrl(uri, mode: LaunchMode.externalApplication));
      if (!mounted) return;
      if (!launched) {
        setState(() => _failed = method);
        return;
      }
      if (method == DriverContactMethod.call) {
        widget.onCallLaunched?.call();
      } else {
        widget.onWhatsAppLaunched?.call();
      }
    } catch (_) {
      if (mounted) setState(() => _failed = method);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _capacity() {
    var tons = widget.driver.capacityTons;
    if (tons == null) {
      tons = double.tryParse(
        RegExp(r'[0-9]+(?:\.[0-9]+)?')
                .firstMatch(widget.driver.capacity)
                ?.group(0) ??
            '',
      );
      if (tons != null &&
          (widget.driver.capacity.contains('కిలో') ||
              widget.driver.capacity.toLowerCase().contains('kg'))) {
        tons /= 1000;
      }
    }
    if (tons == null) {
      return tr(te: 'సామర్థ్యం నమోదు కాలేదు', en: 'Capacity not provided');
    }
    final amount = tons.toStringAsFixed(
      tons % 1 == 0
          ? 0
          : (tons * 10) % 1 == 0
          ? 1
          : 2,
    );
    return tr(te: '$amount టన్నులు', en: '$amount Tons');
  }

  @override
  Widget build(BuildContext context) {
    final driver = widget.driver;
    final base = driver.baseLocation == null
        ? tr(te: driver.village.teluguName, en: driver.village.name)
        : language.label(driver.baseLocation!);
    final actionable = !_busy && !driver.isDemo;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        key: const ValueKey('direct-call-sheet'),
        padding: EdgeInsets.fromLTRB(
          24,
          12,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                key: const ValueKey('direct-call-handle'),
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFCDD7D1),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    tr(
                      te: 'డ్రైవర్‌తో నేరుగా మాట్లాడండి',
                      en: 'Direct Driver Connect',
                    ),
                    style: const TextStyle(
                      color: _green,
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: const ValueKey('modal-close-button'),
                  tooltip: tr(te: 'మూసివేయండి', en: 'Close'),
                  onPressed: () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFEAF8F0),
                    foregroundColor: _green,
                  ),
                  icon: const Icon(Icons.close, size: 24),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F7F4),
                border: Border.all(color: const Color(0xFFCDEBDA)),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const CircleAvatar(
                        backgroundColor: _green,
                        foregroundColor: Colors.white,
                        child: Icon(Icons.local_shipping_outlined, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
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
                                    message: tr(
                                      te: 'ధృవీకరించిన ఫోన్',
                                      en: 'Verified phone',
                                    ),
                                    child: const Icon(
                                      Icons.verified,
                                      color: _green,
                                      size: 18,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${tr(te: driver.vehicleType.teluguName, en: driver.vehicleType.englishName)} • ${_capacity()}',
                              style: const TextStyle(
                                color: Color(0xFF365B47),
                                height: 1.4,
                              ),
                            ),
                            if (driver.vehicleNumber.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  driver.vehicleNumber,
                                  style: const TextStyle(
                                    color: Color(0xFF365B47),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        color: _green,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          tr(te: '$base క్లస్టర్', en: '$base Delta Cluster'),
                          style: const TextStyle(color: _green, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF1FBF5),
                border: Border.all(color: const Color(0xFFCDEBDA)),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(
                      te: 'కాల్ చేసే ముందు సిద్ధంగా ఉంచుకోండి:',
                      en: 'Keep ready before calling:',
                    ),
                    style: const TextStyle(
                      color: _green,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    key: const ValueKey('checklist-chips'),
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final label in [
                        tr(te: '🐟 పట్టుబడి రకం', en: '🐟 Load Type'),
                        tr(te: '⚖️ అంచనా బరువు', en: '⚖️ Estimated Tons'),
                        tr(te: '📍 చెరువు దారి', en: '📍 Pickup and Route'),
                      ])
                        Chip(
                          label: Text(
                            label,
                            style: const TextStyle(color: _green, fontSize: 12),
                          ),
                          backgroundColor: Colors.white,
                          side: BorderSide.none,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const ValueKey('modal-call-button'),
              onPressed: actionable
                  ? () => _contact(DriverContactMethod.call)
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
              icon: const Icon(Icons.call, size: 24),
              label: Text(
                tr(te: 'నేరుగా కాల్ చేయండి', en: 'Call Driver Now'),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const ValueKey('modal-whatsapp-button'),
              onPressed: actionable
                  ? () => _contact(DriverContactMethod.whatsapp)
                  : null,
              style: OutlinedButton.styleFrom(
                backgroundColor: const Color(0xFFEAF8F0),
                foregroundColor: _green,
                side: const BorderSide(color: _green),
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.chat_bubble_outline, size: 24),
              label: Text(
                tr(
                  te: 'వాట్సాప్‌లో లొకేషన్ పంపండి',
                  en: 'Send Location on WhatsApp',
                ),
                textAlign: TextAlign.center,
              ),
            ),
            if (driver.isDemo)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  tr(
                    te: 'నమూనా నంబర్ • సంప్రదించడం నిలిపివేయబడింది',
                    en: 'Demo number • Contacting disabled',
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            if (_invalidPhone || _failed != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _invalidPhone
                      ? tr(
                          te: 'డ్రైవర్ ఫోన్ నంబర్ సరికాదు.',
                          en: 'The driver phone number is invalid.',
                        )
                      : _failed == DriverContactMethod.call
                      ? tr(
                          te: 'డయలర్ తెరవలేదు. మళ్లీ ప్రయత్నించండి.',
                          en: 'Could not open the dialer. Please retry.',
                        )
                      : tr(
                          te: 'వాట్సాప్ తెరవలేదు. మళ్లీ ప్రయత్నించండి.',
                          en: 'Could not open WhatsApp. Please retry.',
                        ),
                  style: const TextStyle(color: Color(0xFFB42318)),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 18),
            Text(
              tr(
                te: '✓ కొల్లేరు వీల్స్ ఎటువంటి బ్రోకర్ ఛార్జీలు తీసుకోదు • నేరుగా మాట్లాడండి',
                en: '✓ Zero Brokerage • Agree on trip price directly with driver',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(color: _green, fontSize: 12, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
