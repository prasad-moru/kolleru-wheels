import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/supabase_config.dart';
import '../models/user_profile_model.dart';
import '../models/local_driver_profile.dart';
import 'local_driver_repository.dart';
import 'supabase_driver_repository.dart';

/// Cached identity restores offline UX, never server authorization.
class AuthRepository extends ChangeNotifier {
  AuthRepository({
    SupabaseClient? client,
    bool? mockMode,
    DateTime Function()? now,
  }) : _client = client ?? SupabaseConfig.client,
       isMock = mockMode ?? (client == null && !SupabaseConfig.isConfigured),
       _now = now ?? DateTime.now {
    _authChanges = _client?.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedOut) {
        _verifiedPhone = null;
        onboardingPhone = null;
        currentProfile = null;
        unawaited(_clearIdentity());
      }
    });
  }
  StreamSubscription<AuthState>? _authChanges;
  Future<void> _clearIdentity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_sessionKey);
      await prefs.remove(_onboardingKey);
    } catch (_) {
      /* Memory identity is already cleared. */
    }
  }

  @override
  void dispose() {
    unawaited(_authChanges?.cancel());
    super.dispose();
  }

  static final instance = AuthRepository();
  final SupabaseClient? _client;
  final bool isMock;
  final DateTime Function() _now;
  UserProfile? _currentProfile;
  UserProfile? get currentProfile => _currentProfile;
  set currentProfile(UserProfile? value) {
    _currentProfile = value;
    notifyListeners();
  }

  String? _pendingPhone;
  String? _verifiedPhone;
  String? onboardingPhone;
  String? get verifiedPhone {
    if (isMock) return _verifiedPhone ?? currentProfile?.phone;
    final raw = _client?.auth.currentUser?.phone;
    return raw == null
        ? null
        : normalizePhone(raw.startsWith('+') ? raw : '+$raw');
  }

  DateTime? _sentAt;
  static const _sessionKey = 'auth_identity_v1';
  static const _rolesKey = 'auth_roles_v1';
  static const _onboardingKey = 'auth_onboarding_v1';

  static String normalizePhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\s'), '');
    final value = digits.startsWith('+91') ? digits.substring(3) : digits;
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(value)) {
      throw const FormatException('Enter a valid 10-digit mobile number');
    }
    return '+91$value';
  }

  Future<void> signInWithOtp({
    required String phone,
    required String role,
  }) async {
    if (!['driver', 'shipper'].contains(role)) {
      throw ArgumentError('Only public roles can be selected');
    }
    final normalized = normalizePhone(phone);
    if (_sentAt != null &&
        _now().difference(_sentAt!) < const Duration(seconds: 60)) {
      throw StateError('Please wait before resending');
    }
    if (!isMock) {
      if (_client == null) throw StateError('Sign-in temporarily unavailable');
      await _client.auth
          .signInWithOtp(phone: normalized, data: {'role': role})
          .timeout(const Duration(seconds: 15));
    }
    _pendingPhone = normalized;
    _verifiedPhone = null;
    _sentAt = _now();
  }

  Future<UserProfile?> verifyOTP({
    required String phone,
    required String token,
    bool publishSession = true,
  }) async {
    final normalized = normalizePhone(phone);
    if (_pendingPhone != normalized || !RegExp(r'^\d{6}$').hasMatch(token)) {
      throw const FormatException('Invalid OTP');
    }
    if (isMock) {
      if (token != '123456' ||
          _sentAt == null ||
          _now().difference(_sentAt!) >= const Duration(minutes: 5)) {
        throw const FormatException('Incorrect or expired demo OTP');
      }
    } else if (_verifiedPhone != normalized || verifiedPhone != normalized) {
      final response = await _client!.auth
          .verifyOTP(phone: normalized, token: token, type: OtpType.sms)
          .timeout(const Duration(seconds: 15));
      if (response.session == null ||
          response.user?.phone?.replaceFirst(RegExp(r'^\+'), '') !=
              normalized.substring(1)) {
        throw StateError('Phone verification failed');
      }
    }
    _verifiedPhone = normalized;
    final profile = isMock
        ? await _cachedProfile(normalized)
        : await _remoteProfile(normalized);
    if (profile == null) {
      await _markOnboarding(normalized);
    } else if (publishSession) {
      await _cache(profile);
    }
    if (publishSession || profile == null) currentProfile = profile;
    _pendingPhone = null;
    return profile;
  }

  Future<UserProfile?> _remoteProfile(String phone) async {
    final row = await _client!
        .from('user_profiles')
        .select('phone,role,name,village_id')
        .eq('phone', phone)
        .maybeSingle()
        .timeout(const Duration(seconds: 8));
    return row == null ? null : UserProfile.fromJson(row);
  }

  Future<UserProfile?> _cachedProfile(String phone) async {
    final prefs = await SharedPreferences.getInstance();
    final roles = jsonDecode(prefs.getString(_rolesKey) ?? '{}') as Map;
    final row = roles[phone];
    return row == null
        ? null
        : UserProfile.fromJson(Map<String, dynamic>.from(row as Map));
  }

  Future<void> _markOnboarding(String phone) async {
    onboardingPhone = phone;
    currentProfile = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
    await prefs.setString(
      _onboardingKey,
      jsonEncode({'phone': phone, 'mock': isMock}),
    );
  }

  Future<UserProfile> createUserProfile({
    required String phone,
    required String name,
    required String role,
    String? villageId,
    bool publishSession = true,
  }) async {
    final normalized = normalizePhone(phone);
    if (verifiedPhone != normalized) {
      throw StateError('Verify this phone first');
    }
    if (!['driver', 'shipper'].contains(role)) {
      throw ArgumentError('Invalid public role');
    }
    if (name.trim().length < 2 || name.trim().length > 80) {
      throw const FormatException('Enter your name');
    }
    var profile = isMock
        ? await _cachedProfile(normalized)
        : await _remoteProfile(normalized);
    if (profile == null) {
      profile = UserProfile(
        phone: normalized,
        name: name.trim(),
        role: role,
        villageId: villageId,
      );
      if (!isMock) {
        final row = await _client!
            .from('user_profiles')
            .upsert(
              {...profile.toJson(), 'user_id': _client.auth.currentUser!.id},
              onConflict: 'phone',
              ignoreDuplicates: true,
            )
            .select('phone,role,name,village_id')
            .maybeSingle()
            .timeout(const Duration(seconds: 8));
        // A concurrent registration must not overwrite an authoritative role.
        profile = row == null
            ? await _remoteProfile(normalized)
            : UserProfile.fromJson(row);
        if (profile == null) throw StateError('Profile save was not confirmed');
      }
    }
    if (publishSession) {
      await _cache(profile);
      currentProfile = profile;
    }
    return profile;
  }

  /// Publish the logged-in identity only after all registration data is saved.
  /// Remote driver writes use the durable offline outbox; no partial identity
  /// notification can send the router into a second vehicle form.
  Future<UserProfile> completeRegistration({
    required String phone,
    required String name,
    required String role,
    required String villageId,
    LocalDriverProfile? driver,
  }) async {
    final normalized = normalizePhone(phone);
    if (verifiedPhone != normalized ||
        (role == 'driver' && driver == null) ||
        (driver != null && (role != 'driver' || driver.phone != normalized))) {
      throw StateError('Verified registration details are required');
    }
    final profile = await createUserProfile(
      phone: normalized,
      name: name,
      role: role,
      villageId: villageId,
      publishSession: false,
    );
    if (profile.role == 'driver' && driver != null) {
      await LocalDriverRepository().saveProfile(driver);
      if (!isMock) {
        await SupabaseDriverRepository.instance.upsertDriver(
          driver.toDriverModel(),
        );
      }
    }
    await _cache(profile);
    currentProfile = profile;
    return profile;
  }

  Future<void> _cache(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_rolesKey);
    final roles = raw == null
        ? <String, dynamic>{}
        : jsonDecode(raw) as Map<String, dynamic>;
    roles[profile.phone] = profile.toJson();
    if (!await prefs.setString(_rolesKey, jsonEncode(roles)) ||
        !await prefs.setString(
          _sessionKey,
          jsonEncode({
            ...profile.toJson(),
            'mock': isMock,
            'user_id': isMock ? null : _client?.auth.currentUser?.id,
            'saved_at': _now().toUtc().toIso8601String(),
          }),
        )) {
      throw StateError('Could not save sign-in');
    }
    await prefs.remove(_onboardingKey);
    onboardingPhone = null;
  }

  Future<UserProfile?> restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_sessionKey);
      if (raw == null) {
        if (isMock) {
          final pending = prefs.getString(_onboardingKey);
          if (pending != null) {
            final row = jsonDecode(pending) as Map;
            if (row['mock'] == true) {
              _verifiedPhone = normalizePhone(row['phone'] as String);
              onboardingPhone = _verifiedPhone;
            }
          }
        }
        final phone = _client?.auth.currentUser?.phone;
        if (!isMock && phone != null) {
          final normalized = normalizePhone(
            phone.startsWith('+') ? phone : '+$phone',
          );
          final profile = await _remoteProfile(normalized);
          if (profile == null) {
            await _markOnboarding(normalized);
          } else {
            await _cache(profile);
          }
          return currentProfile = profile;
        }
        return currentProfile = null;
      }
      final row = jsonDecode(raw) as Map<String, dynamic>;
      if (row['mock'] != isMock) return currentProfile = null;
      if (!isMock &&
          (_client?.auth.currentUser == null ||
              _client!.auth.currentUser!.id != row['user_id'])) {
        return currentProfile = null;
      }
      var profile = UserProfile.fromJson(row);
      if (!isMock &&
          _client!.auth.currentUser!.phone?.replaceFirst(RegExp(r'^\+'), '') !=
              profile.phone.substring(1)) {
        return currentProfile = null;
      }
      if (!isMock) {
        try {
          final remote = await _remoteProfile(profile.phone);
          if (remote == null) {
            await _markOnboarding(profile.phone);
            return null;
          }
          profile = remote;
          await _cache(profile);
        } catch (_) {
          /* Cached role only restores offline UI. */
        }
      }
      return currentProfile = profile;
    } catch (_) {
      return currentProfile = null;
    }
  }

  Future<String?> getRole(String phone) async {
    final normalized = normalizePhone(phone);
    if (!isMock && _client != null) {
      try {
        final profile = await _remoteProfile(normalized);
        if (profile == null) return null;
        if (currentProfile?.phone == normalized) {
          await _cache(profile);
          currentProfile = profile;
        }
        return profile.role;
      } catch (_) {
        /* Offline cache below. */
      }
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final roles = jsonDecode(prefs.getString(_rolesKey) ?? '{}') as Map;
      final row = roles[normalized];
      return row == null
          ? null
          : UserProfile.fromJson(Map<String, dynamic>.from(row as Map)).role;
    } catch (_) {
      return null;
    }
  }

  Future<bool> isLiveAdmin() async {
    if (isMock || _client?.auth.currentUser == null) return false;
    try {
      final raw = _client!.auth.currentUser!.phone;
      if (raw == null) return false;
      final phone = normalizePhone(raw.startsWith('+') ? raw : '+$raw');
      return (await _remoteProfile(phone))?.role == 'admin';
    } catch (_) {
      return false;
    }
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
    await prefs.remove(_onboardingKey);
    onboardingPhone = null;
    _verifiedPhone = null;
    currentProfile = null;
    _pendingPhone = null;
    if (!isMock && _client != null) {
      await _client.auth.signOut(scope: SignOutScope.local);
    }
  }
}
