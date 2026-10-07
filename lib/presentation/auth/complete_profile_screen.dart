import 'package:flutter/material.dart';

import '../../data/models/user_profile_model.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/local_driver_repository.dart';
import '../driver/driver_registration_screen.dart';
import '../common/mandal_village_picker.dart';
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

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  late final _auth = widget.repository ?? AuthRepository.instance;
  String _role = 'shipper';
  String? _villageId;
  bool _saving = false;
  String? _error;
  Future<void> _complete() async {
    if (_saving || !_form.currentState!.validate()) return;
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
          () => _error = 'సేవ్ చేయలేకపోయాము / Could not save profile. Check connection and retry.',
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('నమోదు / Complete Profile')),
    body: SafeArea(
      child: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('నిర్ధారించిన ఫోన్ / Verified phone: ${widget.phone}'),
            const SizedBox(height: 20),
            TextFormField(
              key: const ValueKey('complete-name'),
              controller: _name,
              enabled: !_saving,
              autofillHints: const [AutofillHints.name],
              decoration: const InputDecoration(labelText: 'పేరు / Full name'),
              validator: (value) =>
                  (value?.trim().length ?? 0) < 2 ||
                      (value?.trim().length ?? 0) > 80
                  ? 'పేరు ఇవ్వండి / Enter a name (2–80 characters)'
                  : null,
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ChoiceChip(
                  key: const ValueKey('complete-shipper'),
                  label: const Text('రైతు / వ్యాపారి (Farmer / Shipper)'),
                  selected: _role == 'shipper',
                  onSelected: _saving
                      ? null
                      : (_) => setState(() => _role = 'shipper'),
                ),
                ChoiceChip(
                  key: const ValueKey('complete-driver'),
                  label: const Text('డ్రైవర్ (Driver)'),
                  selected: _role == 'driver',
                  onSelected: _saving
                      ? null
                      : (_) => setState(() => _role = 'driver'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            MandalVillagePicker(onChanged: (id) => _villageId = id),
            const SizedBox(height: 24),
            FilledButton(
              key: const ValueKey('complete-profile'),
              onPressed: _saving ? null : _complete,
              child: Text(
                _role == 'driver'
                    ? 'వాహనం వివరాలు / Continue to vehicle details'
                    : 'నమోదు చేయండి / Complete registration',
              ),
            ),
            if (_saving) const LinearProgressIndicator(),
            if (_error != null) Text(_error!),
          ],
        ),
      ),
    ),
  );
}
