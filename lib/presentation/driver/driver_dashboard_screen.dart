import 'package:flutter/material.dart';

import '../../core/constants/app_strings.dart';
import '../../core/localization/app_language_provider.dart';
import '../../data/models/driver_activity_model.dart';
import '../../data/repositories/driver_activity_repository.dart';
import '../../core/constants/driver_spots.dart';
import '../../core/constants/villages.dart';
import '../../core/utils/proximity_matcher.dart';
import '../../data/models/local_driver_profile.dart';
import '../../data/models/driver_verification.dart';
import '../../data/repositories/local_driver_repository.dart';
import '../../data/repositories/load_request_repository.dart';
import '../../data/repositories/supabase_driver_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../directory/widgets/driver_visiting_card.dart';
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
    this.activityRepository,
    this.remoteDriverRepository,
  });
  final DriverActivityRepository? activityRepository;
  final SupabaseDriverRepository? remoteDriverRepository;
  final LocalDriverProfile profile;
  final AuthRepository? authRepository;
  final LocalDriverRepository repository;
  final LoadRequestRepository? loadRequestRepository;
  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState
    extends LanguageAwareState<DriverDashboardScreen>
    with WidgetsBindingObserver {
  static const _green = Color(0xFF0A6836);
  int _tab = 0;
  DriverActivity? _activity;
  bool _activityLoading = false;
  bool _activityFailed = false;
  late final _activityRepository =
      widget.activityRepository ?? DriverActivityRepository();
  late LocalDriverProfile _profile;
  late final _auth = widget.authRepository ?? AuthRepository.instance;
  bool _saving = false;
  bool _syncPending = false;
  late final _remoteDriver =
      widget.remoteDriverRepository ?? SupabaseDriverRepository.instance;
  final _loadBoardKey = GlobalKey<LoadPoolBoardState>();
  LoadRequestRepository get _loads =>
      widget.loadRequestRepository ?? LoadRequestRepository.instance;
  String? get _operationalMandalId =>
      ProximityMatcher.mandalId(_profile.currentSpotVillage.id) ??
      ProximityMatcher.mandalId(_profile.baseVillage.id);

  Future<void> _refreshLoads() async {
    await _refreshActivity();
    try {
      final board = _loadBoardKey.currentState;
      if (board != null) {
        await board.refresh();
      } else {
        await _loads.getActiveRequests(
          operationalMandalId: _operationalMandalId,
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(language.label(AppStrings.loadFailedPool))),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
    WidgetsBinding.instance.addObserver(this);
    _auth.addListener(_identityChanged);
    if (_auth.currentProfile?.role == 'driver' &&
        _auth.currentProfile?.phone == _profile.phone) {
      _syncDriver();
      _refreshActivity();
    }
  }

  void _identityChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _auth.removeListener(_identityChanged);
    WidgetsBinding.instance.removeObserver(this);
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(language.label(AppStrings.saveFailed))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openCard() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VisitingCardScreen(driver: _profile.toDriverModel()),
      ),
    );
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
                  language.label(AppStrings.currentLocation),
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
                        title: Text(language.label(spot.label)),
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshActivity();
  }

  Future<void> _refreshActivity() async {
    if (_activityLoading) return;
    setState(() => _activityLoading = true);
    try {
      final activity = await _activityRepository.fetchActivity(_auth);
      if (mounted) {
        setState(() {
          _activity = activity;
          _activityFailed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _activityFailed = true);
    } finally {
      if (mounted) setState(() => _activityLoading = false);
    }
  }

  Future<void> _logout() async {
    try {
      await _auth.signOut();
    } catch (_) {
      /* Local identity still clears. */
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => SessionRouter(repository: _auth)),
      (_) => false,
    );
  }

  BoxDecoration _surface({bool prominent = false}) => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(prominent ? 22 : 16),
    border: Border.all(
      color: prominent ? _green : const Color(0xFFCDEBDA),
      width: prominent ? 2 : 1,
    ),
    boxShadow: [
      BoxShadow(
        color: _green.withValues(alpha: 0.05),
        blurRadius: 16,
        offset: const Offset(0, 5),
      ),
    ],
  );

  Widget _availability() => Container(
    padding: const EdgeInsets.all(20),
    decoration: _surface(prominent: true),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(
                      te: 'మీ ప్రస్తుత స్థితి',
                      en: 'Your Availability Status',
                    ),
                    style: const TextStyle(
                      color: _green,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tr(
                      te: 'పంట, సరుకు రవాణాకు సిద్ధంగా ఉన్నారా?',
                      en: 'Ready for harvest and transport loads?',
                    ),
                    style: const TextStyle(
                      color: Color(0xFF365B47),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Semantics(
              key: const ValueKey('driver-status-toggle'),
              label: tr(
                te: 'ఆర్డర్ల కోసం అందుబాటు',
                en: 'Availability for loads',
              ),
              child: Switch(
                key: const ValueKey('driver-availability'),
                value: _profile.isAvailable,
                activeThumbColor: Colors.white,
                activeTrackColor: _green,
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
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _profile.isAvailable
                ? const Color(0xFFE8F8EF)
                : const Color(0xFFF1F5F3),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _profile.isAvailable
                    ? tr(
                        te: '🟢 ఆర్డర్లకు సిద్ధం',
                        en: '🟢 Online - Ready for Loads',
                      )
                    : tr(
                        te: '⚪ ప్రస్తుతం అందుబాటులో లేను',
                        en: '⚪ Offline - Off Duty',
                      ),
                style: const TextStyle(
                  color: _green,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _profile.verification == DriverVerification.pending
                    ? tr(
                        te: 'అడ్మిన్ ఆమోదం కోసం వేచి ఉంది',
                        en: 'Awaiting admin approval',
                      )
                    : _profile.verification == DriverVerification.rejected
                    ? tr(
                        te: 'నమోదు తిరస్కరించబడింది',
                        en: 'Registration rejected',
                      )
                    : _profile.isAvailable
                    ? tr(
                        te: 'రైతులకు కనిపిస్తున్నారు',
                        en: 'Visible to Shippers',
                      )
                    : tr(
                        te: 'మళ్లీ సిద్ధమైనప్పుడు ఆన్‌లైన్‌లోకి రండి',
                        en: 'Go online when you are ready again',
                      ),
                style: const TextStyle(color: Color(0xFF365B47)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          tr(
            te: 'పట్టుబడి సమయంలో కాల్స్ రావడానికి ఆన్‌లైన్‌లో ఉండండి',
            en: 'Stay online during harvest hours to receive direct calls',
          ),
          style: const TextStyle(color: Color(0xFF365B47), height: 1.5),
        ),
        if (_saving)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(language.label(AppStrings.saving)),
          ),
        if (_syncPending)
          TextButton(
            onPressed: _saving ? null : _syncDriver,
            child: Text(
              tr(
                te: 'ఫోన్‌లో సేవ్ అయింది • సమకాలీకరణ మిగిలి ఉంది',
                en: 'Saved locally • sync pending',
              ),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    ),
  );

  Widget _preview() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              tr(
                te: 'రైతులకు కనిపించే మీ కార్డు',
                en: 'How Shippers See Your Card',
              ),
              style: const TextStyle(
                color: _green,
                fontWeight: FontWeight.w700,
                fontSize: 19,
              ),
            ),
          ),
          TextButton(
            key: const ValueKey('edit-driver-card'),
            onPressed: _saving ? null : _openCard,
            child: Text(tr(te: 'సవరించండి', en: 'Edit')),
          ),
        ],
      ),
      const SizedBox(height: 10),
      DriverVisitingCard(
        key: const ValueKey('driver-card-preview'),
        driver: _profile.toDriverModel(),
        previewOnly: true,
        onOpen: _openCard,
        onWhatsApp: () {},
      ),
    ],
  );

  Widget _metric({
    required IconData icon,
    required String value,
    required String caption,
    Key? key,
  }) => Container(
    key: key,
    padding: const EdgeInsets.all(16),
    decoration: _surface(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _green, size: 24),
        const SizedBox(height: 14),
        Text(
          value,
          style: const TextStyle(
            color: _green,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          caption,
          style: const TextStyle(
            color: Color(0xFF365B47),
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ],
    ),
  );

  Widget _metrics() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        tr(te: 'నేటి కార్యకలాపాలు', en: "Today's Activity"),
        style: const TextStyle(
          color: _green,
          fontWeight: FontWeight.w700,
          fontSize: 21,
        ),
      ),
      const SizedBox(height: 14),
      LayoutBuilder(
        builder: (context, constraints) {
          final call = _metric(
            key: const ValueKey('driver-call-counter'),
            icon: Icons.phone_in_talk_outlined,
            value: _activity == null
                ? '—'
                : tr(
                    te: '${_activity!.callsToday} కాల్స్',
                    en: '${_activity!.callsToday} Calls',
                  ),
            caption: tr(te: 'నేడు రైతుల నుండి', en: 'From Shippers Today'),
          );
          final verified = _metric(
            icon: _profile.isPhoneVerified
                ? Icons.verified_user_outlined
                : Icons.shield_outlined,
            value: _profile.verification == DriverVerification.pending
                ? tr(te: 'ఆమోదం కోసం వేచి ఉంది', en: 'Approval Pending')
                : _profile.verification == DriverVerification.rejected
                ? tr(te: 'నమోదు తిరస్కరించబడింది', en: 'Registration Rejected')
                : _profile.isPhoneVerified
                ? tr(te: 'ధృవీకరించబడింది', en: 'Verified Driver')
                : tr(te: 'ధృవీకరణ మిగిలి ఉంది', en: 'Verification Pending'),
            caption: _profile.isAvailable
                ? tr(te: 'క్రియాశీల స్థితి', en: 'Active Status')
                : tr(te: 'ప్రస్తుతం ఆఫ్‌లైన్', en: 'Currently Offline'),
          );
          if (constraints.maxWidth < 300 ||
              MediaQuery.textScalerOf(context).scale(14) > 21) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [call, const SizedBox(height: 12), verified],
            );
          }
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: call),
                const SizedBox(width: 12),
                Expanded(child: verified),
              ],
            ),
          );
        },
      ),
    ],
  );

  String _elapsed(DateTime time) {
    final age = _activityRepository.currentTime.difference(time);
    if (age.inMinutes < 1) return tr(te: 'ఇప్పుడే', en: 'Just now');
    if (age.inHours < 1) {
      return tr(
        te: '${age.inMinutes} నిమిషాల క్రితం',
        en: '${age.inMinutes}m ago',
      );
    }
    if (age.inDays < 1) {
      return tr(te: '${age.inHours} గంటల క్రితం', en: '${age.inHours}h ago');
    }
    return tr(te: '${age.inDays} రోజుల క్రితం', en: '${age.inDays}d ago');
  }

  Widget _inquiries({bool all = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              all
                  ? tr(te: 'కాల్ లాగ్స్', en: 'Call Logs')
                  : tr(te: 'ఇటీవలి కాల్స్', en: 'Recent Calls'),
              style: const TextStyle(
                color: _green,
                fontWeight: FontWeight.w700,
                fontSize: 21,
              ),
            ),
          ),
          if (!all)
            Flexible(
              child: TextButton(
                onPressed: () => setState(() => _tab = 2),
                child: Text(
                  tr(te: 'అన్నీ చూడండి', en: 'View all'),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 10),
      if (_activityLoading) const LinearProgressIndicator(),
      if (_activityFailed)
        TextButton.icon(
          key: const ValueKey('retry-driver-activity'),
          onPressed: _refreshActivity,
          icon: const Icon(Icons.refresh),
          label: Text(
            tr(
              te: 'కాల్స్ తెరవలేదు. మళ్లీ ప్రయత్నించండి.',
              en: 'Could not refresh calls. Retry.',
            ),
          ),
        ),
      if (_activity != null && _activity!.recentCalls.isEmpty)
        Container(
          key: const ValueKey('driver-inquiries-empty'),
          padding: const EdgeInsets.all(20),
          decoration: _surface(),
          child: Text(
            tr(
              te: 'ఇంకా రైతుల నుండి కాల్స్ లేవు',
              en: 'No shipper inquiries yet',
            ),
          ),
        ),
      for (final call in (_activity?.recentCalls ?? <DriverInquiry>[]).take(
        all ? 50 : 2,
      ))
        Container(
          key: ValueKey('driver-inquiry-${call.id}'),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: _surface(),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.phone_callback_outlined,
                color: _green,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      call.location != null
                          ? language.label(call.location!)
                          : call.village != null
                          ? tr(
                              te: call.village!.teluguName,
                              en: call.village!.name,
                            )
                          : tr(te: 'స్థానిక రైతు', en: 'Local shipper'),
                      style: const TextStyle(
                        color: _green,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      call.loadDetail == null
                          ? tr(
                              te: 'రవాణా గురించి విచారణ',
                              en: 'Transport inquiry',
                            )
                          : language.label(call.loadDetail!),
                      style: const TextStyle(color: Color(0xFF365B47)),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _elapsed(call.createdAt),
                      style: const TextStyle(
                        color: Color(0xFF52675B),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
    ],
  );

  Widget _locationControls() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        language.label(AppStrings.currentLocation),
        style: const TextStyle(
          color: _green,
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        key: const ValueKey('current-spot'),
        onPressed: _saving ? null : _chooseSpot,
        icon: const Icon(Icons.edit_location_alt_outlined, size: 24),
        label: Text(
          language.label(_profile.currentSpotLabel),
          textAlign: TextAlign.center,
        ),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        key: const ValueKey('dashboard-visiting-card'),
        onPressed: _saving ? null : _openCard,
        icon: const Icon(Icons.badge_outlined, size: 24),
        label: Text(
          tr(te: 'నా విజిటింగ్ కార్డు తెరవండి', en: 'Open My Visiting Card'),
          textAlign: TextAlign.center,
        ),
      ),
    ],
  );

  Widget _brand() => Row(
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
            fontSize: 16,
            fontWeight: FontWeight.w800,
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
              tr(te: 'డ్రైవర్ డ్యాష్‌బోర్డ్', en: 'Driver Cockpit'),
              style: const TextStyle(
                color: _green,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              language.label(_profile.name),
              style: const TextStyle(color: Color(0xFF365B47), fontSize: 13),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _toggleLanguage() => OutlinedButton(
    key: const ValueKey('language-toggle'),
    onPressed: language.toggleLanguage,
    style: OutlinedButton.styleFrom(
      foregroundColor: _green,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      shape: const StadiumBorder(),
    ),
    child: Text(tr(te: '🌐 EN', en: '🌐 తెలుగు')),
  );

  Widget _menuButton() => Builder(
    builder: (context) => IconButton(
      tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
      onPressed: () => Scaffold.of(context).openDrawer(),
      icon: const Icon(Icons.menu, size: 24),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_auth.currentProfile?.role != 'driver' ||
        _auth.currentProfile?.phone != _profile.phone) {
      return SessionRouter(repository: _auth);
    }
    final stacked =
        MediaQuery.sizeOf(context).width <
        500 * MediaQuery.textScalerOf(context).scale(14) / 14;
    return AppLanguageScope(
      language: language,
      child: Scaffold(
        backgroundColor: const Color(0xFFF2F7F4),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: Colors.white,
          toolbarHeight: stacked
              ? 120 *
                    (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
                      1,
                      2,
                    )
              : 88,
          title: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _brand(),
                    Row(
                      children: [
                        _menuButton(),
                        const Spacer(),
                        _toggleLanguage(),
                      ],
                    ),
                  ],
                )
              : _brand(),
          actions: stacked
              ? null
              : [_menuButton(), _toggleLanguage(), const SizedBox(width: 12)],
        ),
        drawer: Drawer(
          child: SafeArea(
            child: ListView(
              children: [
                ListTile(
                  key: const ValueKey('driver-profile'),
                  leading: const Icon(Icons.person),
                  title: Text(language.label(_profile.name)),
                  subtitle: Text(_profile.phone),
                ),
                ListTile(
                  key: const ValueKey('drawer-digital-card'),
                  leading: const Icon(Icons.badge),
                  title: Text(
                    tr(te: 'నా విజిటింగ్ కార్డు', en: 'Digital Visiting Card'),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    _openCard();
                  },
                ),
                ListTile(
                  key: const ValueKey('drawer-logout'),
                  leading: const Icon(Icons.logout),
                  title: Text(tr(te: 'లాగౌట్', en: 'Logout')),
                  onTap: () {
                    Navigator.of(context).pop();
                    _logout();
                  },
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: NavigationBar(
          key: const ValueKey('driver-bottom-navigation'),
          selectedIndex: _tab,
          backgroundColor: Colors.white,
          indicatorColor: const Color(0xFFDDF3E6),
          onDestinationSelected: (tab) {
            setState(() => _tab = tab);
            if (tab == 2) _refreshActivity();
          },
          destinations: [
            NavigationDestination(
              key: const ValueKey('driver-nav-dashboard'),
              icon: Icon(
                Icons.dashboard_outlined,
                size: 24,
                color: _tab == 0 ? _green : const Color(0xFF52675B),
              ),
              label: tr(te: 'డ్యాష్‌బోర్డ్', en: 'Dashboard'),
            ),
            NavigationDestination(
              key: const ValueKey('driver-nav-card'),
              icon: Icon(
                Icons.badge_outlined,
                size: 24,
                color: _tab == 1 ? _green : const Color(0xFF52675B),
              ),
              label: tr(te: 'నా కార్డు', en: 'My Card'),
            ),
            NavigationDestination(
              key: const ValueKey('driver-nav-calls'),
              icon: Icon(
                Icons.phone_in_talk_outlined,
                size: 24,
                color: _tab == 2 ? _green : const Color(0xFF52675B),
              ),
              label: tr(te: 'కాల్ లాగ్స్', en: 'Call Logs'),
            ),
          ],
        ),
        body: SafeArea(
          child: RefreshIndicator(
            key: const ValueKey('dashboard-refresh'),
            color: _green,
            onRefresh: _refreshLoads,
            child: ListView(
              key: const ValueKey('dashboard-scroll'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                if (_tab == 0) ...[
                  _availability(),
                  const SizedBox(height: 20),
                  _preview(),
                  const SizedBox(height: 24),
                  _metrics(),
                  const SizedBox(height: 24),
                  _inquiries(),
                  const SizedBox(height: 24),
                  _locationControls(),
                  const SizedBox(height: 24),
                  LoadPoolBoard(
                    key: _loadBoardKey,
                    callerPhone: _profile.phone,
                    operationalMandalId: _operationalMandalId,
                    vehicleType: _profile.vehicleType,
                    repository: _loads,
                  ),
                ] else if (_tab == 1) ...[
                  _preview(),
                  const SizedBox(height: 24),
                  _locationControls(),
                ] else ...[
                  _metrics(),
                  const SizedBox(height: 24),
                  _inquiries(all: true),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
