import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/localization/app_language_provider.dart';
import '../../../data/repositories/auth_repository.dart';

/// Inline phone verification, opened only when a guest requests a contact.
class ConnectGate extends StatefulWidget {
  const ConnectGate({super.key, required this.auth});
  final AuthRepository auth;
  @override
  State<ConnectGate> createState() => _ConnectGateState();
}

class _ConnectGateState extends LanguageAwareState<ConnectGate> {
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _sent = false;
  bool _busy = false;
  bool _failed = false;
  bool _validated = false;

  @override
  void onLanguageChanged() {
    if (_validated) _form.currentState?.validate();
  }

  Future<void> _submit() async {
    _validated = true;
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      if (!_sent) {
        await widget.auth.signInWithOtp(phone: _phone.text, role: 'shipper');
        if (mounted) setState(() => _sent = true);
      } else {
        final profile = await widget.auth.verifyOTP(
          phone: _phone.text,
          token: _otp.text,
        );
        if (mounted) Navigator.of(context).pop(profile != null);
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _phone.dispose();
    _otp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _form,
        child: Column(
          key: const ValueKey('connect-gate'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    tr(
                      te: 'డ్రైవర్‌ను సంప్రదించండి',
                      en: 'Connect with the driver',
                    ),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0A6836),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: tr(te: 'మూసివేయండి', en: 'Close'),
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              tr(
                te: 'సంప్రదించడానికి మీ ఫోన్ నంబర్ ధృవీకరించండి.',
                en: 'Verify your phone number to contact drivers.',
              ),
            ),
            const SizedBox(height: 16),
            if (!_sent)
              TextFormField(
                key: const ValueKey('connect-phone'),
                controller: _phone,
                enabled: !_busy,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumberNational],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                decoration: InputDecoration(
                  prefixText: '+91 ',
                  labelText: tr(te: 'మొబైల్ నంబర్', en: 'Mobile number'),
                ),
                validator: (value) {
                  try {
                    AuthRepository.normalizePhone(value ?? '');
                    return null;
                  } on FormatException {
                    return tr(
                      te: 'సరైన 10 అంకెల నంబర్ ఇవ్వండి',
                      en: 'Enter a valid 10-digit mobile number',
                    );
                  }
                },
              )
            else
              TextFormField(
                key: const ValueKey('connect-otp'),
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
                validator: (value) => (value ?? '').length == 6
                    ? null
                    : tr(
                        te: '6 అంకెల కోడ్ ఇవ్వండి',
                        en: 'Enter the 6-digit code',
                      ),
              ),
            if (widget.auth.isMock)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  tr(te: 'నమూనా కోడ్: 123456', en: 'Demo code: 123456'),
                ),
              ),
            if (_failed)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  tr(
                    te: 'ధృవీకరణ విఫలమైంది. మళ్లీ ప్రయత్నించండి.',
                    en: 'Verification failed. Please try again.',
                  ),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('connect-submit'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0A6836),
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: _busy ? null : _submit,
              child: Text(
                _sent
                    ? tr(te: 'ధృవీకరించండి', en: 'Verify OTP')
                    : tr(te: 'OTP పొందండి', en: 'Get OTP'),
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
          ],
        ),
      ),
    ),
  );
}
