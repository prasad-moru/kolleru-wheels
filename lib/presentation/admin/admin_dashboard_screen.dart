import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../data/models/admin_analytics_model.dart';
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

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with WidgetsBindingObserver {
  late final AuthRepository _auth =
      widget.authRepository ?? AuthRepository.instance;
  late final AdminAnalyticsRepository _repository =
      widget.analyticsRepository ?? AdminAnalyticsRepository.instance;
  AdminAnalyticsModel? _analytics;
  bool _loading = false;
  String? _error;
  Timer? _pollTimer;
  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _auth.addListener(_identityChanged);
    _refresh();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _analytics != null) {
        setState(() => _now = DateTime.now());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _identityChanged() {
    if (!mounted) return;
    if (_auth.currentProfile?.role != 'admin') {
      setState(() {
        _analytics = null;
        _error = 'Admin authorization required / అడ్మిన్ అనుమతి అవసరం';
      });
    }
  }

  Future<void> _refresh() async {
    if (_loading || !mounted) return;
    if (_auth.currentProfile?.role != 'admin') {
      setState(() {
        _analytics = null;
        _error = 'Admin authorization required / అడ్మిన్ అనుమతి అవసరం';
      });
      return;
    }
    setState(() {
      _loading = true;
      _now = DateTime.now();
    });
    try {
      final data = await _repository.fetchSnapshot(_auth);
      if (mounted) {
        setState(() {
          _analytics = data;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _analytics = null;
          _error = 'అనుమతి లేదా కనెక్షన్ లేదు / Admin authorization or connection unavailable';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signOut() async {
    try {
      await _auth.signOut();
    } catch (_) {
      // The local session is cleared before the remote sign-out request.
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil<void>(
      MaterialPageRoute<void>(builder: (_) => SessionRouter(repository: _auth)),
      (_) => false,
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _clockTimer?.cancel();
    _auth.removeListener(_identityChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_auth.currentProfile?.role != 'admin') return _accessDenied(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('కొల్లేరు అడ్మిన్ కంట్రోల్'),
        actions: [
          IconButton(
            tooltip: 'Refresh analytics',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Text(
              'Admin Command Hub',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 3),
            Text(
              'కొల్లేరు రవాణా కార్యకలాపాలు / Regional operations overview',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            if (_loading && _analytics == null) const LinearProgressIndicator(),
            if (_error != null) _errorPanel(context, _error!),
            if (_analytics case final analytics?) ...[
              _sectionTitle(context, 'స్థితి / At a glance'),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = (constraints.maxWidth - 12) / 2;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _metricCard(
                        width,
                        'Total Users',
                        analytics.totalUsers,
                        Icons.people_alt_outlined,
                        const Color(0xFFE9F2FC),
                        const Color(0xFF285E8E),
                      ),
                      _metricCard(
                        width,
                        'Active Trucks',
                        analytics.activeDrivers,
                        Icons.local_shipping_outlined,
                        const Color(0xFFE8F4EB),
                        const Color(0xFF176744),
                      ),
                      _metricCard(
                        width,
                        'Live Loads',
                        analytics.activeLoads,
                        Icons.inventory_2_outlined,
                        const Color(0xFFFFF2DF),
                        const Color(0xFF8A5A0A),
                      ),
                      _metricCard(
                        width,
                        'Calls Placed Today',
                        analytics.callsPlacedToday,
                        Icons.call_outlined,
                        const Color(0xFFF0ECF8),
                        const Color(0xFF654A91),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '${analytics.activeFarmers} active farmers today · ${analytics.registeredDrivers} registered drivers',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 24),
              _sectionTitle(
                context,
                'ప్రత్యక్ష లోడ్లు / Live Urgent Load Pool',
              ),
              const SizedBox(height: 8),
              if (analytics.liveLoads.isEmpty)
                _emptyCard('ప్రస్తుతం లోడ్లు లేవు / No active loads')
              else
                for (final load in analytics.liveLoads)
                  _loadCard(context, load),
              const SizedBox(height: 18),
              _sectionTitle(context, 'మండలాల వారీగా / Mandal Activity'),
              const SizedBox(height: 8),
              _mandalCard(context, analytics),
              const SizedBox(height: 18),
              _sectionTitle(context, 'కాల్ ఆడిట్ / Telemetry Audit Trail'),
              const SizedBox(height: 8),
              if (analytics.recentCalls.isEmpty)
                _emptyCard('ఇంకా కాల్స్ లేవు / No call intents yet')
              else
                for (final call in analytics.recentCalls)
                  _callCard(context, call),
              const SizedBox(height: 8),
              Text(
                'Call entries record dialer requests, not completed calls. Refreshes every 30 seconds.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _accessDenied(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Admin Command Hub')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 42),
            const SizedBox(height: 12),
            const Text('Admin authorization required / అడ్మిన్ అనుమతి అవసరం'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _signOut,
              child: const Text('Return to Login'),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _sectionTitle(BuildContext context, String title) =>
      Text(title, style: Theme.of(context).textTheme.titleLarge);

  Widget _metricCard(
    double width,
    String label,
    int value,
    IconData icon,
    Color background,
    Color foreground,
  ) => SizedBox(
    width: width,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: foreground, size: 20),
            ),
            const SizedBox(height: 10),
            Text(
              '$value',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(color: foreground, fontWeight: FontWeight.w500),
            ),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ),
  );

  Widget _loadCard(BuildContext context, AdminLoadFeedItem load) {
    final remaining = load.expiresAt.difference(_now);
    final countdown = remaining.isNegative
        ? 'Expired'
        : '${remaining.inMinutes}:${(remaining.inSeconds % 60).toString().padLeft(2, '0')} left';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.local_shipping_outlined, color: AppColors.green),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    load.pickupLocation,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '${load.destination} · ${load.category}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Text(
              countdown,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: remaining.inMinutes < 5
                    ? const Color(0xFFB5473D)
                    : const Color(0xFF176744),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mandalCard(
    BuildContext context,
    AdminAnalyticsModel analytics,
  ) => Card(
    child: Column(
      children: [
        for (var index = 0; index < analytics.mandals.length; index++) ...[
          if (index > 0) const Divider(height: 1, indent: 14, endIndent: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${analytics.mandals[index].teluguName} / ${analytics.mandals[index].name}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    _countLabel(
                      'Drivers',
                      analytics.mandals[index].driverCount,
                    ),
                    _countLabel(
                      'Farmers',
                      analytics.mandals[index].farmerCount,
                    ),
                    _countLabel('Calls', analytics.mandals[index].callTally),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );

  Widget _countLabel(String label, int count) => Text('$label  $count');

  Widget _callCard(BuildContext context, AdminCallLogItem call) {
    final timestamp = call.createdAt.toLocal();
    final time =
        '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}  ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Chip(
                  label: Text(call.callerRole.toUpperCase()),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                Text(time, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 4),
            Text('${call.callerPhone} → ${call.receiverPhone}'),
            if (call.contextNote.isNotEmpty)
              Text(
                call.contextNote,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }

  Widget _emptyCard(String message) => Card(
    child: Padding(padding: const EdgeInsets.all(18), child: Text(message)),
  );

  Widget _errorPanel(BuildContext context, String message) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_outlined),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
    ),
  );
}
