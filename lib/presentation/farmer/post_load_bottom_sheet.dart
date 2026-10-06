import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/villages.dart';
import '../../data/models/vehicle_type.dart';
import '../../data/repositories/load_request_repository.dart';

class PostLoadBottomSheet extends StatefulWidget {
  const PostLoadBottomSheet({
    super.key,
    required this.repository,
    this.initialVillageId,
  });
  final LoadRequestRepository repository;
  final String? initialVillageId;
  @override
  State<PostLoadBottomSheet> createState() => _PostLoadBottomSheetState();
}

class _PostLoadBottomSheetState extends State<PostLoadBottomSheet> {
  final _form = GlobalKey<FormState>();
  final _pickup = TextEditingController();
  final _phone = TextEditingController();
  final _name = TextEditingController();
  String? _drop;
  VehicleType? _vehicle;
  String _material = AppStrings.materials.first;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _drop = widget.initialVillageId;
  }

  @override
  void dispose() {
    _pickup.dispose();
    _phone.dispose();
    _name.dispose();
    super.dispose();
  }

  String _digits(String input) {
    final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length == 12 && digits.startsWith('91')
        ? digits.substring(2)
        : digits;
  }

  Future<void> _post() async {
    if (_saving || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      await widget.repository.createRequest(
        posterName: _name.text.trim().isEmpty
            ? 'రైతు / Shipper'
            : _name.text.trim(),
        posterPhone: '+91${_digits(_phone.text)}',
        fromLocation: _pickup.text.trim(),
        toVillageId: _drop!,
        materialType: _material,
        vehicleTypeNeeded: _vehicle,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text(AppStrings.saveFailed)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .9,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: AbsorbPointer(
            absorbing: _saving,
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    AppStrings.urgentLoad,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(AppStrings.localLoadNote),
                  const SizedBox(height: 20),
                  TextFormField(
                    key: const ValueKey('load-pickup'),
                    controller: _pickup,
                    decoration: const InputDecoration(
                      labelText: AppStrings.pickupSpot,
                    ),
                    validator: (value) => (value?.trim().isEmpty ?? true)
                        ? AppStrings.pickupRequired
                        : null,
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final spot in ['కైకలూరు మార్కెట్', 'దుకాణం వద్ద'])
                        ActionChip(
                          label: Text(spot),
                          onPressed: () => _pickup.text = spot,
                          padding: const EdgeInsets.all(8),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('load-drop'),
                    initialValue: _drop,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: AppStrings.dropVillage,
                    ),
                    validator: (id) =>
                        id == null ? AppStrings.villageRequired : null,
                    items: [
                      for (final village in KolleruVillages.all)
                        DropdownMenuItem(
                          value: village.id,
                          child: Text(
                            village.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (id) => _drop = id,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    AppStrings.material,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final material in AppStrings.materials)
                        ChoiceChip(
                          label: Text(material),
                          selected: _material == material,
                          padding: const EdgeInsets.all(8),
                          onSelected: (_) =>
                              setState(() => _material = material),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<VehicleType>(
                    hint: const Text(AppStrings.allVehicles),
                    initialValue: _vehicle,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: AppStrings.vehicleType,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text(AppStrings.allVehicles),
                      ),
                      for (final type in VehicleType.values)
                        DropdownMenuItem(value: type, child: Text(type.label)),
                    ],
                    onChanged: (type) => _vehicle = type,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: AppStrings.shipperName,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey('load-phone'),
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: AppStrings.shipperPhone,
                      hintText: '9876543210',
                    ),
                    validator: (value) =>
                        RegExp(r'^[6-9][0-9]{9}$')
                            .hasMatch(_digits(value ?? ''))
                        ? null
                        : AppStrings.phoneInvalid,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    key: const ValueKey('post-load-submit'),
                    onPressed: _saving ? null : _post,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.green,
                      minimumSize: const Size.fromHeight(64),
                    ),
                    icon: const Icon(Icons.campaign),
                    label: Text(
                      _saving ? AppStrings.saving : AppStrings.postNeed,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
