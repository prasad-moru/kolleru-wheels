import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/telemetry_repository.dart';
import '../auth/session_router.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({
    super.key,
    this.authRepository,
    this.telemetryRepository,
  });
  final AuthRepository? authRepository;
  final TelemetryRepository? telemetryRepository;
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _data;
  bool _loading = false;
  String? _error;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final data =
          await (widget.telemetryRepository ?? TelemetryRepository.instance)
              .getAdminSnapshot(
                widget.authRepository ?? AuthRepository.instance,
              );
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _data = null;
          _error = 'అనుమతి లేదా కనెక్షన్ లేదు / Admin authorization or connection unavailable';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('అడ్మిన్ / Admin Monitor'),
      actions: [
        IconButton(
          tooltip: 'Sign out',
          icon: const Icon(Icons.logout),
          onPressed: () async {
            try {
              await (widget.authRepository ?? AuthRepository.instance)
                  .signOut();
            } catch (_) {
              /* Local sign-out completed. */
            }
            if (!context.mounted) return;
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute<void>(
                builder: (_) =>
                    SessionRouter(repository: widget.authRepository),
              ),
              (_) => false,
            );
          },
        ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: _loading ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) Text(_error!),
        if (_data != null) ...[
          _counter('డ్రైవర్లు / Registered drivers', _data!['total']),
          _counter('అందుబాటులో / Active', _data!['active']),
          _counter(
            'బిజీ / Busy',
            (_data!['total'] as int) - (_data!['active'] as int),
          ),
          _counter('నేటి లోడ్లు / Load posts today', _data!['loads']),
          const SizedBox(height: 20),
          Text(
            'కాల్ ప్రయత్నాలు / Recent call intents',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text(
            'Dialer taps only; these do not confirm completed calls. Refreshes every 30 seconds.',
          ),
          for (final row in _data!['calls'] as List)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${row['caller_phone'] ?? 'Guest'} ➔ ${row['receiver_phone']}',
                    ),
                    Text('${row['caller_role']} · ${row['context_note']}'),
                    Text(
                      DateTime.tryParse('${row['created_at']}')
                              ?.toLocal()
                              .toString() ??
                          '',
                    ),
                  ],
                ),
              ),
            ),
          if ((_data!['calls'] as List).isEmpty)
            const Text('ఇంకా కాల్స్ లేవు / No call intents yet'),
        ],
      ],
    ),
  );
  Widget _counter(String label, Object? value) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Text(
        '$label: $value',
        style: Theme.of(context).textTheme.titleLarge,
      ),
    ),
  );
}
