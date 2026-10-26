import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/villages.dart';
import '../../core/localization/app_language_provider.dart';
import '../../data/models/admin_analytics_model.dart';
import '../../data/models/driver_verification.dart';
import '../../data/repositories/admin_analytics_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../auth/session_router.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({
    super.key,
    this.authRepository,
    this.analyticsRepository,
  });
  final AuthRepository? authRepository;
  final AdminAnalyticsRepository? analyticsRepository;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState
    extends LanguageAwareState<AdminDashboardScreen>
    with WidgetsBindingObserver {
  static const _green = Color(0xFF0A6836);
  late final _auth = widget.authRepository ?? AuthRepository.instance;
  late final _repository =
      widget.analyticsRepository ?? AdminAnalyticsRepository.instance;
  AdminAnalyticsModel? _analytics;
  StreamSubscription<void>? _changes;
  Timer? _pollTimer;
  Timer? _clockTimer;
  bool _loading = false;
  bool _error = false;
  bool _reviewError = false;
  bool _refreshQueued = false;
  final _reviewing = <String>{};
  int _generation = 0;
  int _tab = 0;
  DateTime _now = DateTime.now();
  late String _identity;
  String get _currentIdentity =>
      '${_auth.currentProfile?.phone}:${_auth.currentProfile?.role}';
  bool get _isAdmin => _auth.currentProfile?.role == 'admin';

  @override
  void initState() {
    super.initState();
    _identity = _currentIdentity;
    WidgetsBinding.instance.addObserver(this);
    _auth.addListener(_identityChanged);
    _subscribe();
    unawaited(_refresh());
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _analytics != null) setState(() => _now = DateTime.now());
    });
  }

  void _subscribe() {
    unawaited(_changes?.cancel());
    _changes = _isAdmin
        ? _repository
              .watchChanges(_auth)
              .listen((_) => _refresh(), onError: (Object _) => _refresh())
        : null;
  }

  void _identityChanged() {
    if (!mounted || _identity == _currentIdentity) return;
    _identity = _currentIdentity;
    _generation++;
    setState(() {
      _analytics = null;
      _loading = false;
      _error = false;
      _reviewError = false;
      _reviewing.clear();
    });
    _subscribe();
    if (_isAdmin) unawaited(_refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (!mounted || !_isAdmin) return;
    if (_loading) {
      _refreshQueued = true;
      return;
    }
    final generation = _generation;
    setState(() => _loading = true);
    try {
      final data = await _repository.fetchSnapshot(_auth);
      if (!mounted || generation != _generation || !_isAdmin) return;
      setState(() {
        _analytics = data;
        _error = false;
        _now = DateTime.now();
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _analytics = null;
          _error = true;
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
        if (_refreshQueued) {
          _refreshQueued = false;
          unawaited(_refresh());
        }
      }
    }
  }

  Future<void> _review(
    AdminFleetDriver driver,
    DriverVerification decision,
  ) async {
    if (!_isAdmin || !_reviewing.add(driver.id)) return;
    final generation = _generation;
    setState(() => _reviewError = false);
    try {
      await _repository.reviewDriver(
        _auth,
        driverId: driver.id,
        decision: decision,
      );
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _reviewError = true);
      }
    } finally {
      if (mounted && generation == _generation && _isAdmin) {
        await _refresh();
        if (mounted) setState(() => _reviewing.remove(driver.id));
      }
    }
  }

  Future<void> _signOut() async {
    try {
      await _auth.signOut();
    } catch (_) {
      /* Local session is already cleared. */
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil<void>(
      MaterialPageRoute<void>(builder: (_) => SessionRouter(repository: _auth)),
      (_) => false,
    );
  }

  @override
  void dispose() {
    _generation++;
    _pollTimer?.cancel();
    _clockTimer?.cancel();
    unawaited(_changes?.cancel());
    _auth.removeListener(_identityChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Widget _languageToggle() => OutlinedButton(
    key: const ValueKey('language-toggle'),
    onPressed: language.toggleLanguage,
    style: OutlinedButton.styleFrom(
      foregroundColor: _green,
      side: const BorderSide(color: Color(0xFFCDEBDA)),
      padding: const EdgeInsets.symmetric(horizontal: 12),
    ),
    child: Text(tr(te: '🌐 EN', en: '🌐 తెలుగు')),
  );

  void _settings() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => AnimatedBuilder(
        animation: language,
        builder: (context, _) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr(te: 'సెట్టింగ్స్', en: 'Settings'),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    unawaited(_refresh());
                  },
                  icon: const Icon(Icons.refresh),
                  label: Text(tr(te: 'తాజా వివరాలు', en: 'Refresh operations')),
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    unawaited(_signOut());
                  },
                  icon: const Icon(Icons.logout),
                  label: Text(tr(te: 'లాగ్ అవుట్', en: 'Sign out')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) {
      return Scaffold(
        backgroundColor: const Color(0xFFF2F7F4),
        appBar: AppBar(
          title: Text(tr(te: 'అడ్మిన్ డెస్క్', en: 'Admin Desk')),
          actions: [_languageToggle()],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 42, color: _green),
                const SizedBox(height: 16),
                Text(
                  tr(
                    te: 'అడ్మిన్ అనుమతి అవసరం',
                    en: 'Admin authorization required',
                  ),
                ),
                TextButton(
                  onPressed: _signOut,
                  child: Text(
                    tr(te: 'లాగిన్‌కు తిరిగి వెళ్ళండి', en: 'Return to Login'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final data = _analytics;
    return Scaffold(
      backgroundColor: const Color(0xFFF2F7F4),
      body: SafeArea(
        child: Column(
          children: [
            _header(data),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  key: ValueKey('admin-page-$_tab'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
                  children: [
                    if (_loading) const LinearProgressIndicator(color: _green),
                    if (_error)
                      _surface(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr(
                                te: 'అనుమతి లేదా కనెక్షన్ లేదు. మళ్లీ ప్రయత్నించండి.',
                                en: 'Admin authorization or connection unavailable. Try again.',
                              ),
                            ),
                            TextButton(
                              onPressed: _loading ? null : _refresh,
                              child: Text(
                                tr(te: 'మళ్లీ ప్రయత్నించండి', en: 'Retry'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (data != null) ...[
                      if (_tab == 0) ...[
                        _title(
                          tr(te: 'నేటి కార్యకలాపాలు', en: 'Operations Today'),
                        ),
                        const SizedBox(height: 14),
                        _metrics(data),
                        const SizedBox(height: 24),
                        _queue(data, preview: true),
                        const SizedBox(height: 24),
                        _telemetry(data, preview: true),
                        const SizedBox(height: 24),
                        _health(data),
                      ] else if (_tab == 1) ...[
                        _queue(data),
                        const SizedBox(height: 24),
                        _title(tr(te: 'మొత్తం ఫ్లీట్', en: 'Fleet Directory')),
                        const SizedBox(height: 12),
                        if (data.fleet.isEmpty)
                          _empty(
                            tr(
                              te: 'వాహనాలు లేవు',
                              en: 'No vehicles registered',
                            ),
                          ),
                        for (final driver in data.fleet.where(
                          (d) => d.verification != DriverVerification.pending,
                        ))
                          _driverCard(driver),
                      ] else ...[
                        _title(tr(te: 'నివేదికలు', en: 'Reports')),
                        const SizedBox(height: 14),
                        _metrics(data),
                        const SizedBox(height: 24),
                        _telemetry(data),
                        const SizedBox(height: 24),
                        _health(data),
                        const SizedBox(height: 24),
                        _surface(
                          child: Text(
                            tr(
                              te: 'నేడు చురుకైన రైతులు: ${data.activeFarmers} • తాజా లోడ్లు: ${data.activeLoads}',
                              en: 'Active shippers today: ${data.activeFarmers} • Live loads: ${data.activeLoads}',
                            ),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        key: const ValueKey('admin-bottom-navigation'),
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFE0F0E6),
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: [
          NavigationDestination(
            key: const ValueKey('admin-overview-tab'),
            icon: const Icon(Icons.space_dashboard_outlined, size: 24),
            selectedIcon: const Icon(
              Icons.space_dashboard,
              color: _green,
              size: 24,
            ),
            label: tr(te: 'నియంత్రణ', en: 'Overview'),
          ),
          NavigationDestination(
            key: const ValueKey('admin-fleet-tab'),
            icon: const Icon(Icons.local_shipping_outlined, size: 24),
            selectedIcon: const Icon(
              Icons.local_shipping,
              color: _green,
              size: 24,
            ),
            label: tr(te: 'ఫ్లీట్', en: 'Fleet'),
          ),
          NavigationDestination(
            key: const ValueKey('admin-reports-tab'),
            icon: const Icon(Icons.bar_chart_outlined, size: 24),
            selectedIcon: const Icon(Icons.bar_chart, color: _green, size: 24),
            label: tr(te: 'రిపోర్ట్స్', en: 'Reports'),
          ),
        ],
      ),
    );
  }

  Widget _header(AdminAnalyticsModel? data) => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
    color: Colors.white,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final brand = Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _green,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'KW',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(te: 'అడ్మిన్ డెస్క్', en: 'Admin Desk'),
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: _green,
                    ),
                  ),
                  Text(
                    tr(
                      te: 'కొల్లేరు డెల్టా కార్యకలాపాలు',
                      en: 'Kolleru Delta Operations',
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF466354),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
        final actions = Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _pill(
              data == null
                  ? tr(te: 'ఆన్‌లైన్: —', en: 'Online: —')
                  : tr(
                      te: 'ఆన్‌లైన్: ${data.activeDrivers} డ్రైవర్లు',
                      en: '${data.activeDrivers} Drivers Online',
                    ),
              icon: Icons.circle,
            ),
            _languageToggle(),
            IconButton(
              key: const ValueKey('admin-settings-button'),
              tooltip: tr(te: 'సెట్టింగ్స్', en: 'Settings'),
              onPressed: _settings,
              icon: const Icon(Icons.settings_outlined, color: _green),
            ),
          ],
        );
        if (constraints.maxWidth < 680 ||
            MediaQuery.textScalerOf(context).scale(14) > 20) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [brand, const SizedBox(height: 10), actions],
          );
        }
        return Row(
          children: [
            Expanded(child: brand),
            const SizedBox(width: 16),
            actions,
          ],
        );
      },
    ),
  );

  Widget _metrics(AdminAnalyticsModel data) => LayoutBuilder(
    builder: (context, constraints) {
      final narrow =
          constraints.maxWidth < 350 &&
          MediaQuery.textScalerOf(context).scale(14) > 20;
      final width = narrow
          ? constraints.maxWidth
          : (constraints.maxWidth - 16) / 3;
      return Wrap(
        key: const ValueKey('admin-metrics-grid'),
        spacing: 8,
        runSpacing: 8,
        children: [
          _metric(
            width,
            Icons.local_shipping_outlined,
            data.registeredDrivers,
            tr(te: 'మొత్తం వాహనాలు', en: 'Total Vehicles'),
          ),
          _metric(
            width,
            Icons.call_outlined,
            data.callsPlacedToday,
            tr(te: 'నేటి కాల్స్', en: "Today's Calls"),
          ),
          _metric(
            width,
            Icons.hourglass_top,
            data.pendingDrivers.length,
            tr(te: 'పరిశీలనలో', en: 'Pending Verification'),
            amber: true,
          ),
        ],
      );
    },
  );

  Widget _metric(
    double width,
    IconData icon,
    int count,
    String label, {
    bool amber = false,
  }) => SizedBox(
    width: width,
    child: _surface(
      color: amber ? const Color(0xFFFFF5DB) : Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: amber ? const Color(0xFF805000) : _green, size: 24),
          const SizedBox(height: 10),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: amber ? const Color(0xFF805000) : _green,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF365B47)),
          ),
        ],
      ),
    ),
  );

  Widget _queue(AdminAnalyticsModel data, {bool preview = false}) => Column(
    key: const ValueKey('driver-approval-queue'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _title(tr(te: 'ధృవీకరణ కోసం డ్రైవర్లు', en: 'Pending Approvals')),
          if (preview)
            TextButton(
              key: const ValueKey('admin-view-all'),
              onPressed: () => setState(() => _tab = 1),
              child: Text(tr(te: 'అన్నీ చూడండి →', en: 'View All →')),
            ),
        ],
      ),
      const SizedBox(height: 10),
      if (_reviewError)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            tr(
              te: 'నిర్ణయం సేవ్ కాలేదు. తాజా స్థితి చూసి మళ్లీ ప్రయత్నించండి.',
              en: 'Decision could not be saved. Check the latest status and retry.',
            ),
            key: const ValueKey('driver-review-error'),
            style: const TextStyle(color: Color(0xFFA52222)),
          ),
        ),
      if (data.pendingDrivers.isEmpty)
        _empty(tr(te: 'పెండింగ్ ఆమోదాలు లేవు', en: 'No pending approvals')),
      for (final driver
          in (preview ? data.pendingDrivers.take(1) : data.pendingDrivers))
        _driverCard(driver),
    ],
  );

  Widget _driverCard(AdminFleetDriver driver) {
    final pending = driver.verification == DriverVerification.pending;
    final busy = _reviewing.contains(driver.id);
    final name = driver.name.isEmpty
        ? tr(te: 'డ్రైవర్', en: 'Driver')
        : language.label(driver.name);
    final mandal = driver.mandal;
    final details =
        '${language.label(driver.vehicleType.label)} • ${driver.vehicleNumber} • ${driver.capacityTons} ${tr(te: 'టన్నులు', en: 'Tons')}';
    return Padding(
      key: ValueKey('admin-driver-${driver.id}'),
      padding: const EdgeInsets.only(bottom: 12),
      child: _surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '$name${mandal == null ? '' : ' • ${tr(te: mandal.teluguName, en: mandal.name)}'}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF153E29),
              ),
            ),
            const SizedBox(height: 8),
            Text(details),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.phone_outlined, size: 18, color: _green),
                const SizedBox(width: 8),
                Flexible(child: Text(driver.phone)),
              ],
            ),
            const SizedBox(height: 14),
            if (pending)
              LayoutBuilder(
                builder: (context, constraints) {
                  final approve = FilledButton.icon(
                    key: const ValueKey('approve-driver-btn'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 48),
                    ),
                    onPressed: busy || driver.id.isEmpty
                        ? null
                        : () => _review(driver, DriverVerification.approved),
                    icon: const Icon(Icons.check, size: 18),
                    label: Text(tr(te: 'ఆమోదించండి', en: 'Approve')),
                  );
                  final reject = OutlinedButton.icon(
                    key: const ValueKey('reject-driver-btn'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFA52222),
                      side: const BorderSide(color: Color(0xFFC55656)),
                      minimumSize: const Size(0, 48),
                    ),
                    onPressed: busy || driver.id.isEmpty
                        ? null
                        : () => _review(driver, DriverVerification.rejected),
                    icon: const Icon(Icons.close, size: 18),
                    label: Text(tr(te: 'తిరస్కరించండి', en: 'Reject')),
                  );
                  if (MediaQuery.textScalerOf(context).scale(14) > 20 ||
                      constraints.maxWidth < 300) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [approve, const SizedBox(height: 8), reject],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: approve),
                      const SizedBox(width: 10),
                      Expanded(child: reject),
                    ],
                  );
                },
              )
            else
              _pill(
                driver.verification == DriverVerification.approved
                    ? tr(te: 'ఆమోదించబడింది', en: 'Approved')
                    : tr(te: 'తిరస్కరించబడింది', en: 'Rejected'),
              ),
            if (busy)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(color: _green),
              ),
          ],
        ),
      ),
    );
  }

  Widget _telemetry(AdminAnalyticsModel data, {bool preview = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: _title(
              tr(te: 'తాజా పట్టుబడి కాల్స్', en: 'Live Call Activity'),
            ),
          ),
          Semantics(
            label: tr(te: 'ప్రత్యక్ష కార్యకలాపాలు', en: 'Live activity'),
            child: Opacity(
              opacity:
                  MediaQuery.disableAnimationsOf(context) || _now.second.isEven
                  ? 1
                  : .35,
              child: const Icon(Icons.circle, color: _green, size: 10),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _surface(
        child: Column(
          key: const ValueKey('telemetry-feed-list'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (data.recentCalls.isEmpty)
              Text(tr(te: 'ఇంకా కాల్స్ లేవు', en: 'No call inquiries yet')),
            for (final call
                in (preview ? data.recentCalls.take(3) : data.recentCalls))
              _callRow(call),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Text(
        tr(
          te: 'డయలర్ లేదా చాట్ తెరిచిన అభ్యర్థనలు మాత్రమే; పూర్తయిన కాల్స్ కావు.',
          en: 'Entries record dialer or chat requests, not completed calls.',
        ),
        style: const TextStyle(fontSize: 12, color: Color(0xFF466354)),
      ),
    ],
  );

  Widget _callRow(AdminCallLogItem call) {
    final mandal = KolleruVillages.mandals
        .where((m) => m.id == call.originMandalId)
        .firstOrNull;
    final role = switch (call.callerRole) {
      'shipper' => tr(te: 'రైతు', en: 'Shipper'),
      'driver' => tr(te: 'డ్రైవర్', en: 'Driver'),
      'admin' => tr(te: 'అడ్మిన్', en: 'Admin'),
      _ => tr(te: 'అతిథి', en: 'Guest'),
    };
    final origin =
        '$role${mandal == null ? '' : ' (${tr(te: mandal.teluguName, en: mandal.name)})'}';
    final target = call.driverName?.isNotEmpty == true
        ? language.label(call.driverName!)
        : call.receiverPhone == 'Guest'
        ? tr(te: 'వివరాలు లేవు', en: 'Unknown contact')
        : call.receiverPhone;
    final elapsed = _now.toUtc().difference(call.createdAt.toUtc());
    final minutes = elapsed.inMinutes < 0 ? 0 : elapsed.inMinutes;
    final time = minutes < 1
        ? tr(te: 'ఇప్పుడే', en: 'Just now')
        : minutes < 60
        ? tr(te: '$minutes ని. క్రితం', en: '${minutes}m ago')
        : minutes < 1440
        ? tr(te: '${minutes ~/ 60} గం. క్రితం', en: '${minutes ~/ 60}h ago')
        : tr(
            te: '${minutes ~/ 1440} రోజుల క్రితం',
            en: '${minutes ~/ 1440}d ago',
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.call_outlined, color: _green, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$origin → $target',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 5),
                Text(
                  [
                    if (call.loadCategory != null)
                      _materialLabel(call.loadCategory!),
                    if (call.vehicleType != null)
                      language.label(call.vehicleType!.label),
                    call.contextNote.endsWith(':whatsapp')
                        ? tr(te: 'వాట్సాప్ విచారణ', en: 'WhatsApp inquiry')
                        : tr(te: 'రవాణా విచారణ', en: 'Transport inquiry'),
                  ].join(' • '),
                  style: const TextStyle(
                    color: Color(0xFF466354),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  time,
                  style: const TextStyle(
                    color: Color(0xFF466354),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _materialLabel(String value) {
    final pair = switch (value.toLowerCase().trim()) {
      'live fish' || 'లైవ్ ఫిష్' => ('లైవ్ ఫిష్', 'Live Fish'),
      'fish' || 'చేపలు' => ('చేపలు', 'Fish'),
      'shrimp' || 'prawns' || 'రొయ్యలు' => ('రొయ్యలు', 'Shrimp'),
      'feed' || 'చేపల దాణా' => ('చేపల దాణా', 'Feed'),
      'paddy' || 'ధాన్యం' => ('ధాన్యం', 'Paddy'),
      'cement' || 'సిమెంట్' => ('సిమెంట్', 'Cement'),
      'iron rods' || 'ఐరన్ / రాడ్లు' => ('ఐరన్ రాడ్లు', 'Iron rods'),
      'pipes' || 'పైపులు' => ('పైపులు', 'Pipes'),
      'other cargo' || 'ఇతర సామాన్లు' => ('ఇతర సామాన్లు', 'Other cargo'),
      _ => null,
    };
    return pair == null ? language.label(value) : tr(te: pair.$1, en: pair.$2);
  }

  Widget _health(AdminAnalyticsModel data) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _title(
        tr(te: 'క్లస్టర్ డైరెక్టరీ ఆరోగ్యం', en: 'Cluster Directory Health'),
      ),
      const SizedBox(height: 12),
      SingleChildScrollView(
        key: const ValueKey('cluster-health-strip'),
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final mandal in data.mandals)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _pill(
                  '${tr(te: mandal.teluguName, en: mandal.name)}: ${mandal.activeDriverCount} ${tr(te: 'లభ్యత', en: 'Active')}',
                  icon: Icons.circle,
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _title(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w800,
      color: Color(0xFF153E29),
    ),
  );
  Widget _empty(String message) => _surface(child: Text(message));
  Widget _pill(String label, {IconData? icon}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF6EE),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: const Color(0xFFCDEBDA)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 8, color: _green),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              color: _green,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
  Widget _surface({required Widget child, Color color = Colors.white}) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFCDEBDA)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x080A6836),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: child,
      );
}
