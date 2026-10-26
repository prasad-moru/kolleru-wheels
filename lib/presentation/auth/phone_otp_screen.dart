import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/localization/app_language_provider.dart';
import '../../data/models/user_profile_model.dart';
import '../../data/repositories/auth_repository.dart';
import '../common/language_switch_button.dart';
import 'complete_profile_screen.dart';
import 'onboarding_navigation.dart';

class PhoneOtpScreen extends StatefulWidget {
  const PhoneOtpScreen({
    super.key,
    this.repository,
    this.initialOtpPhone,
    required this.onVerified,
  });
  final AuthRepository? repository;
  final String? initialOtpPhone;
  final void Function(UserProfile) onVerified;
  @override
  State<PhoneOtpScreen> createState() => _PhoneOtpScreenState();
}

class _PhoneOtpScreenState extends LanguageAwareState<PhoneOtpScreen> {
  late final _auth = widget.repository ?? AuthRepository.instance;
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _register = false;
  bool _sent = false;
  bool _busy = false;
  bool _validated = false;
  int _seconds = 0;
  Timer? _timer;
  String? _registrationPhone;
  ({String te, String en})? _error;

  @override
  void onLanguageChanged() {
    if (_validated && !_sent) _form.currentState?.validate();
  }

  @override
  void initState() {
    super.initState();
    final pending = _auth.onboardingPhone;
    if (pending != null && _auth.verifiedPhone == pending) {
      _registrationPhone = pending;
    } else if (widget.initialOtpPhone != null) {
      _phone.text = widget.initialOtpPhone!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _send();
      });
    }
  }

  void _showError({required String te, required String en}) {
    if (!mounted) return;
    setState(() => _error = (te: te, en: en));
    final errorLanguage = language;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: AnimatedBuilder(
            animation: errorLanguage,
            builder: (_, _) => Text(errorLanguage.tr(te: te, en: en)),
          ),
        ),
      );
  }

  Future<void> _send() async {
    if (_busy || _seconds > 0) return;
    if (!_sent) {
      _validated = true;
      if (!_form.currentState!.validate()) return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.signInWithOtp(phone: _phone.text, role: 'shipper');
      if (!mounted) return;
      setState(() {
        _sent = true;
        _seconds = 60;
      });
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(
          () => _seconds =
              (deadline.difference(DateTime.now()).inMilliseconds / 1000)
                  .ceil()
                  .clamp(0, 60),
        );
        if (_seconds == 0) timer.cancel();
      });
    } catch (_) {
      _showError(
        te: 'SMS పంపడం విఫలమైంది. నంబర్ సరిచూసి మళ్లీ ప్రయత్నించండి.',
        en: 'Could not send SMS. Check your number and try again.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final profile = await _auth.verifyOTP(
        phone: _phone.text,
        token: _otp.text,
      );
      if (!mounted) return;
      _timer?.cancel();
      if (profile != null) {
        widget.onVerified(profile);
      } else {
        setState(
          () => _registrationPhone = AuthRepository.normalizePhone(_phone.text),
        );
      }
    } catch (_) {
      _showError(
        te: 'OTP సరికాదు. కోడ్ సరిచూడండి లేదా మళ్లీ పంపండి.',
        en: 'Verification failed. Check code or resend.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    if (_busy) return;
    _timer?.cancel();
    await leaveOnboarding(context, _auth);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _otp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_registrationPhone != null) {
      return AppLanguageScope(
        language: language,
        child: CompleteProfileScreen(
          phone: _registrationPhone!,
          repository: _auth,
          onCompleted: widget.onVerified,
        ),
      );
    }
    return OnboardingBackScope(
      enabled: !_busy,
      onExit: _leave,
      child: Scaffold(
        appBar: AppBar(
          actions: [LanguageSwitchButton(language: language, enabled: !_busy)],
          title: Text(
            _register
                ? tr(te: 'నమోదు', en: 'Register')
                : tr(te: 'లాగిన్', en: 'Sign in'),
          ),
          leading: IconButton(
            key: const ValueKey('onboarding-back'),
            tooltip: tr(te: 'రద్దు చేయండి', en: 'Cancel'),
            onPressed: _busy ? null : _leave,
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: OutlinedButton.icon(
            key: const ValueKey('browse-guest'),
            onPressed: _busy ? null : _leave,
            style: OutlinedButton.styleFrom(
              backgroundColor: const Color(0xFFECFDF5),
              foregroundColor: const Color(0xFF0A6836),
            ),
            icon: const Icon(Icons.agriculture_outlined),
            label: Text(
              tr(te: 'లాగిన్ లేకుండా చూడండి', en: 'Browse as guest'),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (!_sent) ...[
                const Icon(
                  Icons.local_shipping_outlined,
                  size: 40,
                  color: Color(0xFF0A6836),
                ),
                const SizedBox(height: 14),
                Text(
                  tr(te: 'కొల్లేరు వీల్స్', en: 'Kolleru Wheels'),
                  key: const ValueKey('login-hero'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  tr(
                    te: 'మన ఊరి వాహనాలు, నేరుగా పరిచయాలు',
                    en: 'Local vehicles. Direct connections.',
                  ),
                ),
                const SizedBox(height: 24),
              ],
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFCDEBDA)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final register in [false, true])
                          ChoiceChip(
                            selected: _register == register,
                            showCheckmark: false,
                            selectedColor: const Color(0xFF0A6836),
                            labelStyle: TextStyle(
                              color: _register == register
                                  ? Colors.white
                                  : const Color(0xFF365B47),
                            ),
                            label: Text(
                              register
                                  ? tr(te: 'కొత్త నమోదు', en: 'Register')
                                  : tr(te: 'లాగిన్', en: 'Login'),
                              key: ValueKey(
                                register ? 'register-tab' : 'login-tab',
                              ),
                            ),
                            onSelected: _busy || _sent
                                ? null
                                : (_) => setState(() {
                                    _register = register;
                                    _error = null;
                                  }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (_auth.isMock)
                      Text(
                        tr(
                          te: 'డెమో కోసం OTP 123456 వాడండి. SMS పంపబడదు.',
                          en: 'Demo sign-in: use OTP 123456. No SMS is sent.',
                        ),
                      ),
                    if (!_sent)
                      Form(
                        key: _form,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: TextFormField(
                            key: const ValueKey('auth-phone'),
                            controller: _phone,
                            enabled: !_busy,
                            keyboardType: TextInputType.phone,
                            inputFormatters: [
                              TextInputFormatter.withFunction((
                                oldValue,
                                newValue,
                              ) {
                                var digits = newValue.text.replaceAll(
                                  RegExp(r'[^0-9]'),
                                  '',
                                );
                                if (digits.length == 12 &&
                                    digits.startsWith('91')) {
                                  digits = digits.substring(2);
                                }
                                return TextEditingValue(
                                  text: digits,
                                  selection: TextSelection.collapsed(
                                    offset: digits.length,
                                  ),
                                );
                              }),
                            ],
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w500,
                            ),
                            autofillHints: const [
                              AutofillHints.telephoneNumberNational,
                            ],
                            decoration: InputDecoration(
                              prefixIconConstraints: const BoxConstraints(
                                minWidth: 74,
                              ),
                              prefixIcon: Container(
                                margin: const EdgeInsets.all(8),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFECFDF5),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  '+91',
                                  style: TextStyle(
                                    color: Color(0xFF0A6836),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              labelText: tr(
                                te: 'ఫోన్ నంబర్',
                                en: 'Phone number',
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
                        ),
                      ),
                    const SizedBox(height: 24),
                    if (_sent) ...[
                      Text(
                        tr(
                          te: 'OTP పంపబడింది: +91${_phone.text}',
                          en: 'Code sent to +91${_phone.text}',
                        ),
                      ),
                      TextField(
                        key: const ValueKey('auth-otp'),
                        controller: _otp,
                        enabled: !_busy,
                        keyboardType: TextInputType.number,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        decoration: InputDecoration(
                          labelText: tr(te: '6 అంకెల OTP', en: '6-digit OTP'),
                        ),
                      ),
                      FilledButton(
                        key: const ValueKey('verify-otp'),
                        onPressed: _busy ? null : _verify,
                        child: Text(tr(te: 'ధృవీకరించండి', en: 'Verify OTP')),
                      ),
                      TextButton(
                        onPressed: _busy || _seconds > 0 ? null : _send,
                        child: Text(
                          _seconds > 0
                              ? tr(
                                  te: '$_seconds సెకన్లలో మళ్లీ పంపండి',
                                  en: 'Resend in ${_seconds}s',
                                )
                              : tr(te: 'OTP మళ్లీ పంపండి', en: 'Resend OTP'),
                        ),
                      ),
                    ] else
                      FilledButton(
                        key: const ValueKey('send-otp'),
                        onPressed: _busy ? null : _send,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0A6836),
                        ),
                        child: Text(tr(te: 'OTP పంపండి', en: 'Send OTP')),
                      ),
                    if (_register)
                      TextButton(
                        key: const ValueKey('cancel-onboarding'),
                        onPressed: _busy ? null : _leave,
                        child: Text(tr(te: 'రద్దు చేయండి', en: 'Cancel')),
                      ),
                    if (_busy) const LinearProgressIndicator(),
                    if (_error != null)
                      Text(
                        tr(te: _error!.te, en: _error!.en),
                        style: const TextStyle(color: Color(0xFFD9383A)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                tr(
                  te: 'కాల్ ట్యాప్‌లు నమోదు చేస్తాము. కాల్ ఆడియో రికార్డు చేయము.',
                  en: 'Call taps are logged; call audio is never recorded.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
