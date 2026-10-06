import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/supabase_config.dart';
import '../models/user_profile_model.dart';

/// Cached identity restores offline UX, never server authorization.
class AuthRepository {
  AuthRepository({
    SupabaseClient? client,
    bool? mockMode,
    DateTime Function()? now,
  }) : _client = client ?? SupabaseConfig.client,
       isMock = mockMode ?? (client == null && !SupabaseConfig.isConfigured),
       _now = now ?? DateTime.now;
  static final instance = AuthRepository();
  final SupabaseClient? _client;
  final bool isMock;
  final DateTime Function() _now;
  UserProfile? currentProfile;
  String? _pendingPhone;
  String _pendingRole = 'shipper';
  DateTime? _sentAt;
  static const _sessionKey = 'auth_identity_v1';
  static const _rolesKey = 'auth_roles_v1';

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
    _pendingRole = role;
    _sentAt = _now();
  }

  Future<UserProfile> verifyOTP({
    required String phone,
    required String token,
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
    } else {
      final response = await _client!.auth
          .verifyOTP(phone: normalized, token: token, type: OtpType.sms)
          .timeout(const Duration(seconds: 15));
      if (response.session == null ||
          response.user?.phone?.replaceFirst(RegExp(r'^\+'), '') !=
              normalized.substring(1)) {
        throw StateError('Phone verification failed');
      }
    }
    final profile = isMock
        ? UserProfile(phone: normalized, role: _pendingRole)
        : await _remoteProfile(normalized);
    await _cache(profile);
    currentProfile = profile;
    _pendingPhone = null;
    return profile;
  }

  Future<UserProfile> _remoteProfile(String phone) async {
    final row = await _client!
        .from('user_profiles')
        .select('phone,role,name')
        .eq('phone', phone)
        .single()
        .timeout(const Duration(seconds: 8));
    return UserProfile.fromJson(row);
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
  }

  Future<UserProfile?> restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_sessionKey);
      if (raw == null) {
        final phone = _client?.auth.currentUser?.phone;
        if (!isMock && phone != null) {
          final normalized = normalizePhone(
            phone.startsWith('+') ? phone : '+$phone',
          );
          final profile = await _remoteProfile(normalized);
          await _cache(profile);
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
          profile = await _remoteProfile(profile.phone);
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
      return (await _remoteProfile(phone)).role == 'admin';
    } catch (_) {
      return false;
    }
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
    currentProfile = null;
    _pendingPhone = null;
    if (!isMock && _client != null) {
      await _client.auth.signOut(scope: SignOutScope.local);
    }
  }
}
