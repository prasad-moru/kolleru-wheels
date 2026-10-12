import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/app_strings.dart';
import '../../core/utils/proximity_matcher.dart';
import '../../data/models/load_request_model.dart';
import '../../data/models/vehicle_type.dart';
import '../../data/repositories/load_request_repository.dart';
import '../../data/repositories/supabase_load_request_repository.dart';
import 'load_dispatch_card.dart';

class LoadPoolBoard extends StatefulWidget {
  const LoadPoolBoard({
    super.key,
    required this.repository,
    this.operationalMandalId,
    this.callerPhone,
    this.vehicleType,
  });
  final LoadRequestRepository repository;
  final String? operationalMandalId;
  final String? callerPhone;
  final VehicleType? vehicleType;
  @override
  LoadPoolBoardState createState() => LoadPoolBoardState();
}

class LoadPoolBoardState extends State<LoadPoolBoard>
    with WidgetsBindingObserver {
  List<LoadRequestModel> _requests = [];
  Timer? _timer;
  bool _failed = false;
  bool _loading = true;
  int _revision = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.repository.addListener(refresh);
    refresh();
  }

  @override
  void didUpdateWidget(covariant LoadPoolBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.repository != oldWidget.repository) {
      oldWidget.repository.removeListener(refresh);
      widget.repository.addListener(refresh);
      refresh();
    } else if (widget.operationalMandalId != oldWidget.operationalMandalId ||
        widget.vehicleType != oldWidget.vehicleType) {
      refresh();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  /// Reload through the repository while preserving notifications and expiry.
  /// Shared by the dashboard's pull gesture, retry controls, and lifecycle.
  Future<void> refresh() async {
    final revision = ++_revision;
    try {
      final requests = await widget.repository.getActiveRequests(
        operationalMandalId: widget.operationalMandalId,
      );
      if (!mounted || revision != _revision) return;
      setState(() {
        _requests = requests;
        _failed = false;
        _loading = false;
      });
      _schedule();
    } catch (_) {
      if (mounted && revision == _revision) {
        _timer?.cancel();
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (_requests.isEmpty) return;
    var delay = const Duration(minutes: 1);
    final now = widget.repository.currentTime;
    for (final request in _requests) {
      final expiration = request.expiresAt.difference(now);
      if (expiration < delay) delay = expiration;
      final elapsed = now.difference(request.createdAt).inMilliseconds;
      final nextMinute = Duration(milliseconds: 60000 - elapsed % 60000);
      if (nextMinute < delay) delay = nextMinute;
    }
    _timer = Timer(
      delay.isNegative || delay == Duration.zero
          ? const Duration(milliseconds: 1)
          : delay,
      refresh,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.repository.removeListener(refresh);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Widget _emptyState(BuildContext context) => Container(
    key: const ValueKey('load-pool-empty'),
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
    ),
    child: Column(
      children: [
        Container(
          width: 92,
          height: 92,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFFECFDF5),
          ),
          child: const Stack(
            alignment: Alignment.center,
            children: [
              Icon(Icons.local_shipping_outlined, size: 44, color: Color(0xFF0F5132)),
              Positioned(
                bottom: 14,
                right: 10,
                child: Icon(Icons.eco, size: 26, color: Color(0xFF059669)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          AppStrings.noLoads,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: const Color(0xFF0F172A),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        const Text(AppStrings.loadMatchHint, textAlign: TextAlign.center),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: refresh,
          icon: const Icon(Icons.refresh),
          label: const Text(AppStrings.refreshLoads, textAlign: TextAlign.center),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final now = widget.repository.currentTime;
    // Recheck expiry and filters on every build as well as repository refresh.
    final requests = _requests.where(
      (request) => request.isActiveAt(now) &&
          (widget.operationalMandalId == null ||
              ProximityMatcher.mandalId(request.toVillageId) == widget.operationalMandalId) &&
          (widget.vehicleType == null || request.vehicleTypeNeeded == null ||
              request.vehicleTypeNeeded == widget.vehicleType),
    ).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                AppStrings.loadPool,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: const Color(0xFF0F172A),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('refresh-load-pool'),
              tooltip: AppStrings.refreshLoads,
              onPressed: _loading ? null : refresh,
              icon: const Icon(Icons.refresh, color: Color(0xFF0F5132)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(AppStrings.freightBoardHint),
        if (widget.operationalMandalId != null) ...[
          const SizedBox(height: 6),
          const Text(AppStrings.mandalLoadNote),
        ],
        if (widget.repository is SupabaseLoadRequestRepository &&
            (widget.repository as SupabaseLoadRequestRepository).syncPending)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('ఫోన్‌లో సేవ్ అయింది • సింక్ పెండింగ్ / Saved locally • sync pending'),
          ),
        const SizedBox(height: 16),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: LinearProgressIndicator(),
          )
        else if (_failed)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
            ),
            child: Column(
              children: [
                const Icon(Icons.cloud_off_outlined, size: 32, color: Color(0xFF475569)),
                const SizedBox(height: 10),
                const Text(AppStrings.loadFailedPool, textAlign: TextAlign.center),
                TextButton.icon(
                  onPressed: refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text(AppStrings.retry),
                ),
              ],
            ),
          )
        else if (requests.isEmpty)
          _emptyState(context)
        else
          for (final request in requests)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: LoadDispatchCard(
                key: ValueKey('load-${request.id}'),
                request: request,
                now: now,
                callerPhone: widget.callerPhone,
              ),
            ),
      ],
    );
  }
}
