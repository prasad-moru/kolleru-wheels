import 'package:flutter/material.dart';

import '../../core/localization/app_language_provider.dart';
import '../../data/models/user_profile_model.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/local_driver_repository.dart';
import '../common/language_switch_button.dart';
import '../common/mandal_village_picker.dart';
import '../driver/driver_registration_screen.dart';
import 'onboarding_navigation.dart';
import 'role_destination.dart';

class CompleteProfileScreen extends StatefulWidget {
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
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState
    extends LanguageAwareState<CompleteProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  late final _auth = widget.repository ?? AuthRepository.instance;
  String _role = 'shipper';
  String? _villageId;
  bool _saving = false;
  ({String te, String en})? _error;
  bool _validated = false;

  @override
  void onLanguageChanged() {
    if (_validated) _form.currentState?.validate();
  }

  Future<void> _complete() async {
    if (_saving) return;
    _validated = true;
    if (!_form.currentState!.validate()) return;
    if (_role == 'driver') {
      setState(() => _saving = true);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => DriverRegistrationScreen(
            repository: LocalDriverRepository(),
            verifiedPhone: widget.phone,
            initialName: _name.text.trim(),
            initialVillageId: _villageId,
            authRepository: _auth,
            completeUserProfile: true,
          ),
        ),
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final profile = await _auth.createUserProfile(
        phone: widget.phone,
        name: _name.text,
        role: 'shipper',
        villageId: _villageId,
      );
      if (!mounted) return;
      if (widget.onCompleted != null) {
        widget.onCompleted!(profile);
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) =>
                RoleDestination(profile: profile, authRepository: _auth),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = (
            te: 'సేవ్ చేయలేకపోయాము. కనెక్షన్ సరిచూసి మళ్లీ ప్రయత్నించండి.',
            en: 'Could not save profile. Check connection and retry.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _leave() async {
    if (_saving) return;
    await leaveOnboarding(context, _auth);
  }

  @override
  Widget build(BuildContext context) => OnboardingBackScope(
    enabled: !_saving,
    onExit: _leave,
    child: Scaffold(
      appBar: AppBar(
        actions: [LanguageSwitchButton(language: language, enabled: !_saving)],
        title: Text(tr(te: 'వివరాలు పూర్తి చేయండి', en: 'Complete profile')),
        leading: IconButton(
          key: const ValueKey('onboarding-back'),
          tooltip: tr(te: 'రద్దు చేయండి', en: 'Cancel'),
          onPressed: _saving ? null : _leave,
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(tr(te: 'నిర్ధారించిన ఫోన్: ${widget.phone}', en: 'Verified phone: ${widget.phone}')),
              const SizedBox(height: 20),
              TextFormField(
                key: const ValueKey('complete-name'),
                controller: _name,
                enabled: !_saving,
                autofillHints: const [AutofillHints.name],
                decoration: InputDecoration(labelText: tr(te: 'పూర్తి పేరు', en: 'Full name')),
                validator: (value) =>
                    (value?.trim().length ?? 0) < 2 ||
                        (value?.trim().length ?? 0) > 80
                    ? tr(te: 'పేరు ఇవ్వండి (2–80 అక్షరాలు)', en: 'Enter a name (2–80 characters)')
                    : null,
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  ChoiceChip(
                    key: const ValueKey('complete-shipper'),
                    label: Text(tr(te: 'రైతు లేదా వ్యాపారి', en: 'Farmer or shipper')),
                    selected: _role == 'shipper',
                    onSelected: _saving
                        ? null
                        : (_) => setState(() => _role = 'shipper'),
                  ),
                  ChoiceChip(
                    key: const ValueKey('complete-driver'),
                    label: Text(tr(te: 'డ్రైవర్', en: 'Driver')),
                    selected: _role == 'driver',
                    onSelected: _saving
                        ? null
                        : (_) => setState(() => _role = 'driver'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              MandalVillagePicker(language: language, onChanged: (id) => _villageId = id),
              const SizedBox(height: 24),
              FilledButton(
                key: const ValueKey('complete-profile'),
                onPressed: _saving ? null : _complete,
                child: Text(
                  _role == 'driver'
                      ? tr(te: 'వాహనం వివరాలు', en: 'Continue to vehicle details')
                      : tr(te: 'నమోదు పూర్తి చేయండి', en: 'Complete registration'),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                key: const ValueKey('cancel-onboarding'),
                onPressed: _saving ? null : _leave,
                child: Text(tr(te: 'రద్దు చేయండి', en: 'Cancel'), textAlign: TextAlign.center),
              ),
              if (_saving) const LinearProgressIndicator(),
              if (_error != null) Text(tr(te: _error!.te, en: _error!.en)),
            ],
          ),
        ),
      ),
    ),
  );
}
