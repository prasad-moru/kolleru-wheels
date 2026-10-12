import 'package:flutter/material.dart';

import '../../core/constants/app_strings.dart';
import '../../core/constants/villages.dart';
import '../../core/utils/proximity_matcher.dart';
import '../../data/models/load_request_model.dart';
import '../../data/repositories/telemetry_repository.dart';
import '../common/call_button.dart';

/// A dispatch ticket for one active, thirty-minute urgent post.
class LoadDispatchCard extends StatelessWidget {
  const LoadDispatchCard({
    super.key,
    required this.request,
    required this.now,
    this.callerPhone,
    this.telemetryRepository,
    this.launcher,
  });

  final LoadRequestModel request;
  final DateTime now;
  final String? callerPhone;
  final TelemetryRepository? telemetryRepository;
  final Future<bool> Function(Uri)? launcher;

  static const _ink = Color(0xFF0F172A);
  static const _slate = Color(0xFF475569);

  Widget _pill(
    String label,
    IconData icon,
    Color background,
    Color foreground, {
    Key? key,
  }) => Container(
    key: key,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: foreground),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _commodity() {
    final label = request.materialType.toLowerCase();
    if (label.contains('feed') || label.contains('fertiliz') ||
        label.contains('fertilis') || label.contains('దాణా') ||
        label.contains('ఎరువు')) {
      return _pill(request.materialType, Icons.grain,
          const Color(0xFFE0F2FE), const Color(0xFF0369A1));
    }
    if (label.contains('fish') || label.contains('shrimp') ||
        label.contains('prawn') || label.contains('చేప') ||
        label.contains('రొయ్య')) {
      return _pill(request.materialType, Icons.water_outlined,
          const Color(0xFFDCFCE7), const Color(0xFF15803D));
    }
    if (label.contains('paddy') || label.contains('grain') ||
        label.contains('ధాన్యం') || label.contains('వరి')) {
      return _pill(request.materialType, Icons.grass,
          const Color(0xFFFEF3C7), const Color(0xFFB45309));
    }
    return _pill(request.materialType, Icons.inventory_2_outlined,
        const Color(0xFFF1F5F9), _slate);
  }

  Widget _routeNode(
    String label,
    String location,
    IconData icon,
    Color color,
    BuildContext context,
  ) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 24,
        height: 24,
        child: Icon(icon, size: icon == Icons.circle ? 10 : 23, color: color),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: _slate, fontSize: 12)),
            const SizedBox(height: 3),
            Text(
              location,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: _ink,
                fontWeight: FontWeight.w600,
                fontSize: 18,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final remaining = request.expiresAt.difference(now);
    final minutesLeft = (remaining.inSeconds / 60).ceil().clamp(0, 30);
    final closingSoon = remaining <= const Duration(minutes: 5);
    final mandalId = ProximityMatcher.mandalId(request.toVillageId);
    final mandal = KolleruVillages.mandals
        .where((mandal) => mandal.id == mandalId)
        .firstOrNull;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            children: [
              _pill(
                AppStrings.urgentBadge,
                Icons.bolt,
                closingSoon ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7),
                closingSoon ? const Color(0xFFB91C1C) : const Color(0xFFB45309),
              ),
              _pill(
                '$minutesLeft నిమి / min left',
                Icons.timer_outlined,
                const Color(0xFFF1F5F9),
                _slate,
                key: ValueKey('countdown-${request.id}'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Semantics(
            label: '${request.fromLocation} ➔ ${request.toVillage.label}',
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _routeNode(AppStrings.pickupSpot, request.fromLocation,
                      Icons.circle, const Color(0xFF059669), context),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: SizedBox(
                      width: 24,
                      child: Column(
                        children: [
                          Container(width: 1.5, height: 14, color: const Color(0xFF94A3B8)),
                          const Icon(Icons.arrow_downward, size: 17, color: Color(0xFF94A3B8)),
                        ],
                      ),
                    ),
                  ),
                  _routeNode(AppStrings.dropVillage, request.toVillage.label,
                      Icons.location_on, const Color(0xFFD97706), context),
                  if (mandal != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 36, top: 4),
                      child: Text(
                        '${mandal.teluguName} / ${mandal.name}',
                        style: const TextStyle(color: _slate, fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _commodity(),
              _pill(
                request.vehicleTypeNeeded?.label ?? AppStrings.anyVehicle,
                Icons.local_shipping_outlined,
                const Color(0xFFE0F2FE),
                const Color(0xFF0369A1),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text(request.posterName, style: const TextStyle(color: _ink, fontWeight: FontWeight.w500)),
              Text(
                now.difference(request.createdAt).inMinutes < 1
                    ? AppStrings.justPosted
                    : '${now.difference(request.createdAt).inMinutes} నిమిషాల క్రితం / minutes ago',
                style: const TextStyle(color: _slate, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          CallButton(
            phone: request.posterPhone,
            label: AppStrings.callFarmer,
            backgroundColor: const Color(0xFF059669),
            borderRadius: 12,
            maxLabelLines: null,
            elevated: true,
            callerPhone: callerPhone,
            callerRole: 'driver',
            contextNote: 'urgent_load:${request.id}',
            telemetryRepository: telemetryRepository,
            launcher: launcher,
          ),
        ],
      ),
    );
  }
}
