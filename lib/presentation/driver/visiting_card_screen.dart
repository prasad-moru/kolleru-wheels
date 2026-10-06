import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../data/models/driver_model.dart';
import '../common/audio_cue_button.dart';
import '../common/call_button.dart';

class VisitingCardScreen extends StatelessWidget {
  const VisitingCardScreen({super.key, required this.driver});
  final DriverModel driver;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text(AppStrings.visitingCard)),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.local_shipping,
                      size: 64,
                      color: AppColors.green,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      driver.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(
                      driver.vehicleType.label,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Divider(height: 32),
                    Text(driver.village.label),
                    Text('${AppStrings.currentSpot}: ${driver.currentSpot}'),
                    Text('${AppStrings.capacity}: ${driver.capacity}'),
                    const SizedBox(height: 12),
                    Text(
                      driver.isAvailable
                          ? AppStrings.available
                          : AppStrings.busy,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SelectableText(driver.phone),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            CallButton(phone: driver.phone, isDemo: driver.isDemo),
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
