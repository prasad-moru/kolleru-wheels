import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/villages.dart';
import '../models/local_driver_profile.dart';

class LocalDriverRepository {
  static const profileKey = 'registered_driver_profile_v1';
  // Serialize read-modify-write operations across repository instances so a
  // location update cannot overwrite an availability update made concurrently.
  static Future<void>? _pending;

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final previous = _pending;
    final result = previous == null
        ? Future<T>.sync(operation)
        : previous.then((_) => operation());
    late final Future<void> tail;
    void clear() {
      if (identical(_pending, tail)) _pending = null;
    }

    tail = result.then<void>(
      (_) => clear(),
      onError: (Object error, StackTrace stack) => clear(),
    );
    _pending = tail;
    return result;
  }

  Future<LocalDriverProfile?> getProfile() async {
    final pending = _pending;
    if (pending != null) await pending;
    return _readProfile();
  }

  Future<LocalDriverProfile?> _readProfile() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(profileKey);
    if (encoded == null) return null;
    // Invalid data is surfaced to the caller, never treated as a missing driver
    // or silently replaced with a new registration.
    return LocalDriverProfile.fromJson(
      jsonDecode(encoded) as Map<String, dynamic>,
    );
  }

  Future<void> saveProfile(LocalDriverProfile profile) =>
      _enqueue(() => _writeProfile(profile));

  Future<void> _writeProfile(LocalDriverProfile profile) async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setString(
      profileKey,
      jsonEncode(profile.toJson()),
    )) {
      throw StateError('Driver profile could not be saved');
    }
  }

  Future<void> updateProfile(LocalDriverProfile profile) => _enqueue(() async {
    final existing = await _readProfile();
    if (existing == null || existing.id != profile.id) {
      throw StateError('Registered driver profile not found');
    }
    await _writeProfile(profile);
  });

  Future<LocalDriverProfile> updateAvailability(bool isAvailable) =>
      _enqueue(() async {
        final profile = await _requireProfile();
        final updated = profile.copyWith(isAvailable: isAvailable);
        await _writeProfile(updated);
        return updated;
      });

  Future<LocalDriverProfile> updateCurrentSpot(
    Village village, {
    String? label,
  }) => _enqueue(() async {
    final profile = await _requireProfile();
    final updated = profile.copyWith(
      currentSpotVillage: village,
      currentSpotLabel: label,
    );
    await _writeProfile(updated);
    return updated;
  });

  Future<LocalDriverProfile> _requireProfile() async {
    final profile = await _readProfile();
    if (profile == null) {
      throw StateError('Registered driver profile not found');
    }
    return profile;
  }
}
