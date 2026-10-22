import 'package:flutter/material.dart';

import '../../core/localization/app_language_provider.dart';

class LanguageSwitchButton extends StatelessWidget {
  const LanguageSwitchButton({
    super.key,
    required this.language,
    this.enabled = true,
  });
  final AppLanguageProvider language;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 12),
    child: OutlinedButton.icon(
      key: const ValueKey('language-toggle'),
      onPressed: enabled ? language.toggleLanguage : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF0F5132),
        backgroundColor: Colors.white,
        side: const BorderSide(color: Color(0xFFCEEAD6)),
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: const StadiumBorder(),
      ),
      icon: const Icon(Icons.translate, size: 18),
      label: Text(language.tr(te: 'English', en: 'తెలుగు')),
    ),
  );
}
