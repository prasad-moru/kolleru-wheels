import 'package:flutter/material.dart';

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
import '../auth/session_router.dart';
import 'visiting_card_screen.dart';
import 'load_pool_board.dart';

class DriverDashboardScreen extends StatefulWidget {
  const DriverDashboardScreen({
    super.key,
    required this.profile,
    required this.repository,
    this.loadRequestRepository,
    this.authRepository,
  });
  final LocalDriverProfile profile;
  final AuthRepository? authRepository;
  final LocalDriverRepository repository;
  final LoadRequestRepository? loadRequestRepository;
  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  late LocalDriverProfile _profile;
  late final _auth = widget.authRepository ?? AuthRepository.instance;
  bool _saving = false;
  bool _syncPending = false;
  final _remoteDriver = SupabaseDriverRepository.instance;
  final _loadBoardKey = GlobalKey<LoadPoolBoardState>();
  LoadRequestRepository get _loads =>
      widget.loadRequestRepository ?? LoadRequestRepository.instance;
  String? get _operationalMandalId =>
      ProximityMatcher.mandalId(_profile.currentSpotVillage.id) ??
      ProximityMatcher.mandalId(_profile.baseVillage.id);

  Future<void> _refreshLoads() async {
    try {
      final board = _loadBoardKey.currentState;
      if (board != null) {
        await board.refresh();
      } else {
        await _loads.getActiveRequests(operationalMandalId: _operationalMandalId);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.loadFailedPool)),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
    _auth.addListener(_identityChanged);
    if (_auth.currentProfile?.role == 'driver' &&
        _auth.currentProfile?.phone == _profile.phone) {
      _syncDriver();
    }
  }

  void _identityChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _auth.removeListener(_identityChanged);
    super.dispose();
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

  Future<void> _openCard() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => VisitingCardScreen(driver: _profile.toDriverModel()),
    ));
    final updated = await widget.repository.getProfile();
    if (mounted && updated != null && updated.id == _profile.id) {
      setState(() => _profile = updated);
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
  Widget build(BuildContext context) =>
      _auth.currentProfile?.role != 'driver' ||
          _auth.currentProfile?.phone != _profile.phone
      ? SessionRouter(repository: _auth)
      : Scaffold(
          appBar: AppBar(title: const Text(AppStrings.dashboard)),
          drawer: Drawer(
            child: SafeArea(
              child: ListView(
                children: [
                  ListTile(
                    key: const ValueKey('driver-profile'),
                    leading: const Icon(Icons.person),
                    title: Text(_profile.name),
                    subtitle: Text(_profile.phone),
                  ),
                  ListTile(
                    key: const ValueKey('drawer-digital-card'),
                    leading: const Icon(Icons.badge),
                    title: const Text(
                      'విజిటింగ్ కార్డ్ / Digital Visiting Card',
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      _openCard();
                    },
                  ),
                  ListTile(
                    key: const ValueKey('drawer-logout'),
                    leading: const Icon(Icons.logout),
                    title: const Text('లాగౌట్ / Logout'),
                    onTap: () async {
                      try {
                        await _auth.signOut();
                      } catch (_) {}
                      if (!context.mounted) return;
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute<void>(
                          builder: (_) => SessionRouter(repository: _auth),
                        ),
                        (_) => false,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          body: SafeArea(
            child: RefreshIndicator(
              key: const ValueKey('dashboard-refresh'),
              color: const Color(0xFF059669),
              onRefresh: _refreshLoads,
              child: ListView(
                key: const ValueKey('dashboard-scroll'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    _profile.name,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _profile.isAvailable
                          ? const Color(0xFFECFDF5)
                          : const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _profile.isAvailable
                            ? const Color(0xFFA7F3D0)
                            : const Color(0xFFFECACA),
                        width: 0.8,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    _profile.isAvailable
                                        ? Icons.check_circle_outline
                                        : Icons.do_not_disturb_on_outlined,
                                    size: 23,
                                    color: _profile.isAvailable
                                        ? const Color(0xFF047857)
                                        : const Color(0xFFB91C1C),
                                  ),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Text(
                                      _profile.isAvailable
                                          ? AppStrings.availableForLoads
                                          : AppStrings.currentlyBusy,
                                      style: TextStyle(
                                        color: _profile.isAvailable
                                            ? const Color(0xFF065F46)
                                            : const Color(0xFF991B1B),
                                        fontSize: 17,
                                        height: 1.4,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Semantics(
                              label: _profile.isAvailable
                                  ? AppStrings.availableForLoads
                                  : AppStrings.currentlyBusy,
                              child: Switch(
                                key: const ValueKey('driver-availability'),
                                value: _profile.isAvailable,
                                activeThumbColor: Colors.white,
                                activeTrackColor: const Color(0xFF059669),
                                inactiveThumbColor: Colors.white,
                                inactiveTrackColor: const Color(0xFF64748B),
                                onChanged: _saving
                                    ? null
                                    : (value) => _save(
                                        () => widget.repository.updateAvailability(value),
                                      ),
                              ),
                            ),
                          ],
                        ),
                        if (_saving) ...[
                          const SizedBox(height: 8),
                          const Text(AppStrings.saving),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            VehicleBadge(type: _profile.vehicleType, size: 64),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _profile.vehicleType.label,
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE0F2FE),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '${AppStrings.capacity}: ${_profile.capacityTons} టన్నులు / Tons',
                                      style: const TextStyle(color: Color(0xFF0369A1), fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text('${AppStrings.baseVillage}: ${_profile.baseVillage.label}'),
                        const SizedBox(height: 16),
                        Text(AppStrings.currentLocation, style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          key: const ValueKey('current-spot'),
                          onPressed: _saving ? null : _chooseSpot,
                          icon: const Icon(Icons.edit_location_alt_outlined, size: 20),
                          label: Text(_profile.currentSpotLabel, textAlign: TextAlign.center),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const ValueKey('dashboard-visiting-card'),
                    onPressed: _saving ? null : _openCard,
                    icon: const Icon(Icons.badge_outlined),
                    label: const Text(AppStrings.digitalCard, textAlign: TextAlign.center),
                  ),
                  if (_syncPending)
                    TextButton(
                      onPressed: _saving ? null : _syncDriver,
                      child: const Text(
                        'ఫోన్‌లో సేవ్ అయింది • క్లౌడ్ సింక్ పెండింగ్ / Saved locally • cloud sync pending',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  const SizedBox(height: 28),
                  LoadPoolBoard(
                    key: _loadBoardKey,
                    callerPhone: _profile.phone,
                    operationalMandalId: _operationalMandalId,
                    vehicleType: _profile.vehicleType,
                    repository: _loads,
                  ),
                ],
              ),
            ),
          ),
        );
}
