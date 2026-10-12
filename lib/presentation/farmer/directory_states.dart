import 'package:flutter/material.dart';

import '../../core/constants/app_strings.dart';

class DirectoryEmptyState extends StatelessWidget {
  const DirectoryEmptyState({super.key, required this.onReset});
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('directory-empty'),
    margin: const EdgeInsets.only(top: 16),
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE2E8F0), width: 0.5),
    ),
    child: Column(
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: const BoxDecoration(
            color: Color(0xFFECFDF5),
            shape: BoxShape.circle,
          ),
          child: const Stack(
            alignment: Alignment.center,
            children: [
              Icon(Icons.local_shipping_outlined, size: 48, color: Color(0xFF0F5132)),
              Positioned(
                right: 10,
                bottom: 14,
                child: Icon(Icons.search, size: 28, color: Color(0xFF047857)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          AppStrings.noDrivers,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(AppStrings.emptyDirectoryHint, textAlign: TextAlign.center),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: onReset,
          icon: const Icon(Icons.filter_alt_off_outlined),
          label: const Text(AppStrings.reset, textAlign: TextAlign.center),
        ),
      ],
    ),
  );
}

/// Animated only while fetching. Reduced-motion users see static placeholders.
class DirectoryLoadingState extends StatefulWidget {
  const DirectoryLoadingState({super.key});

  @override
  State<DirectoryLoadingState> createState() => _DirectoryLoadingStateState();
}

class _DirectoryLoadingStateState extends State<DirectoryLoadingState>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.stop();
    } else {
      _animation.repeat();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  Widget _block(double width, double height) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: const Color(0xFFE2E8F0),
      borderRadius: BorderRadius.circular(10),
    ),
  );

  Widget _skeleton() => Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE2E8F0), width: 0.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _block(60, 60),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FractionallySizedBox(widthFactor: 0.8, child: _block(double.infinity, 16)),
                  const SizedBox(height: 10),
                  FractionallySizedBox(widthFactor: 0.6, child: _block(double.infinity, 12)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _block(double.infinity, 28),
        const SizedBox(height: 16),
        _block(double.infinity, 52),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Semantics(
    label: AppStrings.loadingDrivers,
    liveRegion: true,
    child: ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) => ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(-3 + 6 * _animation.value, -0.3),
            end: Alignment(-1 + 6 * _animation.value, 0.3),
            colors: const [Color(0x00FFFFFF), Color(0x99FFFFFF), Color(0x00FFFFFF)],
          ).createShader(bounds),
          child: child,
        ),
        child: Column(children: [_skeleton(), _skeleton()]),
      ),
    ),
  );
}
