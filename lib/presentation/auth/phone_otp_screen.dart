import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/villages.dart';
import '../../data/models/local_driver_profile.dart';
import '../../data/models/user_profile_model.dart';
import '../../data/models/vehicle_type.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/local_driver_repository.dart';
import '../common/mandal_village_picker.dart';
import '../driver/driver_dashboard_screen.dart';
import '../farmer/home_directory_screen.dart';
import 'role_destination.dart';

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
  final _name = TextEditingController();
  final _number = TextEditingController();
  final _capacity = TextEditingController();
  final _form = GlobalKey<FormState>();
  final _driverId = const Uuid().v4();
  String _role = 'shipper';
  String? _villageId;
  String? _verifiedPhone;
  VehicleType _vehicle = VehicleType.boleroPickup;
  bool _register = false;
  bool _sent = false;
  bool _busy = false;
  int _seconds = 0;
  Timer? _timer;
  String? _error;

  @override
  void initState() {
    super.initState();
    final pending = _auth.onboardingPhone;
    if (pending != null) {
      _register = true;
      _phone.text = pending.substring(3);
      _verifiedPhone = pending;
    }
  }

  Future<void> _send() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    if (_register && _verifiedPhone != null) {
      await _completeRegistration();
      return;
    }
    if (_seconds > 0) return;
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
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
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
        'SMS పంపడం విఫలమైంది. దయచేసి సరైన నెంబర్ సరిచూడండి లేదా టెస్ట్ నెంబర్ వాడండి.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _error = message);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _completeRegistration() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final navigator = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);
      LocalDriverProfile? driver;
      if (_role == 'driver') {
        final village = KolleruVillages.find(_villageId)!;
        driver = LocalDriverProfile(
          id: _driverId,
          name: _name.text.trim(),
          phone: _verifiedPhone!,
          baseVillage: village,
          currentSpotVillage: village,
          vehicleType: _vehicle,
          capacityTons: double.parse(_capacity.text),
          specializations: const [],
          vehicleNumber: _number.text.trim().toUpperCase(),
          isAvailable: true,
        );
      }
      final profile = await _auth.completeRegistration(
        phone: _verifiedPhone!,
        name: _name.text,
        role: _role,
        villageId: _villageId!,
        driver: driver,
      );
      if (!mounted) return;
      _timer?.cancel();
      navigator.pushAndRemoveUntil<void>(
        MaterialPageRoute(
          builder: (_) => profile.role == 'driver' && driver != null
              ? DriverDashboardScreen(
                  profile: driver,
                  repository: LocalDriverRepository(),
                  authRepository: _auth,
                )
              : profile.role == 'shipper'
              ? HomeDirectoryScreen(authRepository: _auth)
              : RoleDestination(profile: profile, authRepository: _auth),
        ),
        (_) => false,
      );
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('నమోదు విజయవంతమైంది! / Registration Successful!'),
          ),
        );
      widget.onVerified(profile);
    } catch (_) {
      _showError(
        'నమోదు సేవ్ కాలేదు. మళ్లీ ప్రయత్నించండి / Could not save registration. Please retry.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_busy) return;
    if (_verifiedPhone != null && _register) {
      await _completeRegistration();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final profile = await _auth.verifyOTP(
        phone: _phone.text,
        token: _otp.text,
        publishSession: !_register,
      );
      if (!mounted) return;
      if (_register) {
        _verifiedPhone = AuthRepository.normalizePhone(_phone.text);
        await _completeRegistration();
      } else if (profile != null) {
        widget.onVerified(profile);
      } else {
        _verifiedPhone = AuthRepository.normalizePhone(_phone.text);
        setState(() {
          _register = true;
          _sent = false;
          _otp.clear();
        });
        _showError(
          'ఖాతా కనుగొనబడలేదు. దయచేసి నమోదు చేసుకోండి (Account not found. Please register)',
        );
      }
    } catch (_) {
      _showError('OTP సరికాదు / Verification failed. Check code or resend.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final controller in [_phone, _otp, _name, _number, _capacity]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('కొల్లేరు వీల్స్ / Kolleru Wheels')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('లాగిన్ (Login)', key: ValueKey('login-tab')),
              ),
              ButtonSegment(
                value: true,
                label: Text(
                  'కొత్త నమోదు (Register)',
                  key: ValueKey('register-tab'),
                ),
              ),
            ],
            selected: {_register},
            onSelectionChanged: _busy || _sent
                ? null
                : (values) => setState(() {
                    _register = values.single;
                    _error = null;
                  }),
          ),
          const SizedBox(height: 20),
          if (_auth.isMock)
            const Text('డెమో / Demo sign-in: use OTP 123456. No SMS is sent.'),
          Form(
            key: _form,
            child: Column(
              children: [
                if (_register)
                  TextFormField(
                    key: const ValueKey('auth-name'),
                    controller: _name,
                    enabled: !_sent && !_busy,
                    decoration: const InputDecoration(
                      labelText: 'పూర్తి పేరు / Full Name',
                    ),
                    validator: (value) =>
                        (value ?? '').trim().length < 2 ||
                            (value ?? '').trim().length > 80
                        ? 'పేరు ఇవ్వండి / Enter a name (2–80 characters)'
                        : null,
                  ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('auth-phone'),
                  controller: _phone,
                  enabled: !_sent && !_busy,
                  readOnly: _verifiedPhone != null,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    TextInputFormatter.withFunction((oldValue, newValue) {
                      var digits = newValue.text.replaceAll(
                        RegExp(r'[^0-9]'),
                        '',
                      );
                      if (digits.length == 12 && digits.startsWith('91')) {
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
                  decoration: const InputDecoration(
                    prefixText: '+91 ',
                    labelText: 'ఫోన్ నంబర్ / Phone number',
                  ),
                  validator: (value) {
                    try {
                      AuthRepository.normalizePhone(value ?? '');
                      return null;
                    } on FormatException {
                      return 'సరైన 10 అంకెల మొబైల్ నెంబర్ ఇవ్వండి / Enter a valid 10-digit Indian mobile number';
                    }
                  },
                ),
                if (_register)
                  AbsorbPointer(
                    absorbing: _sent || _busy,
                    child: Column(
                      children: [
                        const SizedBox(height: 16),
                        const Text('పాత్ర ఎంపిక / Select Role'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              key: const ValueKey('auth-shipper'),
                              label: const Text(
                                'రైతు / వ్యాపారి (Farmer / Shipper)',
                              ),
                              selected: _role == 'shipper',
                              onSelected: (_) =>
                                  setState(() => _role = 'shipper'),
                            ),
                            ChoiceChip(
                              key: const ValueKey('auth-driver'),
                              label: const Text(
                                'డ్రైవర్ / వాహనదారుడు (Driver / Vehicle Owner)',
                              ),
                              selected: _role == 'driver',
                              onSelected: (_) =>
                                  setState(() => _role = 'driver'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        MandalVillagePicker(
                          onChanged: (id) => setState(() => _villageId = id),
                        ),
                        if (_role == 'driver') ...[
                          const SizedBox(height: 16),
                          DropdownButtonFormField<VehicleType>(
                            key: const ValueKey('auth-vehicle'),
                            initialValue: _vehicle,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'వాహనం / Vehicle Type',
                            ),
                            items: [
                              for (final type in VehicleType.values)
                                DropdownMenuItem(
                                  value: type,
                                  child: Text(type.label),
                                ),
                            ],
                            onChanged: (type) =>
                                setState(() => _vehicle = type!),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            key: const ValueKey('auth-number'),
                            controller: _number,
                            decoration: const InputDecoration(
                              labelText: 'వాహనం నెంబర్ / Registration Number',
                            ),
                            validator: (value) => (value ?? '').trim().isEmpty
                                ? 'వాహనం నెంబర్ ఇవ్వండి / Enter registration number'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            key: const ValueKey('auth-capacity'),
                            controller: _capacity,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'సామర్థ్యం / Capacity (Tons)',
                            ),
                            validator: (value) {
                              final tons = double.tryParse(value ?? '');
                              return tons == null ||
                                      !tons.isFinite ||
                                      tons <= 0 ||
                                      tons > 100
                                  ? 'సరైన టన్నులు ఇవ్వండి / Enter capacity (0–100 tons)'
                                  : null;
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (_sent) ...[
            Text('OTP పంపబడింది / Code sent to +91${_phone.text}'),
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
            FilledButton(
              key: const ValueKey('verify-otp'),
              onPressed: _busy ? null : _verify,
              child: Text(
                _verifiedPhone != null
                    ? 'మళ్లీ ప్రయత్నించండి / Retry Registration'
                    : 'నిర్ధారించండి / Verify OTP',
              ),
            ),
            TextButton(
              onPressed: _busy || _seconds > 0 || _verifiedPhone != null
                  ? null
                  : _send,
              child: Text(
                _seconds > 0
                    ? 'మళ్లీ పంపండి / Resend in ${_seconds}s'
                    : 'మళ్లీ పంపండి / Resend OTP',
              ),
            ),
          ] else
            FilledButton(
              key: const ValueKey('send-otp'),
              onPressed: _busy ? null : _send,
              child: Text(
                !_register
                    ? 'OTP పంపండి (Send OTP)'
                    : _verifiedPhone != null
                    ? 'నమోదు పూర్తి చేయండి / Complete Registration'
                    : 'నమోదు పూర్తి చేయండి / Register & Send OTP',
              ),
            ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Color(0xFFD9383A))),
          const SizedBox(height: 20),
          const Text(
            'కాల్ ట్యాప్‌లు నమోదు చేస్తాము; కాల్ ఆడియో రికార్డు చేయము. / Call taps are logged; call audio is never recorded.',
          ),
        ],
      ),
    ),
  );
}
