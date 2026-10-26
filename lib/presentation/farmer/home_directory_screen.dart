import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_strings.dart';
import '../../core/localization/app_language_provider.dart';
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
import '../directory/widgets/connect_gate.dart';
import '../common/driver_directory_card.dart';
import '../driver/visiting_card_screen.dart';
import 'post_load_bottom_sheet.dart';
import 'directory_states.dart';

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

class _HomeDirectoryScreenState
    extends LanguageAwareState<HomeDirectoryScreen> {
  late final DirectoryRepository _repository;
  late final AuthRepository _auth;
  List<DriverModel>? _liveDrivers;
  late final SupabaseDriverRepository _remoteDrivers;
  bool _remoteLoading = false;
  bool _cachedDrivers = false;
  String? _villageId;
  String? _mandalId;
  VehicleType? _vehicle;
  bool _selectionChanged = false;
  static const _green = Color(0xFF0A6836);
  final _search = TextEditingController();
  bool _searching = false;
  int _tab = 0;
  List<String> _history = [];
  String? _historyIdentity;
  String get _historyKey =>
      'directory_calls_${_auth.currentProfile?.phone ?? 'guest'}';
  static const _preferenceKey = 'directory_village_id';
  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? MockDirectoryRepository();
    _auth = widget.authRepository ?? AuthRepository.instance;
    _auth.addListener(_identityChanged);
    _historyIdentity = _historyKey;
    _remoteDrivers =
        widget.remoteDriverRepository ?? SupabaseDriverRepository.instance;
    if (_auth.currentProfile?.role != 'shipper' && !_auth.isGuest) return;
    if (widget.repository == null || widget.remoteDriverRepository != null) {
      _fetchDrivers();
    }
    _restoreVillage();
    _restoreHistory();
  }

  void _identityChanged() {
    if (!mounted) return;
    if (_historyIdentity != _historyKey) {
      _historyIdentity = _historyKey;
      _history = [];
      _restoreHistory();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _auth.removeListener(_identityChanged);
    _search.dispose();
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

  void _openSignIn() {
    _auth.endGuestMode();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => SessionRouter(repository: _auth)),
      (_) => false,
    );
  }

  Future<void> _myLoads() async {
    if (_auth.currentProfile?.role != 'shipper') {
      _openSignIn();
      return;
    }
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
                return Center(
                  child: Text(language.label(AppStrings.loadFailed)),
                );
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
                  Text(
                    tr(te: 'నేను పోస్ట్ చేసిన లోడ్లు', en: 'My Posted Loads'),
                  ),
                  if (requests.isEmpty)
                    Text(
                      tr(te: 'ప్రస్తుతం లోడ్లు లేవు', en: 'No active posts'),
                    ),
                  for (final request in requests)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          '${request.fromLocation} -> ${tr(te: request.toVillage.teluguName, en: request.toVillage.name)}\n${request.materialType}',
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
    if (_auth.currentProfile?.role != 'shipper') {
      _openSignIn();
      return;
    }
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
                ? tr(
                    te: 'ఫోన్‌లో సేవ్ అయింది. క్లౌడ్ సమకాలీకరణ కోసం వేచి ఉంది.',
                    en: 'Saved locally. Waiting for cloud sync.',
                  )
                : language.label(AppStrings.postedNeed),
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

  void _resetFilters() {
    setState(() {
      _vehicle = null;
      _mandalId = null;
      _search.clear();
    });
    _selectVillage(null);
  }

  Future<bool> _requireContact() async {
    if (!_auth.isGuest && _auth.currentProfile != null) return true;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AppLanguageScope(
        language: language,
        child: ConnectGate(auth: _auth),
      ),
    );
    if (!mounted) return false;
    if (_auth.onboardingPhone != null) {
      _openSignIn();
      return false;
    }
    return result == true && _auth.currentProfile != null;
  }

  Future<void> _restoreHistory() async {
    final key = _historyKey;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted && key == _historyKey) {
        setState(() => _history = prefs.getStringList(key) ?? []);
      }
    } catch (_) {
      /* Call history is optional offline storage. */
    }
  }

  Future<void> _rememberCall(DriverModel driver) async {
    setState(
      () => _history = [
        driver.id,
        ..._history.where((id) => id != driver.id),
      ].take(30).toList(),
    );
    try {
      await (await SharedPreferences.getInstance()).setStringList(
        _historyKey,
        _history,
      );
    } catch (_) {
      /* Keep this session's history if storage is unavailable. */
    }
  }

  Widget _chip({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      key: key,
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      backgroundColor: Colors.white,
      selectedColor: _green,
      labelStyle: TextStyle(
        color: selected ? Colors.white : _green,
        fontWeight: FontWeight.w600,
      ),
      shape: const StadiumBorder(),
      side: const BorderSide(color: Color(0xFFBDE5CE)),
      onSelected: (_) => onTap(),
    ),
  );

  Widget _mandalFilters() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: Row(
      children: [
        for (final id in <String?>[
          null,
          'kaikaluru',
          'akividu',
          'bhimavaram',
          'mandavalli',
          'kalidindi',
        ])
          _chip(
            key: ValueKey('mandal-${id ?? 'all'}'),
            label: id == null
                ? tr(te: 'అన్నీ', en: 'All')
                : tr(
                    te: KolleruVillages.mandals
                        .firstWhere((m) => m.id == id)
                        .teluguName,
                    en: KolleruVillages.mandals
                        .firstWhere((m) => m.id == id)
                        .name,
                  ),
            selected: _mandalId == id,
            onTap: () {
              setState(() => _mandalId = id);
              _selectVillage(null);
            },
          ),
      ],
    ),
  );

  String _vehicleLabel(VehicleType type) => switch (type) {
    VehicleType.boleroPickup => tr(te: 'బొలెరో 2.5ట', en: 'Bolero 2.5T'),
    VehicleType.miniTruck709 => tr(
      te: '709 మినీ లారీ 5ట',
      en: '709 Mini Truck 5T',
    ),
    VehicleType.tipper => tr(te: 'టిప్పర్ 8ట+', en: 'Tipper 8T+'),
    _ => tr(te: type.teluguName, en: type.englishName),
  };

  Widget _vehicleFilters() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: Row(
      children: [
        for (final type in [
          VehicleType.boleroPickup,
          VehicleType.miniTruck709,
          VehicleType.tipper,
          VehicleType.tataAce,
          VehicleType.dost,
          VehicleType.eicher14ft,
          VehicleType.tractor,
        ])
          _chip(
            key: ValueKey('vehicle-${type.name}'),
            label: _vehicleLabel(type),
            selected: _vehicle == type,
            onTap: () =>
                setState(() => _vehicle = _vehicle == type ? null : type),
          ),
      ],
    ),
  );

  Widget _header() => Row(
    children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _green,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Text(
          'KW',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr(te: 'వాహనాల డైరెక్టరీ', en: 'Vehicle Directory'),
              style: const TextStyle(
                color: _green,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              tr(
                te: 'కొల్లేరు వీల్స్ • డెల్టా రవాణా',
                en: 'Kolleru Wheels • Delta Transport',
              ),
              style: const TextStyle(fontSize: 11, color: Color(0xFF365B47)),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _languageToggle() => OutlinedButton(
    key: const ValueKey('language-toggle'),
    onPressed: language.toggleLanguage,
    style: OutlinedButton.styleFrom(
      foregroundColor: _green,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      shape: const StadiumBorder(),
    ),
    child: Text(tr(te: '🌐 EN', en: '🌐 తెలుగు')),
  );

  Widget _drawer() => Drawer(
    child: SafeArea(
      child: ListView(
        children: [
          if (_auth.isGuest)
            ListTile(
              key: const ValueKey('guest-sign-in'),
              leading: const Icon(Icons.login),
              title: Text(language.label(AppStrings.signIn)),
              onTap: () {
                Navigator.of(context).pop();
                _openSignIn();
              },
            )
          else ...[
            ListTile(
              key: const ValueKey('farmer-profile'),
              leading: const Icon(Icons.person),
              title: Text(language.label(_auth.currentProfile!.name)),
              subtitle: Text(_auth.currentProfile!.phone),
            ),
            ListTile(
              key: const ValueKey('my-posted-loads'),
              leading: const Icon(Icons.inventory),
              title: Text(
                tr(te: 'నేను పోస్ట్ చేసిన లోడ్లు', en: 'My Posted Loads'),
              ),
              onTap: () {
                Navigator.of(context).pop();
                _myLoads();
              },
            ),
            ListTile(
              key: const ValueKey('drawer-logout'),
              leading: const Icon(Icons.logout),
              title: Text(tr(te: 'లాగ్ అవుట్', en: 'Logout')),
              onTap: () {
                Navigator.of(context).pop();
                _logout();
              },
            ),
          ],
        ],
      ),
    ),
  );

  Widget _profile() => ListView(
    key: const ValueKey('directory-profile'),
    padding: const EdgeInsets.all(24),
    children: [
      const Icon(Icons.person_outline, size: 48, color: _green),
      const SizedBox(height: 16),
      Text(
        _auth.isGuest
            ? tr(te: 'అతిథి', en: 'Guest')
            : language.label(_auth.currentProfile!.name),
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      if (_auth.currentProfile != null) Text(_auth.currentProfile!.phone),
      const SizedBox(height: 16),
      if (_auth.isGuest)
        FilledButton(
          onPressed: _openSignIn,
          child: Text(language.label(AppStrings.signIn)),
        )
      else ...[
        OutlinedButton(
          onPressed: _myLoads,
          child: Text(
            tr(te: 'నేను పోస్ట్ చేసిన లోడ్లు', en: 'My Posted Loads'),
          ),
        ),
        OutlinedButton(
          onPressed: _logout,
          child: Text(tr(te: 'లాగ్ అవుట్', en: 'Logout')),
        ),
      ],
    ],
  );

  Widget _callHistory(List<DriverModel> drivers) => ListView(
    key: const ValueKey('directory-call-history'),
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        tr(te: 'నా కాల్స్', en: 'Call History'),
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      Text(
        tr(
          te: 'ఈ ఫోన్ నుంచి డయలర్‌లో తెరిచిన పరిచయాలు.',
          en: 'Contacts opened in the dialer from this device.',
        ),
      ),
      const SizedBox(height: 16),
      if (_history.isEmpty)
        Text(tr(te: 'ఇంకా కాల్స్ లేవు', en: 'No calls yet')),
      for (final id in _history)
        for (final driver in drivers.where((d) => d.id == id))
          ListTile(
            leading: const Icon(Icons.call_outlined, size: 24, color: _green),
            title: Text(language.label(driver.name)),
            subtitle: Text(driver.phone),
          ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (_auth.currentProfile?.role != 'shipper' && !_auth.isGuest) {
      return SessionRouter(repository: _auth);
    }
    // With no configured backend and no cache, retain the offline demo directory.
    final demoFallback =
        _liveDrivers?.isEmpty == true &&
        !_remoteDrivers.isConfigured &&
        widget.remoteDriverRepository == null;
    final allDrivers = demoFallback
        ? _repository.getDrivers()
        : _liveDrivers ?? _repository.getDrivers();
    final query = _search.text.trim().toLowerCase();
    final drivers = allDrivers
        .where(
          (d) =>
              d.isPubliclyAvailable &&
              (_vehicle == null || d.vehicleType == _vehicle) &&
              (_mandalId == null ||
                  ProximityMatcher.mandalId(
                        d.currentSpotVillageId ?? d.village.id,
                      ) ==
                      _mandalId) &&
              (query.isEmpty ||
                  [
                    d.name,
                    d.vehicleNumber,
                    d.village.name,
                    d.village.teluguName,
                    d.vehicleType.englishName,
                    d.vehicleType.teluguName,
                  ].any((text) => text.toLowerCase().contains(query))),
        )
        .toList();
    final headings = <String, String>{};
    if (_villageId != null) {
      final result = ProximityMatcher.match(
        drivers,
        KolleruVillages.find(_villageId)!,
      );
      final sections = {
        tr(te: 'మీ ఊరిలోనే ఉన్న వాహనాలు', en: 'In your village'): result.tier1,
        tr(te: 'మండల కేంద్రంలో అందుబాటులో ఉన్నవి', en: 'In Mandal hub'):
            result.tier2,
        tr(te: 'చుట్టుపక్కల మండలాలు', en: 'Nearby Mandals'): result.tier3,
      };
      for (final section in sections.entries) {
        if (section.value.isNotEmpty) {
          headings[section.value.first.id] = section.key;
        }
      }
      drivers
        ..clear()
        ..addAll([...result.tier1, ...result.tier2, ...result.tier3]);
    }
    final stackedHeader =
        MediaQuery.sizeOf(context).width <
        650 * MediaQuery.textScalerOf(context).scale(14) / 14;
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: const ValueKey('directory-search'),
          constraints: const BoxConstraints.tightFor(width: 40, height: 48),
          tooltip: tr(te: 'వెతకండి', en: 'Search'),
          onPressed: () => setState(() {
            _searching = !_searching;
            if (!_searching) _search.clear();
          }),
          icon: const Icon(Icons.search, size: 24),
        ),
        _languageToggle(),
      ],
    );
    return AppLanguageScope(
      language: language,
      child: Scaffold(
        backgroundColor: const Color(0xFFF2F7F4),
        appBar: AppBar(
          backgroundColor: Colors.white,
          automaticallyImplyLeading: false,
          toolbarHeight: stackedHeader
              ? 128 *
                    (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
                      1,
                      2,
                    )
              : 88,
          title: stackedHeader
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Builder(
                          builder: (context) => IconButton(
                            constraints: const BoxConstraints.tightFor(
                              width: 40,
                              height: 48,
                            ),
                            tooltip: MaterialLocalizations.of(context)
                                .openAppDrawerTooltip,
                            onPressed: () => Scaffold.of(context).openDrawer(),
                            icon: const Icon(Icons.menu, size: 24),
                          ),
                        ),
                        const Spacer(),
                        controls,
                      ],
                    ),
                  ],
                )
              : _header(),
          actions: stackedHeader
              ? null
              : [
                  Builder(
                    builder: (context) => IconButton(
                      constraints: const BoxConstraints.tightFor(
                        width: 40,
                        height: 48,
                      ),
                      tooltip: MaterialLocalizations.of(context)
                          .openAppDrawerTooltip,
                      onPressed: () => Scaffold.of(context).openDrawer(),
                      icon: const Icon(Icons.menu, size: 24),
                    ),
                  ),
                  controls,
                ],
        ),
        drawer: _drawer(),
        bottomNavigationBar: NavigationBar(
          key: const ValueKey('directory-bottom-navigation'),
          selectedIndex: _tab,
          backgroundColor: Colors.white,
          indicatorColor: const Color(0xFFDDF3E6),
          onDestinationSelected: (tab) => setState(() => _tab = tab),
          destinations: [
            NavigationDestination(
              key: const ValueKey('nav-vehicles'),
              icon: Icon(
                Icons.local_shipping_outlined,
                size: 24,
                color: _tab == 0 ? _green : const Color(0xFF52675B),
              ),
              label: tr(te: 'వాహనాలు', en: 'Vehicles'),
            ),
            NavigationDestination(
              key: const ValueKey('nav-call-history'),
              icon: Icon(
                Icons.history,
                size: 24,
                color: _tab == 1 ? _green : const Color(0xFF52675B),
              ),
              label: tr(te: 'నా కాల్స్', en: 'Call History'),
            ),
            NavigationDestination(
              key: const ValueKey('nav-profile'),
              icon: Icon(
                Icons.person_outline,
                size: 24,
                color: _tab == 2 ? _green : const Color(0xFF52675B),
              ),
              label: tr(te: 'ప్రొఫైల్', en: 'Profile'),
            ),
          ],
        ),
        body: SafeArea(
          child: _tab == 1
              ? _callHistory(allDrivers)
              : _tab == 2
              ? _profile()
              : Column(
                  children: [
                    if (_searching)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: TextField(
                          key: const ValueKey('directory-search-field'),
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: tr(
                              te: 'పేరు, ఊరు లేదా వాహనం వెతకండి',
                              en: 'Search name, village or vehicle',
                            ),
                          ),
                        ),
                      ),
                    _mandalFilters(),
                    _vehicleFilters(),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _fetchDrivers,
                        child: ListView(
                          key: const ValueKey('directory-list'),
                          padding: const EdgeInsets.all(16),
                          children: [
                            Text(
                              tr(
                                te: 'డ్రైవర్ విజిటింగ్ కార్డులు',
                                en: 'Driver Visiting Cards',
                              ),
                              style: const TextStyle(
                                color: _green,
                                fontWeight: FontWeight.w700,
                                fontSize: 21,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _remoteLoading && _liveDrivers == null
                                  ? language.label(AppStrings.loadingDrivers)
                                  : tr(
                                      te: 'డ్రైవర్లు: ${drivers.length}',
                                      en: 'Drivers: ${drivers.length}',
                                    ),
                            ),
                            const SizedBox(height: 12),
                            if (_remoteLoading && _liveDrivers == null)
                              const DirectoryLoadingState()
                            else if (drivers.isEmpty)
                              DirectoryEmptyState(onReset: _resetFilters),
                            if (!_remoteLoading || _liveDrivers != null) ...[
                              if (_cachedDrivers)
                                Text(
                                  tr(
                                    te: 'సేవ్ చేసిన వాహనాలు',
                                    en: 'Cached drivers',
                                  ),
                                ),
                              for (final driver in drivers) ...[
                                if (headings.containsKey(driver.id))
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    child: Text(
                                      headings[driver.id]!,
                                      style: const TextStyle(
                                        color: _green,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: DriverDirectoryCard(
                                    key: ValueKey(
                                      'directory-driver-${driver.id}',
                                    ),
                                    driver: driver,
                                    authRepository: _auth,
                                    callerPhone: _auth.currentProfile?.phone,
                                    callerRole: _auth.isGuest
                                        ? 'guest'
                                        : 'shipper',
                                    beforeCall: _requireContact,
                                    onCallLaunched: () => _rememberCall(driver),
                                    onOpen: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => VisitingCardScreen(
                                          driver: driver,
                                          authRepository: _auth,
                                          beforeContact: _requireContact,
                                          onCallLaunched: () =>
                                              _rememberCall(driver),
                                          callerPhone:
                                              _auth.currentProfile?.phone,
                                          callerRole: _auth.isGuest
                                              ? 'guest'
                                              : 'shipper',
                                        ),
                                      ),
                                    ),
                                    onWhatsApp: () {},
                                  ),
                                ),
                              ],
                            ],
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              key: const ValueKey('post-urgent-load'),
                              onPressed: _postLoad,
                              icon: const Icon(Icons.campaign),
                              label: Text(
                                _auth.isGuest
                                    ? language.label(AppStrings.signInToPost)
                                    : tr(
                                        te: 'అత్యవసర లోడ్ పోస్ట్ చేయండి',
                                        en: 'Post Urgent Load',
                                      ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              key: ValueKey(_villageId),
                              initialValue: _villageId ?? '',
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: language.label(AppStrings.village),
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: '',
                                  child: Text(
                                    language.label(AppStrings.allVillages),
                                  ),
                                ),
                                for (final village in KolleruVillages.all)
                                  DropdownMenuItem(
                                    value: village.id,
                                    child: Text(
                                      tr(
                                        te: village.teluguName,
                                        en: village.name,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (value) =>
                                  _selectVillage(value == '' ? null : value),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
