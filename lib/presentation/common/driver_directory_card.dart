import 'package:flutter/material.dart';

import '../../core/constants/app_strings.dart';
import '../../core/constants/villages.dart';
import '../../core/theme/driver_card_style.dart';
import '../../core/utils/proximity_matcher.dart';
import '../../data/models/driver_model.dart';
import 'call_button.dart';
import 'driver_avatar_picker.dart';

/// Compact directory listing. The exported visiting card keeps its own layout.
class DriverDirectoryCard extends StatelessWidget {
  const DriverDirectoryCard({
    super.key,
    required this.driver,
    required this.onOpen,
    required this.onWhatsApp,
    this.callerPhone,
  });

  final DriverModel driver;
  final VoidCallback onOpen;
  final VoidCallback onWhatsApp;
  final String? callerPhone;

  static const _ink = Color(0xFF0F172A);
  static const _slate = Color(0xFF475569);
  static const _line = Color(0xFFE2E8F0);

  Widget _avatar(Color accent) => SizedBox.square(
    dimension: 68,
    child: Stack(
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent.withValues(alpha: 0.18),
            border: Border.all(color: accent.withValues(alpha: 0.4)),
          ),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: DriverAvatarPicker(
              name: driver.name,
              imageUrl: driver.avatarUrl,
              size: 56,
              editable: false,
            ),
          ),
        ),
        if (driver.isPhoneVerified)
          Positioned(
            right: 0,
            bottom: 0,
            child: Tooltip(
              message: AppStrings.verifiedPhone,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.verified,
                  size: 22,
                  color: Color(0xFF047857),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _pill(String label, {bool commodity = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: commodity ? const Color(0xFFDCFCE7) : const Color(0xFFE0F2FE),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: commodity ? const Color(0xFF15803D) : const Color(0xFF0369A1),
        fontSize: 13,
        height: 1.35,
        fontWeight: FontWeight.w500,
      ),
    ),
  );

  Widget _availability() => Container(
    key: ValueKey('availability-${driver.id}'),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: driver.isAvailable
          ? const Color(0xFFDCFCE7)
          : const Color(0xFFFEF3C7),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.circle,
          size: 7,
          color: driver.isAvailable
              ? const Color(0xFF166534)
              : const Color(0xFF92400E),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            driver.isAvailable ? AppStrings.available : AppStrings.busy,
            style: TextStyle(
              color: driver.isAvailable
                  ? const Color(0xFF166534)
                  : const Color(0xFF92400E),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final accent = DriverCardStyle.resolve(driver.cardStyle).accent;
    final mandalId = ProximityMatcher.mandalId(driver.village.id);
    final mandal = KolleruVillages.mandals
        .where((mandal) => mandal.id == mandalId)
        .firstOrNull;
    final location = [
      driver.village.label,
      if (mandal != null) '${mandal.teluguName} / ${mandal.name}',
    ].join(' · ');
    final capacity = driver.capacityTons == null
        ? driver.capacity
        : '${driver.capacityTons!.toStringAsFixed(driver.capacityTons! % 1 == 0 ? 0 : 1)} టన్నులు / Tons';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                key: ValueKey('style-strip-${driver.id}'),
                height: 5,
                color: accent,
              ),
              InkWell(
                onTap: onOpen,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: _availability(),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _avatar(accent),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  driver.name,
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(
                                        color: _ink,
                                        fontWeight: FontWeight.w600,
                                        fontFamilyFallback: const ['Inter', 'Noto Sans Telugu'],
                                        letterSpacing: -0.35,
                                      ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Icon(
                                        Icons.location_on_outlined,
                                        size: 14,
                                        color: _slate,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Expanded(
                                      child: Text(
                                        location,
                                        style: const TextStyle(
                                          color: _slate,
                                          fontSize: 13,
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 7,
                        runSpacing: 8,
                        children: [
                          _pill(driver.vehicleType.label),
                          _pill(capacity),
                          for (final tag in driver.specializations)
                            _pill(tag, commodity: true),
                        ],
                      ),
                      if (driver.currentSpot != driver.village.label) ...[
                        const SizedBox(height: 14),
                        Text(
                          '${AppStrings.currentSpot}: ${driver.currentSpot}',
                          style: const TextStyle(color: _slate, fontSize: 13),
                        ),
                      ],
                      if (driver.isDemo) ...[
                        const SizedBox(height: 10),
                        const Text(
                          AppStrings.demoCall,
                          style: TextStyle(color: _slate, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: Color(0xFFFAFCFB),
                  border: Border(top: BorderSide(color: _line, width: 0.5)),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final call = CallButton(
                      phone: driver.phone,
                      isDemo: driver.isDemo,
                      label: AppStrings.call,
                      compact: true,
                      backgroundColor: const Color(0xFF059669),
                      elevated: true,
                      callerPhone: callerPhone,
                      callerRole: 'shipper',
                      contextNote: 'directory:${driver.id}',
                    );
                    final whatsapp = OutlinedButton(
                      key: ValueKey('whatsapp-${driver.id}'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(58),
                        backgroundColor: const Color(0xFFECFDF5),
                        foregroundColor: const Color(0xFF047857),
                        side: const BorderSide(color: Color(0xFFA7F3D0)),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      onPressed: driver.isDemo ? null : onWhatsApp,
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline, size: 21),
                          SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              AppStrings.whatsapp,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    );
                    if (constraints.maxWidth < 280 ||
                        MediaQuery.textScalerOf(context).scale(16) > 22) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [call, const SizedBox(height: 8), whatsapp],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: call),
                        const SizedBox(width: 10),
                        Expanded(child: whatsapp),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
