
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/villages.dart';
import '../../core/constants/app_strings.dart';
import '../../data/models/local_driver_profile.dart';
import '../../data/models/user_profile_model.dart';
import '../../data/models/vehicle_type.dart';
import '../../data/repositories/auth_repository.dart';
import '../common/mandal_village_picker.dart';
import '../common/driver_avatar_picker.dart';
import 'onboarding_navigation.dart';
import 'session_router.dart';

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
  Uint8List? _avatarBytes;
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
    if (_busy || (!_sent && !_form.currentState!.validate())) return;
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
          isPhoneVerified: true,
        );
      }
      final profile = await _auth.completeRegistration(
        phone: _verifiedPhone!,
        name: _name.text,
        role: _role,
        villageId: _villageId!,
        driver: driver,
        avatarBytes: _avatarBytes,
      );
      if (!mounted) return;
      _timer?.cancel();
      navigator.pushAndRemoveUntil<void>(
        MaterialPageRoute(
          builder: (_) => SessionRouter(repository: _auth),
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
      }
      if (_register && profile != null && profile.role == 'driver' &&
          await _auth.resumeExistingDriver(profile)) {
        if (!mounted) return;
        _timer?.cancel();
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => SessionRouter(repository: _auth)),
          (_) => false,
        );
        widget.onVerified(profile);
      } else if (_register) {
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

  Future<void> _leave() async {
    if (_busy) return;
    _timer?.cancel();
    await leaveOnboarding(context, _auth);
  }

  Widget _hero(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFDCFCE7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.local_shipping_outlined, size: 30, color: Color(0xFF0F5132)),
      ),
      const SizedBox(height: 14),
      Text('కొల్లేరు వీల్స్ / Kolleru Wheels',
        key: const ValueKey('login-hero'),
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          color: const Color(0xFF0F5132), fontWeight: FontWeight.w600,
        )),
      const SizedBox(height: 8),
      const Text(AppStrings.loginSubtitle),
      const SizedBox(height: 24),
    ],
  );

  @override
  void dispose() {
    _timer?.cancel();
    for (final controller in [_phone, _otp, _name, _number, _capacity]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => OnboardingBackScope(
    enabled: !_busy,
    onExit: _leave,
    child: Scaffold(
      appBar: AppBar(
        title: Text(_register ? 'నమోదు / Register' : AppStrings.signIn),
        leading: IconButton(
          key: const ValueKey('onboarding-back'),
          tooltip: AppStrings.cancelRegistration,
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
            foregroundColor: const Color(0xFF0F5132),
            side: const BorderSide(color: Color(0xFFA7F3D0)),
          ),
          icon: const Icon(Icons.agriculture_outlined),
          label: const Text(AppStrings.browseGuest, textAlign: TextAlign.center),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (!_sent) _hero(context),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
                boxShadow: [BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10, offset: const Offset(0, 4),
                )],
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
                          selectedColor: const Color(0xFF0F5132),
                          showCheckmark: false,
                          labelStyle: TextStyle(
                            color: _register == register ? Colors.white : const Color(0xFF475569),
                          ),
                          label: Text(
                            register ? 'కొత్త నమోదు (Register)' : 'లాగిన్ (Login)',
                            key: ValueKey(register ? 'register-tab' : 'login-tab'),
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
                    const Text('డెమో / Demo sign-in: use OTP 123456. No SMS is sent.'),
                  if (!_sent) Form(
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
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
                          autofillHints: const [AutofillHints.telephoneNumberNational],
                          decoration: InputDecoration(
                            prefixIconConstraints: const BoxConstraints(minWidth: 74),
                            prefixIcon: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFECFDF5),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text('+91', style: TextStyle(
                                  color: Color(0xFF0F5132), fontWeight: FontWeight.w600,
                                )),
                              ),
                            ),
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
                                  const SizedBox(height: 20),
                                  Center(
                                    child: DriverAvatarPicker(
                                      name: _name.text,
                                      initialBytes: _avatarBytes,
                                      onPhotoSelected: (bytes) =>
                                          setState(() => _avatarBytes = bytes),
                                    ),
                                  ),
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
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F5132)),
                      onPressed: _busy ? null : _verify,
                      child: Text(
                        _verifiedPhone != null
                            ? 'మళ్లీ ప్రయత్నించండి / Retry Registration'
                            : 'లాగిన్ / Verify OTP',
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
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F5132)),
                      onPressed: _busy ? null : _send,
                      child: Text(
                        !_register
                            ? 'OTP పంపండి / Send OTP'
                            : _verifiedPhone != null
                            ? 'నమోదు పూర్తి చేయండి / Complete Registration'
                            : 'నమోదు పూర్తి చేయండి / Register & Send OTP',
                      ),
                    ),
                  if (_register) ...[
                    const SizedBox(height: 12),
                    TextButton(
                      key: const ValueKey('cancel-onboarding'),
                      onPressed: _busy ? null : _leave,
                      child: const Text(AppStrings.cancelRegistration, textAlign: TextAlign.center),
                    ),
                  ],
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: Color(0xFFD9383A))),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'కాల్ ట్యాప్‌లు నమోదు చేస్తాము; కాల్ ఆడియో రికార్డు చేయము. / Call taps are logged; call audio is never recorded.',
            ),
          ],
        ),
      ),
    ),
  );
}
