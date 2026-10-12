import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/supabase_config.dart';
import '../../core/utils/indian_phone_number.dart';
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
    this.sessionTimeout = const Duration(days: 7),
    SupabaseDriverRepository? driverRepository,
  }) : _client = client ?? SupabaseConfig.client,
       isMock = mockMode ?? (client == null && !SupabaseConfig.isConfigured),
       _now = now ?? DateTime.now,
       _injectedDrivers = driverRepository {
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
  final SupabaseDriverRepository? _injectedDrivers;
  late final _drivers =
      _injectedDrivers ?? SupabaseDriverRepository(client: _client);
  bool _guestMode = false;
  bool get isGuest => _guestMode;

  void endGuestMode() {
    _guestMode = false;
    notifyListeners();
  }

  Future<void> browseAsGuest() async {
    try {
      await signOut();
    } finally {
      _verifiedPhone = null;
      onboardingPhone = null;
      _currentProfile = null;
      _guestMode = true;
      notifyListeners();
    }
  }

  Future<LocalDriverProfile?> restoreDriverProfile({
    required LocalDriverRepository localRepository,
    UserProfile? identity,
  }) async {
    final owner = identity ?? currentProfile;
    if (owner == null || owner.role != 'driver') return null;
    final phone = normalizePhone(owner.phone);
    if (verifiedPhone == null || normalizePhone(verifiedPhone!) != phone) {
      return null;
    }
    final saved = await localRepository.getProfile();
    if (verifiedPhone == null || normalizePhone(verifiedPhone!) != phone) {
      throw StateError('Driver identity changed during restoration');
    }
    if (saved != null && normalizePhone(saved.phone) == phone) {
      if (saved.phone == phone) return saved;
      final normalized = LocalDriverProfile.fromDriverModel(
        saved.toDriverModel().copyWith(phone: phone),
      );
      await localRepository.saveProfile(normalized);
      return normalized;
    }
    if (isMock && _injectedDrivers == null) return null;
    final driver = await _drivers.getOwnDriver(phone);
    if (driver == null) return null;
    if (verifiedPhone == null || normalizePhone(verifiedPhone!) != phone) {
      throw StateError('Driver identity changed during restoration');
    }
    final restored = LocalDriverProfile.fromDriverModel(
      driver.copyWith(phone: phone),
    );
    await localRepository.saveProfile(restored);
    return restored;
  }

  Future<bool> resumeExistingDriver(UserProfile identity) async {
    final driver = await restoreDriverProfile(
      localRepository: LocalDriverRepository(),
      identity: identity,
    );
    if (driver == null) return false;
    await _cache(identity);
    currentProfile = identity;
    return true;
  }

  final bool isMock;
  final DateTime Function() _now;
  final Duration sessionTimeout;
  DateTime? _lastActiveWrite;
  UserProfile? _currentProfile;
  UserProfile? get currentProfile => _currentProfile;
  set currentProfile(UserProfile? value) {
    _currentProfile = value;
    if (value != null) _guestMode = false;
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
        : normalizePhone(raw);
  }

  DateTime? _sentAt;
  static const _sessionKey = 'auth_identity_v1';
  static const _rolesKey = 'auth_roles_v1';
  static const _onboardingKey = 'auth_onboarding_v1';
  static const activeWriteInterval = Duration(minutes: 15);

  Future<bool> _expireIfInactive(Map<String, dynamic> row) async {
    final rawTimestamp =
        row['last_active_timestamp'] as String? ?? row['saved_at'] as String?;
    final lastActive = rawTimestamp == null
        ? null
        : DateTime.tryParse(rawTimestamp)?.toUtc();
    if (lastActive == null ||
        _now().toUtc().difference(lastActive) <= sessionTimeout) {
      return false;
    }
    await signOut();
    return true;
  }

  /// Refreshes the persisted activity clock without writing on every tap.
  Future<void> recordActivity() async {
    final now = _now().toUtc();
    if (_lastActiveWrite != null &&
        now.difference(_lastActiveWrite!) < activeWriteInterval) {
      return;
    }
    _lastActiveWrite = now;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_sessionKey);
      if (raw == null) return;
      final row = jsonDecode(raw) as Map<String, dynamic>;
      if (await _expireIfInactive(row)) return;
      row['last_active_timestamp'] = now.toIso8601String();
      await prefs.setString(_sessionKey, jsonEncode(row));
    } catch (_) {
      /* Storage failure must not interrupt normal app use. */
    }
  }

  /// Checks inactivity before a resumed session is allowed to stay open.
  Future<bool> onAppResumed() async {
    if (currentProfile == null) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_sessionKey);
      if (raw == null) return false;
      final row = jsonDecode(raw) as Map<String, dynamic>;
      if (await _expireIfInactive(row)) return true;
      final now = _now().toUtc();
      row['last_active_timestamp'] = now.toIso8601String();
      await prefs.setString(_sessionKey, jsonEncode(row));
      _lastActiveWrite = now;
    } catch (_) {
      /* Retain the active identity if the local clock cannot be read. */
    }
    return false;
  }

  static String normalizePhone(String phone) => IndianPhoneNumber.normalize(phone);

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
        : await _verifiedIdentity(normalized);
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

  /// Recover pre-onboarding accounts from an owned, usable driver row.
  /// Existing authoritative roles always take precedence over directory data.
  Future<UserProfile?> _verifiedIdentity(String phone) async {
    final identity = await _remoteProfile(phone);
    if (identity != null) return identity;
    final driver = await _drivers.getOwnDriver(phone);
    if (driver == null) return null;
    final profile = await createUserProfile(
      phone: phone,
      name: driver.name,
      role: 'driver',
      villageId: driver.village.id,
      publishSession: false,
    );
    if (profile.role == 'driver') {
      await LocalDriverRepository().saveProfile(
        LocalDriverProfile.fromDriverModel(driver.copyWith(phone: phone)),
      );
    }
    return profile;
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
    Uint8List? avatarBytes,
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
      if (await resumeExistingDriver(profile)) return profile;
      final driverRepository = SupabaseDriverRepository(client: _client);
      if (avatarBytes != null && !isMock) {
        final avatarUrl = await driverRepository.uploadDriverAvatar(
          driverId: driver.id,
          jpegBytes: avatarBytes,
        );
        driver = driver.copyWith(avatarUrl: avatarUrl);
      }
      await LocalDriverRepository().saveProfile(driver);
      if (!isMock) {
        await driverRepository.upsertDriver(driver.toDriverModel());
      }
    }
    await _cache(profile);
    currentProfile = profile;
    return profile;
  }

  Future<void> _cache(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    final activeTimestamp = _now().toUtc().toIso8601String();
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
            'saved_at': activeTimestamp,
            'last_active_timestamp': activeTimestamp,
          }),
        )) {
      throw StateError('Could not save sign-in');
    }
    _lastActiveWrite = _now().toUtc();
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
          final normalized = normalizePhone(phone);
          final profile = await _verifiedIdentity(normalized);
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
      if (await _expireIfInactive(row)) return null;
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
          final remote = await _verifiedIdentity(profile.phone);
          if (remote == null) {
            await _markOnboarding(profile.phone);
            return null;
          }
          profile = remote;
          await _cache(profile);
        } catch (_) {
          /* Cached role only restores offline UI. */
        }
      } else {
        final activeTimestamp = _now().toUtc().toIso8601String();
        row['last_active_timestamp'] = activeTimestamp;
        await prefs.setString(_sessionKey, jsonEncode(row));
        _lastActiveWrite = _now().toUtc();
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
      final phone = normalizePhone(raw);
      return (await _remoteProfile(phone))?.role == 'admin';
    } catch (_) {
      return false;
    }
  }

  Future<void> signOut() async {
    onboardingPhone = null;
    _verifiedPhone = null;
    currentProfile = null;
    _pendingPhone = null;
    _lastActiveWrite = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_sessionKey);
      await prefs.remove(_onboardingKey);
    } finally {
      if (!isMock && _client != null) {
        await _client.auth.signOut(scope: SignOutScope.local)
            .timeout(const Duration(seconds: 8));
      }
    }
  }
}
