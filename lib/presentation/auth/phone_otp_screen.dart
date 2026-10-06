import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/user_profile_model.dart';
import '../../data/repositories/auth_repository.dart';

class PhoneOtpScreen extends StatefulWidget {
  const PhoneOtpScreen({super.key, this.repository, required this.onVerified});
  final AuthRepository? repository;
  final void Function(UserProfile) onVerified;
  @override
  State<PhoneOtpScreen> createState() => _PhoneOtpScreenState();
}

class _PhoneOtpScreenState extends State<PhoneOtpScreen> {
  late final _auth = widget.repository ?? AuthRepository.instance;
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  String _role = 'shipper';
  bool _sent = false;
  bool _busy = false;
  int _seconds = 0;
  DateTime? _resendAt;
  Timer? _timer;
  String? _error;

  Future<void> _send() async {
    if (_busy || _seconds > 0) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.signInWithOtp(phone: _phone.text, role: _role);
      if (!mounted) return;
      setState(() {
        _sent = true;
        _seconds = 60;
      });
      _resendAt = DateTime.now().add(const Duration(seconds: 60));
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        setState(
          () => _seconds =
              (_resendAt!.difference(DateTime.now()).inMilliseconds / 1000)
                  .ceil()
                  .clamp(0, 60),
        );
        if (_seconds == 0) timer.cancel();
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'OTP పంపలేకపోయాము / Check mobile number and connection, then retry.',
        );
      }
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
      if (mounted) widget.onVerified(profile);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'OTP సరికాదు / Verification failed. Check code or resend.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _otp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ఫోన్ లాగిన్ / Phone sign-in')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_auth.isMock)
            const Text('డెమో / Demo sign-in: use OTP 123456. No SMS is sent.'),
          TextField(
            key: const ValueKey('auth-phone'),
            controller: _phone,
            enabled: !_sent && !_busy,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            decoration: const InputDecoration(
              prefixText: '+91 ',
              labelText: 'ఫోన్ నెంబర్ / Mobile number',
            ),
          ),
          const SizedBox(height: 20),
          if (!_sent)
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ChoiceChip(
                  key: const ValueKey('auth-driver'),
                  label: const Text(
                    'డ్రైవర్ / వాహనదారుడు (Driver / Vehicle Owner)',
                  ),
                  selected: _role == 'driver',
                  onSelected: _busy
                      ? null
                      : (_) => setState(() => _role = 'driver'),
                ),
                ChoiceChip(
                  label: const Text('రైతు / వ్యాపారి (Farmer / Shipper)'),
                  selected: _role == 'shipper',
                  onSelected: _busy
                      ? null
                      : (_) => setState(() => _role = 'shipper'),
                ),
              ],
            ),
          if (_sent) ...[
            Text('OTP పంపబడింది / Code sent to +91${_phone.text}'),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('auth-otp'),
              controller: _otp,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: const InputDecoration(
                labelText: '6 అంకెల OTP / 6-digit OTP',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('verify-otp'),
              onPressed: _busy ? null : _verify,
              child: const Text('నిర్ధారించండి / Verify OTP'),
            ),
            TextButton(
              onPressed: _busy || _seconds > 0 ? null : _send,
              child: Text(
                _seconds > 0
                    ? 'మళ్ళీ పంపండి / Resend in ${_seconds}s'
                    : 'మళ్ళీ పంపండి / Resend OTP',
              ),
            ),
          ] else ...[
            const SizedBox(height: 24),
            FilledButton(
              key: const ValueKey('send-otp'),
              onPressed: _busy ? null : _send,
              child: const Text('OTP పంపండి / Send OTP'),
            ),
          ],
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Color(0xFFD9383A))),
          const SizedBox(height: 20),
          const Text(
            'కాల్స్ ఎవరికీ చేశారో నమోదు చేస్తాము. కాల్ ఆడియో రికార్డు చేయము. / Call taps are logged; call audio is never recorded.',
          ),
        ],
      ),
    ),
  );
}
