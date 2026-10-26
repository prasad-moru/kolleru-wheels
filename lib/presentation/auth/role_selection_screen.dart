import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/villages.dart';
import '../../core/localization/app_language_provider.dart';
import '../../data/models/local_driver_profile.dart';
import '../../data/models/user_profile_model.dart';
import '../../data/models/vehicle_type.dart';
import '../../data/repositories/auth_repository.dart';
import 'onboarding_navigation.dart';
import 'session_router.dart';

/// Shared post-OTP registration. Stable locality IDs route loads; typed bases stay intact.
class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({
    super.key,
    required this.phone,
    this.repository,
    this.onCompleted,
  });
  final String phone;
  final AuthRepository? repository;
  final ValueChanged<UserProfile>? onCompleted;
  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState
    extends LanguageAwareState<RoleSelectionScreen> {
  static const _green = Color(0xFF0A6836);
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _village = TextEditingController();
  final _number = TextEditingController();
  final _driverId = const Uuid().v4();
  late final _auth = widget.repository ?? AuthRepository.instance;
  String _role = 'shipper';
  String? _mandalId;
  VehicleType _vehicle = VehicleType.boleroPickup;
  bool _saving = false;
  bool _validated = false;
  bool _failed = false;
  bool _needsVerification = false;

  String? get _phone {
    try {
      return AuthRepository.normalizePhone(widget.phone);
    } on FormatException {
      return null;
    }
  }

  bool get _phoneVerified => _phone != null && _auth.verifiedPhone == _phone;
  Mandal? get _mandal =>
      KolleruVillages.mandals.where((m) => m.id == _mandalId).firstOrNull;
  Village? get _routingVillage {
    final villages = _mandal?.villages;
    if (villages == null || villages.isEmpty) return null;
    final typed = _village.text.trim().toLowerCase();
    return villages
            .where(
              (v) => v.name.toLowerCase() == typed || v.teluguName == typed,
            )
            .firstOrNull ??
        villages.first;
  }

  @override
  void onLanguageChanged() {
    if (_validated) _form.currentState?.validate();
  }

  Future<void> _complete() async {
    if (_saving) return;
    _validated = true;
    if (!_form.currentState!.validate()) return;
    if (!_phoneVerified) {
      setState(() => _needsVerification = true);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _failed = false;
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final village = _routingVillage!;
      final base = _village.text.trim();
      final driver = _role == 'driver'
          ? LocalDriverProfile(
              id: _driverId,
              name: _name.text.trim(),
              phone: _phone!,
              baseVillage: village,
              currentSpotVillage: village,
              currentSpotLabel: base,
              baseLocation: base,
              vehicleType: _vehicle,
              capacityTons: switch (_vehicle) {
                VehicleType.miniTruck709 => 5,
                VehicleType.tipper => 8,
                _ => 2.5,
              },
              specializations: const [],
              vehicleNumber: _number.text.trim().toUpperCase(),
              isAvailable: true,
              isPhoneVerified: true,
            )
          : null;
      final profile = await _auth.completeRegistration(
        phone: _phone!,
        name: _name.text,
        role: _role,
        villageId: village.id,
        baseLocation: base,
        driver: driver,
      );
      if (!mounted) return;
      widget.onCompleted?.call(profile);
      navigator.pushAndRemoveUntil<void>(
        MaterialPageRoute(builder: (_) => SessionRouter(repository: _auth)),
        (_) => false,
      );
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              tr(te: 'నమోదు విజయవంతమైంది!', en: 'Registration Successful!'),
            ),
          ),
        );
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _leave() async {
    if (_saving) return;
    await leaveOnboarding(context, _auth);
  }

  @override
  void dispose() {
    _name.dispose();
    _village.dispose();
    _number.dispose();
    super.dispose();
  }

  BoxDecoration _surface() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(22),
    border: Border.all(color: const Color(0xFFCDEBDA)),
    boxShadow: [
      BoxShadow(
        color: _green.withValues(alpha: 0.05),
        blurRadius: 18,
        offset: const Offset(0, 5),
      ),
    ],
  );

  Widget _roleCard({required bool driver}) {
    final role = driver ? 'driver' : 'shipper';
    final selected = _role == role;
    return KeyedSubtree(
      key: ValueKey(driver ? 'complete-driver' : 'complete-shipper'),
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey(driver ? 'role-card-driver' : 'role-card-farmer'),
            onTap: _saving ? null : () => setState(() => _role = role),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFEAF8F0) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? _green : const Color(0xFFCDEBDA),
                  width: selected ? 2 : 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFFD5F5E2),
                    foregroundColor: _green,
                    child: Icon(
                      driver
                          ? Icons.local_shipping_outlined
                          : Icons.water_outlined,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          driver
                              ? tr(
                                  te: 'వాహన యజమాని లేదా డ్రైవర్',
                                  en: 'Vehicle Owner or Driver',
                                )
                              : tr(
                                  te: 'రైతు లేదా సరుకు రవాణాదారు',
                                  en: 'Aqua Farmer or Shipper',
                                ),
                          style: const TextStyle(
                            color: _green,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          driver
                              ? tr(
                                  te: 'నా వాహనంతో రవాణా ఆర్డర్లు పొందాలి',
                                  en: 'Get transport trips for my vehicle',
                                )
                              : tr(
                                  te: 'చేపలు, రొయ్యలు, పంట లేదా దాణా రవాణా కావాలి',
                                  en: 'Need vehicles for harvest, crops, or feed',
                                ),
                          style: const TextStyle(
                            color: Color(0xFF365B47),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: selected ? _green : const Color(0xFF8EBFA3),
                    size: 24,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _verifiedPhone() => Container(
    key: const ValueKey('verified-mobile'),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFF2F7F4),
      border: Border.all(color: const Color(0xFFCDEBDA)),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            '+91',
            style: TextStyle(color: _green, fontWeight: FontWeight.w700),
          ),
        ),
        Text(
          _phone?.substring(3) ?? widget.phone,
          style: const TextStyle(
            color: _green,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          _phoneVerified
              ? tr(te: 'ధృవీకరించబడింది ✓', en: 'Verified ✓')
              : tr(te: 'ధృవీకరణ అవసరం', en: 'Verification required'),
          style: const TextStyle(
            color: _green,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  Widget _vehicleFields() => Column(
    key: const ValueKey('vehicle-type-selector'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        tr(te: 'మీ వాహనం రకం', en: 'Your Vehicle Type'),
        style: const TextStyle(color: _green, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final type in [
            VehicleType.boleroPickup,
            VehicleType.miniTruck709,
            VehicleType.tipper,
          ])
            ChoiceChip(
              key: ValueKey('registration-vehicle-${type.name}'),
              showCheckmark: false,
              selected: _vehicle == type,
              selectedColor: _green,
              backgroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFFBDE5CE)),
              labelStyle: TextStyle(
                color: _vehicle == type ? Colors.white : _green,
              ),
              label: Text(switch (type) {
                VehicleType.miniTruck709 => tr(
                  te: '709 మినీ లారీ 5ట',
                  en: '709 Mini Truck 5T',
                ),
                VehicleType.tipper => tr(te: 'టిప్పర్ 8ట+', en: 'Tipper 8T+'),
                _ => tr(te: 'బొలెరో 2.5ట', en: 'Bolero 2.5T'),
              }),
              onSelected: _saving
                  ? null
                  : (_) => setState(() => _vehicle = type),
            ),
        ],
      ),
      const SizedBox(height: 18),
      TextFormField(
        key: const ValueKey('vehicle-number-field'),
        controller: _number,
        enabled: !_saving,
        textCapitalization: TextCapitalization.characters,
        maxLength: 20,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9 -]')),
        ],
        decoration: InputDecoration(
          labelText: tr(
            te: 'వాహనం రిజిస్ట్రేషన్ నంబర్',
            en: 'Vehicle Registration Number',
          ),
          hintText: 'AP 37 TX 1234',
          counterText: '',
        ),
        validator: (value) =>
            RegExp(r'^[A-Z]{2}[0-9]{1,2}[A-Z]{1,3}[0-9]{4}$').hasMatch(
              (value ?? '').toUpperCase().replaceAll(RegExp(r'[\s-]'), ''),
            )
            ? null
            : tr(
                te: 'సరైన వాహనం నంబర్ ఇవ్వండి',
                en: 'Enter a valid vehicle registration number',
              ),
      ),
    ],
  );

  Widget _profileForm() => Container(
    padding: const EdgeInsets.all(20),
    decoration: _surface(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr(te: 'మీ వివరాలు', en: 'Your Profile Details'),
          style: const TextStyle(
            color: _green,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 22),
        KeyedSubtree(
          key: const ValueKey('complete-name'),
          child: TextFormField(
            key: const ValueKey('name-input-field'),
            controller: _name,
            enabled: !_saving,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            maxLength: 80,
            decoration: InputDecoration(
              labelText: tr(te: 'మీ పూర్తి పేరు', en: 'Full Name'),
              hintText: tr(te: 'ఉదా: మూర్తి రాజు', en: 'e.g. Murthy Raju'),
              counterText: '',
            ),
            validator: (value) =>
                (value ?? '').trim().length < 2 ||
                    (value ?? '').trim().length > 80
                ? tr(
                    te: 'పేరు ఇవ్వండి (2–80 అక్షరాలు)',
                    en: 'Enter a name (2–80 characters)',
                  )
                : null,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          tr(te: 'ధృవీకరించిన మొబైల్', en: 'Verified Mobile'),
          style: const TextStyle(color: _green, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        _verifiedPhone(),
        const SizedBox(height: 20),
        KeyedSubtree(
          key: const ValueKey('mandal-picker'),
          child: DropdownButtonFormField<String>(
            key: const ValueKey('mandal-dropdown'),
            initialValue: _mandalId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: tr(te: 'మీ మండలం', en: 'Your Mandal'),
            ),
            items: [
              for (final id in [
                'akividu',
                'kaikaluru',
                'bhimavaram',
                'mandavalli',
                'kalidindi',
              ])
                DropdownMenuItem(
                  key: ValueKey('mandal-option-$id'),
                  value: id,
                  child: Text(
                    tr(
                      te: KolleruVillages.mandals
                          .firstWhere((m) => m.id == id)
                          .teluguName,
                      en: KolleruVillages.mandals
                          .firstWhere((m) => m.id == id)
                          .name,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _saving
                ? null
                : (id) => setState(() {
                    _mandalId = id;
                    _village.clear();
                  }),
            validator: (value) => value == null
                ? tr(te: 'మీ మండలం ఎంచుకోండి', en: 'Choose your mandal')
                : null,
          ),
        ),
        const SizedBox(height: 20),
        TextFormField(
          key: const ValueKey('village-input-field'),
          controller: _village,
          enabled: !_saving,
          textCapitalization: TextCapitalization.words,
          maxLength: 80,
          decoration: InputDecoration(
            labelText: tr(te: 'గ్రామం లేదా క్లస్టర్', en: 'Village or Base'),
            hintText: tr(te: 'ఉదా: సిద్ధాపురం', en: 'e.g. Siddhapuram'),
            counterText: '',
          ),
          validator: (value) =>
              (value ?? '').trim().length < 2 ||
                  (value ?? '').trim().length > 80
              ? tr(
                  te: 'గ్రామం లేదా క్లస్టర్ పేరు ఇవ్వండి',
                  en: 'Enter your village or base (2–80 characters)',
                )
              : null,
        ),
        if (_role == 'driver') ...[
          const SizedBox(height: 24),
          _vehicleFields(),
        ],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final stacked = MediaQuery.sizeOf(context).width < 620 * scale;
    final title = Text(
      tr(
        te: 'కొల్లేరు వీల్స్ రిజిస్ట్రేషన్',
        en: 'Kolleru Wheels Registration',
      ),
      style: const TextStyle(
        color: _green,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    );
    final toggle = OutlinedButton(
      key: const ValueKey('language-toggle'),
      onPressed: _saving ? null : language.toggleLanguage,
      style: OutlinedButton.styleFrom(
        foregroundColor: _green,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        shape: const StadiumBorder(),
      ),
      child: Text(tr(te: '🌐 EN', en: '🌐 తెలుగు')),
    );
    return OnboardingBackScope(
      enabled: !_saving,
      onExit: _leave,
      child: Scaffold(
        backgroundColor: const Color(0xFFF2F7F4),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: Colors.white,
          toolbarHeight: stacked ? 116 * scale.clamp(1, 2) : 80,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    key: const ValueKey('onboarding-back'),
                    tooltip: tr(te: 'రద్దు చేయండి', en: 'Cancel'),
                    onPressed: _saving ? null : _leave,
                    icon: const Icon(Icons.arrow_back, size: 24),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: title),
                ],
              ),
              if (stacked)
                Align(alignment: Alignment.centerRight, child: toggle),
            ],
          ),
          actions: stacked ? null : [toggle, const SizedBox(width: 12)],
        ),
        body: SafeArea(
          child: Form(
            key: _form,
            child: ListView(
              key: const ValueKey('registration-scroll'),
              padding: const EdgeInsets.all(20),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F3E8),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      tr(
                        te: 'కొల్లేరు డెల్టా రవాణా నెట్‌వర్క్',
                        en: 'KOLLERU DELTA TRANSPORT NETWORK',
                      ),
                      style: const TextStyle(
                        color: _green,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  tr(te: 'మీ ప్రొఫైల్ ఎంచుకోండి', en: 'Select Your Role'),
                  style: const TextStyle(
                    color: _green,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  tr(
                    te: 'కొల్లేరు డెల్టా రవాణా నెట్‌వర్క్‌లో మీరు ఎవరు?',
                    en: 'Who are you in the network?',
                  ),
                  style: const TextStyle(color: Color(0xFF365B47), height: 1.5),
                ),
                const SizedBox(height: 24),
                _roleCard(driver: false),
                const SizedBox(height: 12),
                _roleCard(driver: true),
                const SizedBox(height: 24),
                _profileForm(),
                const SizedBox(height: 22),
                KeyedSubtree(
                  key: const ValueKey('complete-profile'),
                  child: FilledButton(
                    key: const ValueKey('complete-registration-button'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onPressed: _saving ? null : _complete,
                    child: Text(
                      tr(
                        te: 'నమోదు పూర్తి చేయండి ➔',
                        en: 'Complete Registration ➔',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  tr(
                    te: '✓ ఉచిత రిజిస్ట్రేషన్ • ఎటువంటి కమిషన్ లేదు',
                    en: '✓ 100% Free Registration • Zero Commission',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _green,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
                if (_saving)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
                if (_failed)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      tr(
                        te: 'నమోదు సేవ్ కాలేదు. మళ్లీ ప్రయత్నించండి.',
                        en: 'Could not save registration. Please retry.',
                      ),
                    ),
                  ),
                if (_needsVerification)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      tr(
                        te: 'ముందుగా మీ మొబైల్ నంబర్ ధృవీకరించండి.',
                        en: 'Verify your mobile number before registering.',
                      ),
                    ),
                  ),
                TextButton(
                  key: const ValueKey('cancel-onboarding'),
                  onPressed: _saving ? null : _leave,
                  child: Text(tr(te: 'రద్దు చేయండి', en: 'Cancel')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
