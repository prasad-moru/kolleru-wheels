import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/villages.dart';
import '../../data/models/vehicle_type.dart';
import '../../data/repositories/mock_directory_repository.dart';
import '../common/audio_cue_button.dart';
import '../driver/visiting_card_screen.dart';

class HomeDirectoryScreen extends StatefulWidget {
  const HomeDirectoryScreen({super.key, this.repository});
  final DirectoryRepository? repository;
  @override
  State<HomeDirectoryScreen> createState() => _HomeDirectoryScreenState();
}

class _HomeDirectoryScreenState extends State<HomeDirectoryScreen> {
  late final DirectoryRepository _repository;
  String? _villageId;
  VehicleType? _vehicle;
  bool _availableOnly = false;
  bool _selectionChanged = false;
  static const _preferenceKey = 'directory_village_id';
  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? MockDirectoryRepository();
    _restoreVillage();
  }

  Future<void> _restoreVillage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_preferenceKey);
      if (mounted &&
          !_selectionChanged &&
          KolleruVillages.find(saved) != null) {
        setState(() => _villageId = saved);
      }
    } catch (_) {
      /* Storage is optional; directory remains usable. */
    }
  }

  Future<void> _selectVillage(String? id) async {
    _selectionChanged = true;
    setState(() => _villageId = id);
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = _villageId;
      if (current == null) {
        await prefs.remove(_preferenceKey);
      } else {
        await prefs.setString(_preferenceKey, current);
      }
    } catch (_) {
      /* Session selection still works without persistence. */
    }
  }

  IconData _icon(VehicleType type) => switch (type) {
    VehicleType.tractor => Icons.agriculture,
    VehicleType.eicher14ft => Icons.local_shipping,
    VehicleType.boleroPickup => Icons.airport_shuttle,
    VehicleType.tataAce || VehicleType.dost => Icons.delivery_dining,
  };
  @override
  Widget build(BuildContext context) {
    final drivers = _repository.getDrivers(
      villageId: _villageId,
      vehicleType: _vehicle,
      availableOnly: _availableOnly,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Kolleru Wheels')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              AppStrings.directory,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            const Text(AppStrings.demo),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: ValueKey(_villageId),
              initialValue: _villageId ?? '',
              isExpanded: true,
              decoration: const InputDecoration(labelText: AppStrings.village),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text(AppStrings.allVillages),
                ),
                for (final mandal in KolleruVillages.mandals)
                  for (final village in mandal.villages)
                    DropdownMenuItem(
                      value: village.id,
                      child: Text(
                        '${village.label} (${mandal.name})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
              ],
              onChanged: (value) => _selectVillage(value == '' ? null : value),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 600
                    ? 3
                    : constraints.maxWidth >= 340 &&
                          MediaQuery.textScalerOf(context).scale(18) <= 24
                    ? 2
                    : 1;
                final width =
                    (constraints.maxWidth - (columns - 1) * 12) / columns;
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
                            style: OutlinedButton.styleFrom(
                              backgroundColor: _vehicle == type
                                  ? AppColors.green
                                  : Colors.white,
                              foregroundColor: _vehicle == type
                                  ? Colors.white
                                  : AppColors.charcoal,
                              side: BorderSide(
                                color: _vehicle == type
                                    ? AppColors.green
                                    : AppColors.charcoal,
                              ),
                            ),
                            onPressed: () => setState(
                              () => _vehicle = _vehicle == type ? null : type,
                            ),
                            child: Column(
                              children: [
                                Icon(_icon(type), size: 40),
                                const SizedBox(height: 8),
                                Text(type.label, textAlign: TextAlign.center),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            TextButton(
              onPressed: () => setState(() => _vehicle = null),
              child: const Text(AppStrings.allVehicles),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(AppStrings.availableOnly),
              value: _availableOnly,
              onChanged: (value) => setState(() => _availableOnly = value),
            ),
            const AudioCueButton(),
            const SizedBox(height: 20),
            Text(
              'డ్రైవర్లు / Drivers: ${drivers.length}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (drivers.isEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(AppStrings.noDrivers),
              ),
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    _vehicle = null;
                    _availableOnly = false;
                  });
                  _selectVillage(null);
                },
                child: const Text(AppStrings.reset),
              ),
            ],
            for (final driver in drivers)
              Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => VisitingCardScreen(driver: driver),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _icon(driver.vehicleType),
                          size: 36,
                          color: AppColors.green,
                        ),
                        Text(
                          driver.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(driver.vehicleType.label),
                        Text(driver.village.label),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          color: driver.isAvailable
                              ? const Color(0xFFDFF4E8)
                              : AppColors.amber,
                          child: Text(
                            driver.isAvailable
                                ? AppStrings.available
                                : AppStrings.busy,
                            style: const TextStyle(
                              color: AppColors.charcoal,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(AppStrings.visitingCard),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
