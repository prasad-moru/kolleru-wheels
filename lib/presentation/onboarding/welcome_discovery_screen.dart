import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/localization/app_language_provider.dart';
import '../../data/repositories/auth_repository.dart';
import '../auth/session_router.dart';
import '../common/language_switch_button.dart';
import 'components/aqua_illustrations.dart';

class WelcomeDiscoveryScreen extends StatefulWidget {
  const WelcomeDiscoveryScreen({super.key, this.authRepository});
  final AuthRepository? authRepository;
  static const preferenceKey = 'has_seen_welcome';

  @override
  State<WelcomeDiscoveryScreen> createState() => _WelcomeDiscoveryScreenState();
}

class _WelcomeDiscoveryScreenState
    extends LanguageAwareState<WelcomeDiscoveryScreen> {
  final _pages = PageController();
  int _step = 0;
  bool _saving = false;

  static const _slides = [
    (
      teTitle: 'చెరువు నుంచి గమ్యం వరకు',
      enTitle: 'From your pond to the road',
      teBody: 'చేపలు, రొయ్యల రవాణాకు స్థానిక వాహనాలు. కైకలూరు, ఆకివీడు, భీమవరం మార్గాల్లో నేరుగా డ్రైవర్లను కనుగొనండి.',
      enBody: 'Find local vehicles for fish and prawn transport across Kaikaluru, Akividu and Bhimavaram routes.',
    ),
    (
      teTitle: 'మీ సరుకుకు సరైన వాహనం',
      enTitle: 'Find the right vehicle',
      teBody: 'మధ్యవర్తులు లేకుండా డ్రైవర్ కార్డులు చూడండి. వాహన సామర్థ్యం, సరుకు రకం, ధృవీకరించిన ఫోన్ వివరాలు ఒకే చోట.',
      enBody: 'Discover drivers directly, without middlemen. Compare stated capacities, cargo types and verified phone details on their cards.',
    ),
    (
      teTitle: 'ఒక్క ట్యాప్‌తో పరిచయం',
      enTitle: 'One tap. A direct connection.',
      teBody: 'రైతు, డ్రైవర్ నేరుగా మాట్లాడుకోవచ్చు. ఫోన్ లేదా వాట్సాప్‌లో రవాణా వివరాలు, ధర మీరే నిర్ణయించుకోండి.',
      enBody: 'Call or WhatsApp a driver directly. Discuss your load, route and price together, on your terms.',
    ),
  ];

  Future<void> _start() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setBool(WelcomeDiscoveryScreen.preferenceKey, true)) {
        throw StateError('Could not save welcome preference');
      }
      if (!mounted) return;
      final duration = MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 280);
      Navigator.of(context).pushReplacement<void, void>(PageRouteBuilder<void>(
        settings: const RouteSettings(name: '/auth'),
        transitionDuration: duration,
        pageBuilder: (_, _, _) =>
            SessionRouter(repository: widget.authRepository),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: animation.drive(
              Tween(begin: const Offset(0, 0.04), end: Offset.zero)
                  .chain(CurveTween(curve: Curves.easeOut)),
            ),
            child: child,
          ),
        ),
      ));
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(
            te: 'సేవ్ కాలేదు. మళ్లీ ప్రయత్నించండి.',
            en: 'Could not save. Please try again.',
          ))),
        );
      }
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Widget _languageAction(BuildContext context) {
    final media = MediaQuery.of(context);
    final availableWidth = media.size.width - media.padding.horizontal;
    final textScale = media.textScaler.scale(15) / 15;
    if (availableWidth >= 360 * textScale) {
      return LanguageSwitchButton(language: language, enabled: !_saving);
    }

    // Keep the logo and language control usable when text needs more room.
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: IconButton.outlined(
        key: const ValueKey('language-toggle'),
        tooltip: tr(te: 'English', en: 'తెలుగు'),
        onPressed: _saving ? null : language.toggleLanguage,
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: const Color(0xFF0F5132),
          backgroundColor: Colors.white,
        ),
        icon: const Icon(Icons.translate, size: 20),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFAFCF9),
    appBar: AppBar(
      automaticallyImplyLeading: false,
      toolbarHeight: 72,
      titleSpacing: 8,
      title: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFE6F4EA),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.local_shipping_outlined,
              color: Color(0xFF0F5132),
              size: 21,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                tr(te: 'కొల్లేరు వీల్స్', en: 'Kolleru Wheels'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
      actions: [_languageAction(context)],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: PageView.builder(
              key: const ValueKey('welcome-pages'),
              controller: _pages,
              itemCount: _slides.length,
              onPageChanged: (step) => setState(() => _step = step),
              itemBuilder: (context, step) {
                final slide = _slides[step];
                return SingleChildScrollView(
                  key: ValueKey('welcome-slide-$step'),
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          OnboardingIllustrationCard(
                            step: step,
                            language: language.selectedLanguage,
                          ),
                          const SizedBox(height: 28),
                          Text(
                            tr(te: slide.teTitle, en: slide.enTitle),
                            key: ValueKey('welcome-title-$step'),
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: const Color(0xFF0F5132),
                              fontSize: 28,
                              height: 1.25,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            tr(te: slide.teBody, en: slide.enBody),
                            style: const TextStyle(
                              fontSize: 17,
                              height: 1.6,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var step = 0; step < _slides.length; step++)
                      Semantics(
                        selected: step == _step,
                        button: true,
                        label: tr(te: '${step + 1}వ పేజీ', en: 'Page ${step + 1} of 3'),
                        child: InkWell(
                          key: ValueKey('welcome-dot-$step'),
                          borderRadius: BorderRadius.circular(24),
                          onTap: () => _pages.animateToPage(
                            step,
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 250),
                            curve: Curves.easeOut,
                          ),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: Center(
                              child: AnimatedContainer(
                                duration: MediaQuery.disableAnimationsOf(context)
                                    ? Duration.zero
                                    : const Duration(milliseconds: 200),
                                width: step == _step ? 24 : 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: step == _step
                                      ? const Color(0xFF0F5132)
                                      : const Color(0xFFBAD8C3),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const ValueKey('welcome-get-started'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F5132),
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(60),
                    ),
                    onPressed: _saving ? null : _start,
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: Text(tr(te: 'ప్రారంభించండి', en: 'Get Started')),
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
