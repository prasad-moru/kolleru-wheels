import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/villages.dart';
import '../../core/utils/proximity_matcher.dart';
import '../../data/models/vehicle_type.dart';
import '../../data/models/local_driver_profile.dart';
import '../../data/repositories/local_driver_repository.dart';
import '../../data/repositories/load_request_repository.dart';
import '../../data/repositories/mock_directory_repository.dart';
import '../common/audio_cue_button.dart';
import '../common/call_button.dart';
import '../common/vehicle_badge.dart';
import '../driver/visiting_card_screen.dart';
import '../driver/driver_mode_screen.dart';
import 'post_load_bottom_sheet.dart';

class HomeDirectoryScreen extends StatefulWidget {
  const HomeDirectoryScreen({
    super.key,
    this.repository,
    this.localDriverRepository,
    this.onDriverMode,
    this.loadRequestRepository,
  });
  final DirectoryRepository? repository;
  final LocalDriverRepository? localDriverRepository;
  final VoidCallback? onDriverMode;
  final LoadRequestRepository? loadRequestRepository;
  @override
  State<HomeDirectoryScreen> createState() => _HomeDirectoryScreenState();
}

class _HomeDirectoryScreenState extends State<HomeDirectoryScreen> {
  late final DirectoryRepository _repository;
  late final LocalDriverRepository _localRepository;
  LocalDriverProfile? _localProfile;
  bool _profileLoadFailed = false;
  String? _villageId;
  VehicleType? _vehicle;
  bool _availableOnly = false;
  bool _selectionChanged = false;
  static const _preferenceKey = 'directory_village_id';
  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? MockDirectoryRepository();
    _localRepository = widget.localDriverRepository ?? LocalDriverRepository();
    _loadLocalProfile();
    _restoreVillage();
  }

  Future<void> _loadLocalProfile() async {
    try {
      final profile = await _localRepository.getProfile();
      if (mounted) {
        setState(() {
          _localProfile = profile;
          _profileLoadFailed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _profileLoadFailed = true);
    }
  }

  Future<void> _openDriverMode() async {
    if (widget.onDriverMode != null) {
      widget.onDriverMode!();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DriverModeScreen(
          repository: _localRepository,
          loadRequestRepository: widget.loadRequestRepository,
        ),
      ),
    );
    if (mounted) await _loadLocalProfile();
  }

  Future<void> _postLoad() async {
    final posted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PostLoadBottomSheet(
        repository:
            widget.loadRequestRepository ?? LoadRequestRepository.instance,
        initialVillageId: _villageId,
      ),
    );
    if (mounted && posted == true) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(AppStrings.postedNeed)));
    }
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

  @override
  Widget build(BuildContext context) {
    final drivers = [
      ..._repository.getDrivers(
        vehicleType: _vehicle,
        availableOnly: _availableOnly,
      ),
    ];
    final local = _localProfile;
    if (local != null &&
        (_vehicle == null || local.vehicleType == _vehicle) &&
        (!_availableOnly || local.isAvailable)) {
      drivers.insert(0, local.toDriverModel());
    }
    final headings = <String, String>{};
    if (_villageId != null) {
      final matches = ProximityMatcher.rank(drivers, _villageId!);
      for (final tier in ProximityTier.values) {
        final group = matches.where((m) => m.tier == tier);
        if (group.isNotEmpty) {
          headings[group.first.driver.id] = switch (tier) {
            ProximityTier.local => AppStrings.tierLocal,
            ProximityTier.mandal => AppStrings.tierMandal,
            ProximityTier.deltaBelt => AppStrings.tierDelta,
          };
        }
      }
      final busy = drivers.where((d) => !d.isAvailable).toList();
      if (busy.isNotEmpty) headings[busy.first.id] = AppStrings.busyDrivers;
      drivers
        ..clear()
        ..addAll(matches.map((m) => m.driver))
        ..addAll(busy);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kolleru Wheels'),
        actions: [
          IconButton(
            key: const ValueKey('driver-mode'),
            tooltip: AppStrings.driverMode,
            onPressed: _openDriverMode,
            icon: const Icon(Icons.person_pin),
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            children: [
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Kolleru Wheels',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.person_pin),
                title: const Text(AppStrings.driverMode),
                onTap: () {
                  Navigator.of(context).pop();
                  _openDriverMode();
                },
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              AppStrings.directory,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('post-urgent-load'),
              onPressed: _postLoad,
              icon: const Icon(Icons.campaign, size: 28),
              label: const Text(
                AppStrings.urgentLoad,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),
            const Text(AppStrings.demo),
            if (_profileLoadFailed)
              TextButton(
                onPressed: _loadLocalProfile,
                child: const Text(
                  '${AppStrings.loadFailed} — ${AppStrings.retry}',
                ),
              ),
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
                                VehicleBadge(type: type, size: 88),
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
            for (final driver in drivers) ...[
              if (headings.containsKey(driver.id))
                Container(
                  margin: const EdgeInsets.only(top: 20, bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDFF4E8),
                    border: Border.all(color: AppColors.charcoal, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    headings[driver.id]!,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
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
                        VehicleBadge(type: driver.vehicleType, size: 96),
                        Text(
                          driver.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(driver.vehicleType.label),
                        Text(
                          '${AppStrings.capacity}: ${driver.capacity}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            for (final tag in driver.specializations)
                              Chip(
                                label: Text(tag),
                                backgroundColor: const Color(0xFFFFF1BF),
                              ),
                          ],
                        ),
                        Text(driver.village.label),
                        Text(
                          '${AppStrings.currentSpot}: ${driver.currentSpot}',
                        ),
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
                        const SizedBox(height: 12),
                        CallButton(phone: driver.phone, isDemo: driver.isDemo),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
