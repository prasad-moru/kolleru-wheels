import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/localization/app_language_provider.dart';
import '../../data/repositories/auth_repository.dart';
import '../auth/session_router.dart';

class WelcomeDiscoveryScreen extends StatefulWidget {
  const WelcomeDiscoveryScreen({super.key, this.authRepository});
  final AuthRepository? authRepository;
  static const preferenceKey = 'has_seen_welcome';

  @override
  State<WelcomeDiscoveryScreen> createState() => _WelcomeDiscoveryScreenState();
}

class _WelcomeDiscoveryScreenState
    extends LanguageAwareState<WelcomeDiscoveryScreen> {
  static const _green = Color(0xFF0A6836);
  final _pages = PageController(viewportFraction: 0.82);
  final _phone = TextEditingController();
  final _form = GlobalKey<FormState>();
  late final _auth = widget.authRepository ?? AuthRepository.instance;
  int _step = 0;
  bool _saving = false;
  bool _validated = false;

  static const _slides = [
    (
      teTitle: 'మీ అవసరానికి తగిన వాహనం ఎంచుకోండి',
      enTitle: 'Choose Vehicle for Any Load',
      teBody: 'పంట, మేత, మంచు, మార్కెట్ సరుకులకు బొలెరో, 709, టిప్పర్ వాహనాలు.',
      enBody: 'Bolero, 709 and Tipper vehicles for harvest, feed, ice and market goods.',
      icon: Icons.local_shipping_outlined,
    ),
    (
      teTitle: 'డ్రైవర్ వివరాలు & సామర్థ్యం చూడండి',
      enTitle: 'Check Driver & Ton Capacity',
      teBody: 'ధృవీకరించిన ఫోన్ వివరాలు, 2–8 టన్నుల సామర్థ్యం చూడండి.',
      enBody: 'Check verified phone details and 2T–8T vehicle capacity.',
      icon: Icons.verified_outlined,
    ),
    (
      teTitle: 'నేరుగా మాట్లాడి బుక్ చేసుకోండి',
      enTitle: 'Direct Call & Zero Commission',
      teBody: 'డ్రైవర్‌తో నేరుగా మాట్లాడండి. మధ్యవర్తులు లేరు, కమీషన్ లేదు.',
      enBody: 'Talk to the driver and agree your price. No middlemen or commission.',
      icon: Icons.phone_in_talk_outlined,
    ),
  ];

  @override
  void onLanguageChanged() {
    if (_validated) _form.currentState?.validate();
  }

  Future<void> _start({bool guest = false}) async {
    if (_saving) return;
    if (!guest && !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setBool(WelcomeDiscoveryScreen.preferenceKey, true)) {
        throw StateError('Could not save welcome preference');
      }
      if (guest) {
        try {
          await _auth.browseAsGuest();
        } catch (_) {
          // The repository still clears local identity on remote sign-out failure.
        }
      }
      if (!mounted) return;
      final duration = MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 280);
      Navigator.of(context).pushReplacement<void, void>(
        PageRouteBuilder<void>(
          settings: const RouteSettings(name: '/auth'),
          transitionDuration: duration,
          pageBuilder: (_, _, _) => SessionRouter(
            repository: _auth,
            initialOtpPhone: guest ? null : _phone.text,
          ),
          transitionsBuilder: (_, animation, _, child) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: animation.drive(
                Tween(
                  begin: const Offset(0, 0.04),
                  end: Offset.zero,
                ).chain(CurveTween(curve: Curves.easeOut)),
              ),
              child: child,
            ),
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                te: 'సేవ్ కాలేదు. మళ్లీ ప్రయత్నించండి.',
                en: 'Could not save. Please try again.',
              ),
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    _phone.dispose();
    super.dispose();
  }

  bool _stackHeader(BuildContext context) =>
      MediaQuery.sizeOf(context).width <
      360 * MediaQuery.textScalerOf(context).scale(15) / 15;

  Widget _brand() => Row(
    children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _green,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Text(
          'KW',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          tr(te: 'కొల్లేరు వీల్స్', en: 'Kolleru Wheels'),
          maxLines: 2,
          style: const TextStyle(
            color: _green,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );

  Widget _languageButton() => Padding(
    padding: const EdgeInsets.only(right: 12),
    child: OutlinedButton(
      key: const ValueKey('language-toggle'),
      style: OutlinedButton.styleFrom(
        foregroundColor: _green,
        shape: const StadiumBorder(),
      ),
      onPressed: _saving ? null : language.toggleLanguage,
      child: Text(tr(te: '🌐 EN', en: '🌐 తెలుగు')),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF2F7F4),
    appBar: AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: Colors.white,
      toolbarHeight: _stackHeader(context) ? 160 : 76,
      titleSpacing: 16,
      title: _stackHeader(context)
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _brand(),
                Align(
                  alignment: Alignment.centerRight,
                  child: _languageButton(),
                ),
              ],
            )
          : _brand(),
      actions: _stackHeader(context) ? null : [_languageButton()],
    ),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                        child: Text(
                          tr(te: 'యాప్ ఎలా పనిచేస్తుంది?', en: 'How it works'),
                          style: const TextStyle(
                            color: _green,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 212 * scale,
                        child: PageView.builder(
                          key: const ValueKey('welcome-pages'),
                          controller: _pages,
                          itemCount: _slides.length,
                          onPageChanged: (step) => setState(() => _step = step),
                          itemBuilder: (context, step) {
                            final slide = _slides[step];
                            return Container(
                              key: ValueKey('welcome-slide-$step'),
                              margin: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3FFF8),
                                border: Border.all(
                                  color: const Color(0xFFBDE5CE),
                                ),
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Icon(
                                          slide.icon,
                                          color: _green,
                                          size: 30,
                                        ),
                                        Text(
                                          tr(
                                            te: '${step + 1}వ దశ',
                                            en: '${step + 1} of 3',
                                          ),
                                          style: const TextStyle(color: _green),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      tr(te: slide.teTitle, en: slide.enTitle),
                                      key: ValueKey('welcome-title-$step'),
                                      style: const TextStyle(
                                        color: _green,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      tr(te: slide.teBody, en: slide.enBody),
                                      style: const TextStyle(
                                        color: Color(0xFF365B47),
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var step = 0; step < 3; step++)
                            Semantics(
                              selected: step == _step,
                              button: true,
                              label: tr(
                                te: '${step + 1}వ దశ',
                                en: 'Step ${step + 1} of 3',
                              ),
                              child: InkWell(
                                key: ValueKey('welcome-dot-$step'),
                                onTap: () => _pages.animateToPage(
                                  step,
                                  duration:
                                      MediaQuery.disableAnimationsOf(context)
                                      ? Duration.zero
                                      : const Duration(milliseconds: 250),
                                  curve: Curves.easeOut,
                                ),
                                child: SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: Center(
                                    child: Container(
                                      width: 7,
                                      height: 7,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: step == _step
                                            ? _green
                                            : const Color(0xFFBDE5CE),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 24),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _green.withValues(alpha: 0.08),
                          blurRadius: 24,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            tr(
                              te: 'ప్రయాణం ప్రారంభించండి',
                              en: 'Start your journey',
                            ),
                            style: const TextStyle(
                              color: _green,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            key: const ValueKey('phone-input-field'),
                            controller: _phone,
                            enabled: !_saving,
                            keyboardType: TextInputType.phone,
                            autofillHints: const [
                              AutofillHints.telephoneNumberNational,
                            ],
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(10),
                            ],
                            decoration: InputDecoration(
                              labelText: tr(
                                te: 'మొబైల్ నంబర్',
                                en: 'Mobile number',
                              ),
                              prefixIcon: Container(
                                margin: const EdgeInsets.all(8),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF2F7F4),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  '+91',
                                  style: TextStyle(
                                    color: _green,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            validator: (value) {
                              try {
                                AuthRepository.normalizePhone(value ?? '');
                                return null;
                              } on FormatException {
                                return tr(
                                  te: 'సరైన 10 అంకెల మొబైల్ నెంబర్ ఇవ్వండి',
                                  en: 'Enter a valid 10-digit Indian mobile number',
                                );
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            key: const ValueKey('get-otp-button'),
                            style: FilledButton.styleFrom(
                              backgroundColor: _green,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(52),
                            ),
                            onPressed: _saving
                                ? null
                                : () {
                                    _validated = true;
                                    _start();
                                  },
                            child: Text(
                              tr(te: 'OTP పొందండి', en: 'Get OTP'),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              children: [
                                const Expanded(child: Divider()),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  child: Text(tr(te: 'లేదా', en: 'OR')),
                                ),
                                const Expanded(child: Divider()),
                              ],
                            ),
                          ),
                          OutlinedButton(
                            key: const ValueKey('guest-exit-button'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _green,
                              side: const BorderSide(color: _green),
                              minimumSize: const Size.fromHeight(50),
                            ),
                            onPressed: _saving
                                ? null
                                : () => _start(guest: true),
                            child: Text(
                              tr(
                                te: 'అందుబాటులో ఉన్న వాహనాలు చూడండి',
                                en: 'Explore Available Vehicles',
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            tr(
                              te: 'మధ్యవర్తులు లేరు • బ్రోకర్లు లేరు • కమీషన్ లేదు',
                              en: 'No middlemen • No brokers • Zero commission',
                            ),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: _green, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}
