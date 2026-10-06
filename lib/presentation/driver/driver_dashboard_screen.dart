import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/driver_spots.dart';
import '../../core/constants/villages.dart';
import '../../core/utils/proximity_matcher.dart';
import '../../data/models/local_driver_profile.dart';
import '../../data/repositories/local_driver_repository.dart';
import '../../data/repositories/load_request_repository.dart';
import '../../data/repositories/supabase_driver_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../common/vehicle_badge.dart';
import '../farmer/home_directory_screen.dart';
import 'visiting_card_screen.dart';
import 'load_pool_board.dart';

class DriverDashboardScreen extends StatefulWidget {
  const DriverDashboardScreen({
    super.key,
    required this.profile,
    required this.repository,
    this.loadRequestRepository,
  });
  final LocalDriverProfile profile;
  final LocalDriverRepository repository;
  final LoadRequestRepository? loadRequestRepository;
  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  late LocalDriverProfile _profile;
  bool _saving = false;
  bool _syncPending = false;
  final _remoteDriver = SupabaseDriverRepository.instance;
  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
    _syncDriver();
  }

  Future<void> _syncDriver() async {
    if (!_remoteDriver.isConfigured) return;
    try {
      await _remoteDriver.upsertDriver(_profile.toDriverModel());
      if (mounted) setState(() => _syncPending = _remoteDriver.syncPending);
    } catch (_) {
      if (mounted) setState(() => _syncPending = true);
    }
  }

  Future<void> _save(Future<LocalDriverProfile> Function() update) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final updated = await update();
      if (mounted) setState(() => _profile = updated);
      await _syncDriver();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text(AppStrings.saveFailed)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _chooseSpot() async {
    if (_saving) return;
    final spot = await showModalBottomSheet<DriverSpot>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  AppStrings.currentLocation,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final spot in DriverSpots.all)
                      ListTile(
                        key: ValueKey('spot-${spot.label}'),
                        minVerticalPadding: 16,
                        leading: const Icon(Icons.location_on),
                        title: Text(spot.label),
                        selected: spot.label == _profile.currentSpotLabel,
                        onTap: () => Navigator.of(context).pop(spot),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || spot == null) return;
    await _save(
      () => widget.repository.updateCurrentSpot(
        KolleruVillages.find(spot.villageId)!,
        label: spot.label,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(AppStrings.dashboard),
      actions: [
        if (AuthRepository.instance.currentProfile != null)
          IconButton(
            tooltip: 'లాగ్ అవుట్ / Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              try {
                await AuthRepository.instance.signOut();
              } catch (_) {
                /* Local sign-out completed. */
              }
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute<void>(
                  builder: (_) => const HomeDirectoryScreen(),
                ),
                (_) => false,
              );
            },
          ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_profile.name, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _profile.isAvailable ? AppColors.green : AppColors.busyRed,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(
                  _profile.isAvailable
                      ? Icons.check_circle
                      : Icons.do_not_disturb_on,
                  size: 48,
                  color: Colors.white,
                ),
                const SizedBox(height: 12),
                Text(
                  _profile.isAvailable
                      ? AppStrings.availableForLoads
                      : AppStrings.currentlyBusy,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Semantics(
                  label: _profile.isAvailable
                      ? AppStrings.availableForLoads
                      : AppStrings.currentlyBusy,
                  child: Transform.scale(
                    scale: 1.4,
                    child: Switch(
                      key: const ValueKey('driver-availability'),
                      value: _profile.isAvailable,
                      activeThumbColor: Colors.white,
                      activeTrackColor: AppColors.charcoal,
                      inactiveThumbColor: Colors.white,
                      inactiveTrackColor: AppColors.charcoal,
                      onChanged: _saving
                          ? null
                          : (value) => _save(
                              () => widget.repository.updateAvailability(value),
                            ),
                    ),
                  ),
                ),
                if (_saving)
                  const Text(
                    AppStrings.saving,
                    style: TextStyle(color: Colors.white),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            AppStrings.currentLocation,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: ActionChip(
              key: const ValueKey('current-spot'),
              avatar: const Icon(Icons.edit_location_alt),
              label: Text(_profile.currentSpotLabel),
              padding: const EdgeInsets.all(12),
              onPressed: _saving ? null : _chooseSpot,
            ),
          ),
          const SizedBox(height: 20),
          VehicleBadge(type: _profile.vehicleType, size: 112),
          Text(
            _profile.vehicleType.label,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text('${AppStrings.baseVillage}: ${_profile.baseVillage.label}'),
          Text(
            '${AppStrings.capacity}: ${_profile.capacityTons} టన్నులు / Tons',
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const ValueKey('dashboard-visiting-card'),
            onPressed: _saving
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          VisitingCardScreen(driver: _profile.toDriverModel()),
                    ),
                  ),
            icon: const Icon(Icons.badge),
            label: const Text(
              AppStrings.digitalCard,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('farmer-view'),
            onPressed: _saving
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => HomeDirectoryScreen(
                        localDriverRepository: widget.repository,
                        loadRequestRepository: widget.loadRequestRepository,
                        onDriverMode: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),
            icon: const Icon(Icons.agriculture),
            label: const Text(AppStrings.farmerView),
          ),
          const SizedBox(height: 16),
          const Text(AppStrings.localProfileNote),
          if (_syncPending)
            TextButton(
              onPressed: _saving ? null : _syncDriver,
              child: const Text(
                'ఫోన్‌లో సేవ్ అయింది • క్లౌడ్ సింక్ పెండింగ్ / Saved locally • cloud sync pending',
              ),
            ),
          const SizedBox(height: 24),
          LoadPoolBoard(
            callerPhone: _profile.phone,
            operationalMandalId:
                ProximityMatcher.mandalId(_profile.currentSpotVillage.id) ??
                ProximityMatcher.mandalId(_profile.baseVillage.id),
            repository:
                widget.loadRequestRepository ?? LoadRequestRepository.instance,
          ),
        ],
      ),
    ),
  );
}
