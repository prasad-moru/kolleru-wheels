import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../data/models/driver_model.dart';
import '../common/audio_cue_button.dart';
import '../common/call_button.dart';
import '../common/vehicle_badge.dart';

class VisitingCardScreen extends StatefulWidget {
  const VisitingCardScreen({super.key, required this.driver});
  final DriverModel driver;

  @override
  State<VisitingCardScreen> createState() => _VisitingCardScreenState();
}

class _VisitingCardScreenState extends State<VisitingCardScreen> {
  final _cardKey = GlobalKey();
  bool _sharing = false;

  Future<void> _shareCard(BuildContext buttonContext) async {
    if (_sharing) return;
    final box = buttonContext.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _sharing = true);
    ui.Image? image;
    try {
      // Capture after the pending frame, when the entire card has painted.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null || boundary.debugNeedsPaint) {
        throw StateError('Visiting card is not ready to capture');
      }
      // Aim for 1080px width while bounding memory on inexpensive phones.
      final ratio = math.min(
        3.0,
        math.min(
          1080 / boundary.size.width,
          math.sqrt(4000000 / (boundary.size.width * boundary.size.height)),
        ),
      );
      image = await boundary.toImage(pixelRatio: ratio);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('PNG encoding failed');
      final temp = await getTemporaryDirectory();
      final directory = await Directory('${temp.path}/kolleru_cards')
          .create(recursive: true);
      // Clean only our previous exports older than one day. Keep recent files
      // available to WhatsApp after the share sheet closes.
      await for (final entry in directory.list()) {
        if (entry is File && entry.path.endsWith('.png')) {
          final modified = await entry.lastModified();
          if (DateTime.now().difference(modified) > const Duration(days: 1)) {
            await entry.delete();
          }
        }
      }
      final file = File(
        '${directory.path}/kolleru_card_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        flush: true,
      );
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: AppStrings.shareText,
        sharePositionOrigin: origin,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(AppStrings.shareFailed)));
      }
    } finally {
      image?.dispose();
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final driver = widget.driver;
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.visitingCard)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RepaintBoundary(
                key: _cardKey,
                child: TransportVisitingCard(driver: driver),
              ),
              const SizedBox(height: 20),
              CallButton(
                phone: driver.phone,
                isDemo: driver.isDemo,
                label: AppStrings.callNow,
              ),
              const SizedBox(height: 12),
              Builder(
                builder: (buttonContext) => FilledButton.icon(
                  key: const ValueKey('share-visiting-card'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(64),
                  ),
                  onPressed: _sharing ? null : () => _shareCard(buttonContext),
                  icon: _sharing
                      ? const SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.share, size: 28),
                  label: Text(
                    _sharing ? AppStrings.sharing : AppStrings.shareStatus,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(AppStrings.shareHint, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              AudioCueButton(
                message:
                    '${driver.name}. ${driver.vehicleType.label}. ${driver.village.label}. ${driver.isAvailable ? AppStrings.available : AppStrings.busy}',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An opaque, self-contained card; exports exclude the surrounding controls.
class TransportVisitingCard extends StatelessWidget {
  const TransportVisitingCard({super.key, required this.driver});
  final DriverModel driver;

  Widget _badge(String text, {Color color = const Color(0xFFE8F4EB)}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.charcoal, width: 1.5),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: AppColors.charcoal,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.charcoal, width: 3),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            color: AppColors.green,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.route, color: AppColors.amber, size: 36),
                const SizedBox(height: 8),
                Text(
                  AppStrings.cardHeader,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(color: Colors.white),
                ),
                const Text(
                  AppStrings.cardSubtitle,
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
          Container(height: 6, color: AppColors.amber),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                VehicleBadge(type: driver.vehicleType, size: 120),
                const SizedBox(height: 16),
                Text(
                  driver.name,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 10,
                  children: [
                    _badge(
                      driver.vehicleType.label,
                      color: const Color(0xFFFFF1BF),
                    ),
                    _badge(
                      '${AppStrings.vehicleNumber}: ${driver.vehicleNumber.isEmpty ? AppStrings.numberPending : driver.vehicleNumber}',
                    ),
                    _badge('${AppStrings.capacity}: ${driver.capacity}'),
                    for (final tag in driver.specializations)
                      _badge(tag, color: const Color(0xFFFFF1BF)),
                  ],
                ),
                const Divider(height: 32, color: AppColors.charcoal),
                Text(
                  driver.village.label,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text('${AppStrings.currentSpot}: ${driver.currentSpot}'),
                const SizedBox(height: 16),
                _badge(
                  driver.isAvailable
                      ? AppStrings.cardAvailable
                      : AppStrings.busy,
                  color: driver.isAvailable
                      ? const Color(0xFFDFF4E8)
                      : AppColors.amber,
                ),
                if (driver.isDemo) ...[
                  const SizedBox(height: 12),
                  const Text(
                    AppStrings.demo,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ],
            ),
          ),
          Container(
            color: AppColors.charcoal,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  AppStrings.callNow,
                  style: TextStyle(
                    color: AppColors.amber,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  driver.phone,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
