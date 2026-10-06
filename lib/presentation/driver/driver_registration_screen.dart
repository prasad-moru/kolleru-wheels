import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/villages.dart';
import '../../data/models/local_driver_profile.dart';
import '../../data/models/vehicle_type.dart';
import '../../data/repositories/local_driver_repository.dart';
import '../../data/repositories/load_request_repository.dart';
import '../common/vehicle_badge.dart';
import '../common/village_picker.dart';
import 'driver_dashboard_screen.dart';

class DriverRegistrationScreen extends StatefulWidget {
  const DriverRegistrationScreen({
    super.key,
    required this.repository,
    this.onRegistered,
    this.loadRequestRepository,
    this.verifiedPhone,
  });
  final LocalDriverRepository repository;
  final String? verifiedPhone;
  final LoadRequestRepository? loadRequestRepository;
  final ValueChanged<LocalDriverProfile>? onRegistered;
  @override
  State<DriverRegistrationScreen> createState() =>
      _DriverRegistrationScreenState();
}

class _DriverRegistrationScreenState extends State<DriverRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _number = TextEditingController();
  final _capacity = TextEditingController();
  final _specializations = <String>{};
  VehicleType _vehicle = VehicleType.boleroPickup;
  String? _villageId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.verifiedPhone != null) {
      _phone.text = widget.verifiedPhone!.substring(3);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _number.dispose();
    _capacity.dispose();
    super.dispose();
  }

  String _mobileDigits(String input) {
    final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length == 12 && digits.startsWith('91')
        ? digits.substring(2)
        : digits;
  }

  Future<void> _register() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    final village = KolleruVillages.find(_villageId)!;
    final profile = LocalDriverProfile(
      id: const Uuid().v4(),
      name: _name.text.trim(),
      phone: '+91${_mobileDigits(_phone.text)}',
      baseVillage: village,
      currentSpotVillage: village,
      vehicleType: _vehicle,
      capacityTons: double.parse(_capacity.text.trim()),
      specializations: _specializations.toList(),
      vehicleNumber: _number.text.trim().toUpperCase(),
      isAvailable: true,
    );
    try {
      await widget.repository.saveProfile(profile);
      if (!mounted) return;
      if (widget.onRegistered != null) {
        widget.onRegistered!(profile);
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => DriverDashboardScreen(
            profile: profile,
            repository: widget.repository,
            loadRequestRepository: widget.loadRequestRepository,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text(AppStrings.saveFailed)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text(AppStrings.registration)),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: AbsorbPointer(
          absorbing: _saving,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(AppStrings.localProfileNote),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('driver-name'),
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: AppStrings.fullName,
                  ),
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  validator: (value) => (value?.trim().length ?? 0) < 2
                      ? AppStrings.nameRequired
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('driver-phone'),
                  controller: _phone,
                  readOnly: widget.verifiedPhone != null,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumberNational],
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: AppStrings.mobile,
                    hintText: '9876543210 / +91 9876543210',
                  ),
                  validator: (value) =>
                      RegExp(r'^[6-9][0-9]{9}$')
                          .hasMatch(_mobileDigits(value ?? ''))
                      ? null
                      : AppStrings.phoneInvalid,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('driver-vehicle-number'),
                  controller: _number,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: AppStrings.vehicleNumber,
                    hintText: 'AP 39 AB 1234',
                  ),
                  validator: (value) =>
                      RegExp(r'^[A-Z]{2}[0-9]{1,2}[A-Z]{1,3}[0-9]{4}$')
                          .hasMatch(
                            (value ?? '').toUpperCase().replaceAll(
                              RegExp(r'[\s-]'),
                              '',
                            ),
                          )
                      ? null
                      : AppStrings.numberInvalid,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('driver-capacity'),
                  controller: _capacity,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: AppStrings.capacityTons,
                    hintText: '1.5',
                  ),
                  validator: (value) {
                    final capacity = double.tryParse(value?.trim() ?? '');
                    return capacity == null ||
                            !capacity.isFinite ||
                            capacity <= 0 ||
                            capacity > 100
                        ? AppStrings.capacityInvalid
                        : null;
                  },
                ),
                const SizedBox(height: 20),
                Text(
                  AppStrings.vehicleType,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final twoColumns =
                        constraints.maxWidth >= 340 &&
                        MediaQuery.textScalerOf(context).scale(18) <= 24;
                    final width = twoColumns
                        ? (constraints.maxWidth - 12) / 2
                        : constraints.maxWidth;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final type in VehicleType.values)
                          SizedBox(
                            width: width,
                            child: Semantics(
                              selected: _vehicle == type,
                              child: OutlinedButton(
                                key: ValueKey('register-vehicle-${type.name}'),
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: _vehicle == type
                                      ? AppColors.green
                                      : Colors.white,
                                  foregroundColor: _vehicle == type
                                      ? Colors.white
                                      : AppColors.charcoal,
                                ),
                                onPressed: () =>
                                    setState(() => _vehicle = type),
                                child: Column(
                                  children: [
                                    VehicleBadge(type: type),
                                    const SizedBox(height: 8),
                                    Text(
                                      type.label,
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),
                VillagePicker(
                  key: const ValueKey('driver-village'),
                  onChanged: (id) => _villageId = id,
                ),
                const SizedBox(height: 20),
                Text(
                  AppStrings.specializations,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in AppStrings.specializationOptions)
                      FilterChip(
                        label: Text(option),
                        selected: _specializations.contains(option),
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            _specializations.add(option);
                          } else {
                            _specializations.remove(option);
                          }
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: const ValueKey('register-driver'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.green,
                    minimumSize: const Size.fromHeight(64),
                  ),
                  onPressed: _saving ? null : _register,
                  icon: const Icon(Icons.person_add),
                  label: Text(
                    _saving ? AppStrings.saving : AppStrings.registerDriver,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
