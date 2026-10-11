import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../data/models/driver_model.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/local_driver_repository.dart';
import '../../data/repositories/supabase_driver_repository.dart';
import '../common/audio_cue_button.dart';
import '../common/call_button.dart';
import '../common/driver_avatar_picker.dart';

class VisitingCardScreen extends StatefulWidget {
  const VisitingCardScreen({super.key, required this.driver});
  final DriverModel driver;

  @override
  State<VisitingCardScreen> createState() => _VisitingCardScreenState();
}

class _VisitingCardScreenState extends State<VisitingCardScreen> {
  final _cardKey = GlobalKey();
  bool _sharing = false;
  bool _savingAvatar = false;
  late DriverModel _driver = widget.driver;
  Uint8List? _avatarBytes;
  late final _auth = AuthRepository.instance;
  late final _driverRepository = SupabaseDriverRepository.instance;

  bool get _canEditAvatar =>
      !_driver.isDemo &&
      _auth.currentProfile?.role == 'driver' &&
      _auth.currentProfile?.phone == _driver.phone;

  Future<void> _saveAvatar(Uint8List bytes) async {
    if (_savingAvatar || !_canEditAvatar) return;
    setState(() {
      _savingAvatar = true;
      _avatarBytes = bytes;
    });
    try {
      final url = await _driverRepository.uploadDriverAvatar(
        driverId: _driver.id,
        jpegBytes: bytes,
      );
      final updated = _driverWithAvatar(_driver, url);
      final local = await LocalDriverRepository().getProfile();
      if (local == null ||
          local.id != updated.id ||
          local.phone != updated.phone) {
        throw StateError('Driver profile is not available on this device');
      }
      await LocalDriverRepository().updateProfile(
        local.copyWith(avatarUrl: url),
      );
      await _driverRepository.upsertDriver(updated);
      if (mounted) {
        setState(() {
          _driver = updated;
          _avatarBytes = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ఫోటో నవీకరించబడింది / Photo updated')),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _avatarBytes = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ఫోటో సేవ్ కాలేదు / Could not save photo'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingAvatar = false);
    }
  }

  DriverModel _driverWithAvatar(DriverModel driver, String url) => DriverModel(
    id: driver.id,
    name: driver.name,
    phone: driver.phone,
    village: driver.village,
    currentSpot: driver.currentSpot,
    vehicleType: driver.vehicleType,
    capacity: driver.capacity,
    isAvailable: driver.isAvailable,
    isDemo: driver.isDemo,
    vehicleNumber: driver.vehicleNumber,
    specializations: driver.specializations,
    currentSpotVillageId: driver.currentSpotVillageId,
    capacityTons: driver.capacityTons,
    avatarUrl: url,
    isPhoneVerified: driver.isPhoneVerified,
  );

  Future<void> _openWhatsApp() async {
    if (_driver.isDemo) return;
    final digits = _driver.phone.replaceAll(RegExp(r'[^0-9]'), '');
    final phone = digits.startsWith('91') ? digits : '91$digits';
    final text = Uri.encodeComponent(
      'నమస్కారం ${_driver.name}, Kolleru Wheels ద్వారా సంప్రదిస్తున్నాను.',
    );
    final uri = Uri.parse('https://wa.me/$phone?text=$text');
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
          mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('WhatsApp తెరవలేకపోయాం / Could not open WhatsApp'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('WhatsApp తెరవలేకపోయాం / Could not open WhatsApp'),
          ),
        );
      }
    }
  }

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
    final driver = _driver;
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
              LayoutBuilder(
                builder: (context, constraints) {
                  final callAction = CallButton(
                    phone: driver.phone,
                    contextNote: 'visiting_card:${driver.id}',
                    isDemo: driver.isDemo,
                    label: 'కాల్ / Call',
                    compact: true,
                  );
                  final whatsappAction = OutlinedButton(
                    key: const ValueKey('whatsapp-driver'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(58),
                      foregroundColor: const Color(0xFF187A52),
                      side: const BorderSide(color: Color(0x33187A52)),
                    ),
                    onPressed: driver.isDemo ? null : _openWhatsApp,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 20),
                        SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            'వాట్సాప్ / WhatsApp',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  );
                  if (constraints.maxWidth < 430) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        callAction,
                        const SizedBox(height: 10),
                        whatsappAction,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: callAction),
                      const SizedBox(width: 10),
                      Expanded(child: whatsappAction),
                    ],
                  );
                },
              ),
              if (_canEditAvatar) ...[
                const SizedBox(height: 14),
                Center(
                  child: DriverAvatarPicker(
                    name: driver.name,
                    imageUrl: driver.avatarUrl,
                    initialBytes: _avatarBytes,
                    size: 56,
                    editable: !_savingAvatar,
                    onPhotoSelected: _saveAvatar,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _savingAvatar
                      ? 'ఫోటో సేవ్ అవుతోంది / Saving photo…'
                      : 'ప్రొఫైల్ ఫోటో మార్చండి / Change profile photo',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 12),
              Builder(
                builder: (buttonContext) => FilledButton(
                  key: const ValueKey('share-visiting-card'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(64),
                  ),
                  onPressed: _sharing ? null : () => _shareCard(buttonContext),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_sharing)
                        const SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        const Icon(Icons.share, size: 28),
                      const SizedBox(width: 9),
                      Flexible(
                        child: Text(
                          _sharing
                              ? AppStrings.sharing
                              : AppStrings.shareStatus,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
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
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x1A19332C)),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: AppColors.charcoal,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.1,
          ),
        ),
      );

  Color _specializationColor(String label) {
    final value = label.toLowerCase();
    if (value.contains('fish') || value.contains('చేప')) {
      return const Color(0xFFEAF4FA);
    }
    if (value.contains('paddy') || value.contains('వరి')) {
      return const Color(0xFFEDF5E9);
    }
    if (value.contains('cement') || value.contains('సిమెంట్')) {
      return const Color(0xFFF7F0E7);
    }
    return const Color(0xFFF1F5F2);
  }

  String get _capacityLabel => driver.capacityTons == null
      ? driver.capacity
      : '${driver.capacityTons!.toStringAsFixed(driver.capacityTons! % 1 == 0 ? 0 : 1)} టన్నులు / Tons';

  @override
  Widget build(BuildContext context) => Card(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            color: const Color(0xFFF2F7F4),
            child: Row(
              children: [
                const Icon(
                  Icons.route_rounded,
                  color: AppColors.green,
                  size: 21,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    AppStrings.cardHeader,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: driver.isAvailable
                          ? const Color(0xFFE3F2EA)
                          : const Color(0xFFFFF3DC),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      driver.isAvailable
                          ? AppStrings.cardAvailable
                          : AppStrings.busy,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: driver.isAvailable
                            ? const Color(0xFF176744)
                            : const Color(0xFF8A5A0A),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: DriverAvatarPicker(
                        name: driver.name,
                        imageUrl: driver.avatarUrl,
                        editable: false,
                        size: 74,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  driver.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall,
                                ),
                              ),
                              if (driver.isPhoneVerified) ...[
                                const SizedBox(width: 5),
                                const Tooltip(
                                  message: 'Verified phone',
                                  child: Icon(
                                    Icons.verified,
                                    color: Color(0xFF147A58),
                                    size: 21,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 8),
                          _badge(
                            driver.vehicleType.label,
                            color: const Color(0xFFF1F5F2),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _capacityLabel,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(color: const Color(0xFF176744)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _badge(
                      '${AppStrings.vehicleNumber}: ${driver.vehicleNumber.isEmpty ? AppStrings.numberPending : driver.vehicleNumber}',
                      color: const Color(0xFFF1F5F2),
                    ),
                    for (final tag in driver.specializations)
                      _badge(tag, color: _specializationColor(tag)),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 15),
                  child: Divider(height: 1),
                ),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 18,
                      color: Color(0xFF64736D),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        '${driver.village.label} · ${driver.currentSpot}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
                if (driver.isDemo) ...[
                  const SizedBox(height: 12),
                  Text(
                    AppStrings.demo,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
          Container(
            color: const Color(0xFF19332C),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            child: Row(
              children: [
                const Icon(
                  Icons.call_outlined,
                  color: Color(0xFFA9DFC5),
                  size: 19,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    driver.phone,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(color: Colors.white, letterSpacing: 0.1),
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
