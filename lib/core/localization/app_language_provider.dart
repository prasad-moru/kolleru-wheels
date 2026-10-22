import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage { telugu, english }

/// Small, offline language preference; no translation or image downloads.
class AppLanguageProvider extends ChangeNotifier {
  static const preferenceKey = 'selected_language';
  AppLanguage _selectedLanguage = AppLanguage.telugu;
  AppLanguage get selectedLanguage => _selectedLanguage;
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  int _revision = 0;
  bool _disposed = false;

  Future<void> load() => _loading ??= _readPreference();

  Future<void> _readPreference() async {
    final revision = _revision;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_disposed || revision != _revision) return;
      _selectedLanguage = prefs.getString(preferenceKey) == 'english'
          ? AppLanguage.english
          : AppLanguage.telugu;
      notifyListeners();
    } catch (_) {
      // Telugu remains available if device preferences cannot be read.
    }
  }

  Future<void> toggleLanguage() => setLanguage(
    _selectedLanguage == AppLanguage.telugu
        ? AppLanguage.english
        : AppLanguage.telugu,
  );

  Future<void> setLanguage(AppLanguage language) {
    if (_disposed) return Future.value();
    _revision++;
    _selectedLanguage = language;
    notifyListeners();
    // Serial writes preserve the last choice when the switch is tapped rapidly.
    _writes = _writes.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(preferenceKey, language.name);
    }).catchError((Object _) {
      // Keep the current session usable when local storage is unavailable.
    });
    return _writes;
  }

  String tr({required String te, required String en}) =>
      _selectedLanguage == AppLanguage.telugu ? te : en;

  /// Adapter for existing paired constants; stored commodity values stay stable.
  String label(String pairedLabel) {
    final separator = pairedLabel.indexOf(' / ');
    if (separator < 0) return pairedLabel;
    return tr(
      te: pairedLabel.substring(0, separator),
      en: pairedLabel.substring(separator + 3),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class AppLanguageScope extends InheritedNotifier<AppLanguageProvider> {
  const AppLanguageScope({
    super.key,
    required AppLanguageProvider language,
    required super.child,
  }) : super(notifier: language);

  static AppLanguageProvider? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AppLanguageScope>()
      ?.notifier;
}

/// Standalone auth screens also load the preference when no app scope is present.
abstract class LanguageAwareState<T extends StatefulWidget> extends State<T> {
  AppLanguageProvider? _language;
  bool _ownsLanguage = false;
  AppLanguageProvider get language => _language!;

  String tr({required String te, required String en}) =>
      language.tr(te: te, en: en);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final inherited = AppLanguageScope.maybeOf(context);
    if (_language != null &&
        (identical(inherited, _language) ||
            (inherited == null && _ownsLanguage))) {
      return;
    }
    _language?.removeListener(_languageChanged);
    if (_ownsLanguage) _language?.dispose();
    _language = inherited ?? AppLanguageProvider();
    _ownsLanguage = inherited == null;
    language.addListener(_languageChanged);
    if (_ownsLanguage) unawaited(language.load());
  }

  void _languageChanged() {
    if (!mounted) return;
    setState(() {});
    onLanguageChanged();
  }

  /// Revalidate submitted forms without clearing their input when labels change.
  @protected
  void onLanguageChanged() {}

  @override
  void dispose() {
    _language?.removeListener(_languageChanged);
    if (_ownsLanguage) _language?.dispose();
    super.dispose();
  }
}
