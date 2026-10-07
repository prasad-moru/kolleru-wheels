import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/villages.dart';
import '../../core/utils/proximity_matcher.dart';
import '../../data/models/vehicle_type.dart';
import '../../data/models/driver_model.dart';
import '../../data/repositories/supabase_driver_repository.dart';
import '../../data/repositories/supabase_load_request_repository.dart';
import '../../data/repositories/local_driver_repository.dart';
import '../../data/repositories/load_request_repository.dart';
import '../../data/repositories/mock_directory_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../auth/session_router.dart';
import '../common/audio_cue_button.dart';
import '../common/call_button.dart';
import '../common/vehicle_badge.dart';
import '../driver/visiting_card_screen.dart';
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
  late final AuthRepository _auth;
  List<DriverModel>? _liveDrivers;
  late final SupabaseDriverRepository _remoteDrivers;
  bool _remoteLoading = false;
  bool _cachedDrivers = false;
  String? _villageId;
  VehicleType? _vehicle;
  final bool _availableOnly = true;
  bool _selectionChanged = false;
  static const _preferenceKey = 'directory_village_id';
  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? MockDirectoryRepository();
    _auth = widget.authRepository ?? AuthRepository.instance;
    _auth.addListener(_identityChanged);
    _remoteDrivers =
        widget.remoteDriverRepository ?? SupabaseDriverRepository.instance;
    if (_auth.currentProfile?.role != 'shipper') return;
    if (widget.repository == null || widget.remoteDriverRepository != null) {
      _fetchDrivers();
    }
    _restoreVillage();
  }

  void _identityChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _auth.removeListener(_identityChanged);
    super.dispose();
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

  Future<void> _logout() async {
    try {
      await _auth.signOut();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => SessionRouter(repository: _auth)),
      (_) => false,
    );
  }

  Future<void> _myLoads() async {
    final phone = _auth.currentProfile!.phone;
    final repository =
        widget.loadRequestRepository ?? LoadRequestRepository.instance;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .7,
          child: FutureBuilder(
            future: repository.getActiveRequests(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(child: Text(AppStrings.loadFailed));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final requests = snapshot.data!
                  .where((r) => r.posterPhone == phone)
                  .toList();
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text('My Posted Loads'),
                  if (requests.isEmpty) const Text('No active posts'),
                  for (final request in requests)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          '${request.fromLocation} -> ${request.toVillage.label}\n${request.materialType}',
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _postLoad() async {
    final posted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PostLoadBottomSheet(
        repository:
            widget.loadRequestRepository ?? LoadRequestRepository.instance,
        initialVillageId: _villageId,
        posterPhone: _auth.currentProfile!.phone,
        posterName: _auth.currentProfile!.name,
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
    if (_auth.currentProfile?.role != 'shipper') {
      return SessionRouter(repository: _auth);
    }
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
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            children: [
              ListTile(
                key: const ValueKey('farmer-profile'),
                leading: const Icon(Icons.person),
                title: Text(_auth.currentProfile!.name),
                subtitle: Text(_auth.currentProfile!.phone),
              ),
              ListTile(
                key: const ValueKey('my-posted-loads'),
                leading: const Icon(Icons.inventory),
                title: const Text('My Posted Loads'),
                onTap: () {
                  Navigator.of(context).pop();
                  _myLoads();
                },
              ),
              ListTile(
                key: const ValueKey('drawer-logout'),
                leading: const Icon(Icons.logout),
                title: const Text('Logout'),
                onTap: () {
                  Navigator.of(context).pop();
                  _logout();
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
