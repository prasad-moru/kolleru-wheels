import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/villages.dart';
import '../../core/utils/proximity_matcher.dart';
import '../../data/models/vehicle_type.dart';
import '../../data/models/local_driver_profile.dart';
import '../../data/models/driver_model.dart';
import '../../data/repositories/supabase_driver_repository.dart';
import '../../data/repositories/supabase_load_request_repository.dart';
import '../../data/repositories/offline_table_store.dart';
import '../../data/repositories/local_driver_repository.dart';
import '../../data/repositories/load_request_repository.dart';
import '../../data/repositories/mock_directory_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../auth/phone_otp_screen.dart';
import '../auth/role_destination.dart';
import '../admin/admin_dashboard_screen.dart';
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
    this.remoteDriverRepository,
    this.authRepository,
  });
  final DirectoryRepository? repository;
  final LocalDriverRepository? localDriverRepository;
  final VoidCallback? onDriverMode;
  final LoadRequestRepository? loadRequestRepository;
  final SupabaseDriverRepository? remoteDriverRepository;
  final AuthRepository? authRepository;
  @override
  State<HomeDirectoryScreen> createState() => _HomeDirectoryScreenState();
}

class _HomeDirectoryScreenState extends State<HomeDirectoryScreen> {
  late final DirectoryRepository _repository;
  late final LocalDriverRepository _localRepository;
  late final AuthRepository _auth;
  LocalDriverProfile? _localProfile;
  List<DriverModel>? _liveDrivers;
  late final SupabaseDriverRepository _remoteDrivers;
  bool _remoteLoading = false;
  bool _cachedDrivers = false;
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
    _auth = widget.authRepository ?? AuthRepository.instance;
    _remoteDrivers =
        widget.remoteDriverRepository ?? SupabaseDriverRepository.instance;
    if (widget.repository == null || widget.remoteDriverRepository != null) {
      _fetchDrivers();
    }
    _loadLocalProfile();
    _restoreVillage();
  }

  Future<void> _fetchDrivers() async {
    if (_remoteLoading) return;
    setState(() => _remoteLoading = true);
    try {
      final drivers = await _remoteDrivers.getAvailableDrivers();
      if (mounted) {
        setState(() {
          _liveDrivers = drivers;
          _cachedDrivers = _remoteDrivers.usingCache;
        });
      }
    } catch (_) {
      /* Static/local directory still works if the cache is damaged. */
    } finally {
      if (mounted) setState(() => _remoteLoading = false);
    }
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
    if (!_auth.isMock && _auth.currentProfile?.role != 'driver') {
      await _openSignIn();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DriverModeScreen(
          repository: _localRepository,
          verifiedPhone: _auth.currentProfile?.role == 'driver'
              ? _auth.currentProfile?.phone
              : null,
          loadRequestRepository: widget.loadRequestRepository,
        ),
      ),
    );
    if (mounted) {
      await _loadLocalProfile();
      await _fetchDrivers();
    }
  }

  Future<void> _openSignIn() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhoneOtpScreen(
          repository: _auth,
          onVerified: (profile) => Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => RoleDestination(profile: profile),
            ),
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openDigitalCard() async {
    try {
      final driver = await _localRepository.getProfile();
      if (!mounted) return;
      if (driver == null || driver.phone != _auth.currentProfile?.phone) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'ముందుగా డ్రైవర్ నమోదు పూర్తి చేయండి / Complete driver registration first.',
            ),
          ),
        );
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => VisitingCardScreen(driver: driver.toDriverModel()),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text(AppStrings.loadFailed)));
      }
    }
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
      final pool =
          widget.loadRequestRepository ?? LoadRequestRepository.instance;
      final pending = pool is SupabaseLoadRequestRepository && pool.syncPending;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pending
                ? 'ఫోన్‌లో సేవ్ అయింది / Saved locally. Waiting for cloud sync.'
                : AppStrings.postedNeed,
          ),
        ),
      );
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
      ...(_liveDrivers?.isNotEmpty == true
          ? _liveDrivers!.where(
              (d) =>
                  (_vehicle == null || d.vehicleType == _vehicle) &&
                  (!_availableOnly || d.isAvailable),
            )
          : _repository.getDrivers(
              vehicleType: _vehicle,
              availableOnly: _availableOnly,
            )),
    ];
    final local = _localProfile;
    if (local != null &&
        (_vehicle == null || local.vehicleType == _vehicle) &&
        (!_availableOnly || local.isAvailable)) {
      drivers.insert(0, local.toDriverModel());
      drivers.removeWhere(
        (d) =>
            d.id != local.id &&
            d.id == OfflineTableStore.cloudId('drivers', local.id),
      );
    }
    final headings = <String, String>{};
    if (_villageId != null) {
      final result = ProximityMatcher.match(
        drivers,
        KolleruVillages.find(_villageId)!,
      );
      final sections = {
        AppStrings.tierLocal: result.tier1,
        AppStrings.tierMandal: result.tier2,
        AppStrings.tierDelta: result.tier3,
      };
      for (final section in sections.entries) {
        if (section.value.isNotEmpty) {
          headings[section.value.first.id] = section.key;
        }
      }
      final busy = drivers.where((d) => !d.isAvailable).toList();
      if (busy.isNotEmpty) headings[busy.first.id] = AppStrings.busyDrivers;
      drivers
        ..clear()
        ..addAll([...result.tier1, ...result.tier2, ...result.tier3])
        ..addAll(busy);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kolleru Wheels'),
        actions: [
          IconButton(
            tooltip: 'రిఫ్రెష్ / Refresh',
            onPressed: _remoteLoading ? null : _fetchDrivers,
            icon: const Icon(Icons.refresh),
          ),
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
              if (_auth.currentProfile == null)
                ListTile(
                  key: const ValueKey('drawer-login'),
                  leading: const Icon(Icons.login),
                  title: const Text('లాగిన్ / నమోదు (Login / Sign in)'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _openSignIn();
                  },
                ),
              if (_auth.currentProfile?.role == 'driver') ...[
                ListTile(
                  key: const ValueKey('drawer-driver-dashboard'),
                  leading: const Icon(Icons.person_pin),
                  title: const Text('డ్రైవర్ డ్యాష్‌బోర్డ్ (Driver Dashboard)'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _openDriverMode();
                  },
                ),
                ListTile(
                  key: const ValueKey('drawer-digital-card'),
                  leading: const Icon(Icons.badge),
                  title: const Text('విజిటింగ్ కార్డ్ (Digital Card)'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _openDigitalCard();
                  },
                ),
              ],
              if (_auth.currentProfile?.role == 'shipper') ...[
                ListTile(
                  key: const ValueKey('drawer-farmer-view'),
                  leading: const Icon(Icons.agriculture),
                  title: const Text('రైతు వీక్షణ (Farmer View)'),
                  onTap: () => Navigator.of(context).pop(),
                ),
                ListTile(
                  key: const ValueKey('drawer-post-load'),
                  leading: const Icon(Icons.campaign),
                  title: const Text('అత్యవసర లోడ్ పోస్ట్ చేయండి (Post Load)'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _postLoad();
                  },
                ),
              ],
              if (_auth.currentProfile?.role == 'admin')
                ListTile(
                  key: const ValueKey('drawer-admin-monitor'),
                  selected: true,
                  selectedColor: Colors.white,
                  selectedTileColor: AppColors.green,
                  leading: const Icon(Icons.admin_panel_settings),
                  title: const Text(
                    'నిర్వాహకుల ప్యానెల్ / Admin Monitor',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            AdminDashboardScreen(authRepository: _auth),
                      ),
                    );
                  },
                ),
              if (_auth.currentProfile != null)
                ListTile(
                  key: const ValueKey('drawer-logout'),
                  leading: const Icon(Icons.logout),
                  title: const Text('లాగౌట్ (Logout)'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    try {
                      await _auth.signOut();
                    } catch (_) {
                      /* Local identity has been cleared. */
                    }
                    if (mounted) setState(() {});
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
            if (_remoteLoading) const LinearProgressIndicator(),
            Text(
              _liveDrivers?.isNotEmpty == true
                  ? (_cachedDrivers
                        ? 'సేవ్ చేసిన వాహనాలు / Cached drivers'
                        : 'లైవ్ వాహనాలు / Live drivers')
                  : AppStrings.demo,
            ),
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
