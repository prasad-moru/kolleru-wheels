import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/villages.dart';
import '../../data/models/load_request_model.dart';
import '../../data/repositories/load_request_repository.dart';
import '../common/call_button.dart';

class LoadPoolBoard extends StatefulWidget {
  const LoadPoolBoard({super.key, required this.repository});
  final LoadRequestRepository repository;
  @override
  State<LoadPoolBoard> createState() => _LoadPoolBoardState();
}

class _LoadPoolBoardState extends State<LoadPoolBoard>
    with WidgetsBindingObserver {
  IconData _materialIcon(String material) => switch (material) {
    'ఐరన్ / రాడ్లు' => Icons.hardware,
    'సిమెంట్' => Icons.inventory_2,
    'పైపులు' => Icons.plumbing,
    'చేపల దాణా' => Icons.grain,
    _ => Icons.category,
  };
  List<LoadRequestModel> _requests = [];
  Timer? _timer;
  bool _failed = false;
  bool _loading = true;
  int _revision = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.repository.addListener(_refresh);
    _refresh();
  }

  @override
  void didUpdateWidget(covariant LoadPoolBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.repository != oldWidget.repository) {
      oldWidget.repository.removeListener(_refresh);
      widget.repository.addListener(_refresh);
      _refresh();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final revision = ++_revision;
    try {
      final requests = await widget.repository.getActiveRequests();
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
      _refresh,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.repository.removeListener(_refresh);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.repository.currentTime;
    // Filter at build as well, so resumed/rebuilt views never display stale loads.
    final requests = _requests.where((r) => r.isActiveAt(now));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          AppStrings.loadPool,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(AppStrings.localLoadNote),
        if (_loading)
          const LinearProgressIndicator()
        else if (_failed)
          TextButton(
            onPressed: _refresh,
            child: const Text(
              '${AppStrings.loadFailedPool} — ${AppStrings.retry}',
            ),
          )
        else if (requests.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text(AppStrings.noLoads),
          )
        else
          for (final request in requests)
            Card(
              key: ValueKey('load-${request.id}'),
              color: const Color(0xFFFFF4D5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppColors.charcoal, width: 2),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      _materialIcon(request.materialType),
                      size: 36,
                      color: AppColors.charcoal,
                    ),
                    Text(
                      '${request.fromLocation} ➔ ${KolleruVillages.find(request.toVillageId)!.label}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${AppStrings.material}: ${request.materialType}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (request.vehicleTypeNeeded != null)
                      Text(request.vehicleTypeNeeded!.label),
                    Text(request.posterName),
                    const SizedBox(height: 8),
                    Text(
                      now.difference(request.createdAt).inMinutes < 1
                          ? AppStrings.justPosted
                          : '${now.difference(request.createdAt).inMinutes} నిమిషాల క్రితం / minutes ago',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    CallButton(
                      phone: request.posterPhone,
                      label: AppStrings.callShipper,
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
