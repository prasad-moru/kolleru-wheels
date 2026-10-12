import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/supabase_config.dart';
import '../../core/constants/villages.dart';
import '../../core/utils/indian_phone_number.dart';
import '../models/driver_model.dart';
import '../models/vehicle_type.dart';
import 'local_driver_repository.dart';
import 'offline_table_store.dart';

class SupabaseDriverRepository {
  SupabaseDriverRepository({SupabaseClient? client, DateTime Function()? now})
    : _client = client ?? SupabaseConfig.client,
      _now = now ?? DateTime.now;
  static final instance = SupabaseDriverRepository();
  final SupabaseClient? _client;
  final DateTime Function() _now;
  final _store = const OfflineTableStore('drivers');
  final _queue = RepositoryQueue();
  bool usingCache = false;
  bool syncPending = false;
  bool get isConfigured => _client != null;

  static Map<String, dynamic> toRow(DriverModel driver, DateTime now) {
    if (driver.isDemo) throw ArgumentError('Demo records cannot be published');
    var tons =
        driver.capacityTons ??
        double.tryParse(
          RegExp(r'[0-9]+(?:\.[0-9]+)?')
                  .firstMatch(driver.capacity)
                  ?.group(0) ??
              '',
        );
    if (driver.capacityTons == null &&
        tons != null &&
        (driver.capacity.toLowerCase().contains('kg') ||
            driver.capacity.contains('కిలో'))) {
      tons /= 1000;
    }
    if (tons == null || !tons.isFinite || tons <= 0 || tons > 100) {
      throw const FormatException('Invalid capacity in tons');
    }
    final spot = driver.currentSpotVillageId ?? driver.village.id;
    if (KolleruVillages.find(spot) == null) {
      throw const FormatException('Unknown current village');
    }
    return {
      'id': OfflineTableStore.cloudId('drivers', driver.id),
      'phone': driver.phone,
      'name': driver.name,
      'base_village_id': driver.village.id,
      'current_spot_village_id': spot,
      'vehicle_type': driver.vehicleType.name,
      'capacity_tons': tons,
      'vehicle_number': driver.vehicleNumber,
      'specializations': driver.specializations,
      'is_available': driver.isAvailable,
      'avatar_url': driver.avatarUrl,
      'card_style': driver.cardStyle,
      'updated_at': now.toUtc().toIso8601String(),
    };
  }

  static DriverModel fromRow(Map<String, dynamic> row) {
    final base = KolleruVillages.find(row['base_village_id'] as String?);
    final spot =
        KolleruVillages.find(row['current_spot_village_id'] as String?) ?? base;
    final tons = (row['capacity_tons'] as num).toDouble();
    if (base == null ||
        spot == null ||
        !tons.isFinite ||
        tons <= 0 ||
        tons > 100) {
      throw const FormatException('Invalid cloud driver');
    }
    return DriverModel(
      id: row['id'] as String,
      name: row['name'] as String,
      phone: row['phone'] as String,
      village: base,
      currentSpot: spot.label,
      currentSpotVillageId: spot.id,
      vehicleType: VehicleType.values.byName(row['vehicle_type'] as String),
      capacityTons: tons,
      capacity: '$tons టన్నులు / $tons Tons',
      vehicleNumber: row['vehicle_number'] as String,
      specializations: (row['specializations'] as List? ?? []).cast<String>(),
      isAvailable: row['is_available'] as bool,
      avatarUrl: row['avatar_url'] as String?,
      cardStyle: row['card_style'] as String? ?? 'classic_delta',
      isPhoneVerified: true,
    );
  }

  /// Reads the owner's record even when busy; a failed read is not a new driver.
  Future<DriverModel?> getOwnDriver(String phone) => _queue.run(() async {
    final normalized = IndianPhoneNumber.normalize(phone);
    final user = _client?.auth.currentUser;
    if (_client != null && (user == null ||
        IndianPhoneNumber.normalize(user.phone ?? '') != normalized)) {
      throw StateError('Verify this driver phone before restoring its profile');
    }
    bool matches(Map<String, dynamic> row) {
      if (user != null && row['user_id'] == user.id) return true;
      try {
        return IndianPhoneNumber.normalize(row['phone'] as String) == normalized;
      } catch (_) {
        return false;
      }
    }
    DriverModel? decode(Map<String, dynamic> row) {
      try {
        final driver = fromRow(row).copyWith(phone: normalized);
        if (driver.name.trim().length < 2 || driver.vehicleNumber.trim().isEmpty) return null;
        return driver;
      } on FormatException {
        return null;
      } on TypeError {
        return null;
      } on ArgumentError {
        return null;
      }
    }
    final pending = (await _store.read(_store.pendingKey)).where(matches).firstOrNull;
    final pendingDriver = pending == null ? null : decode(pending);
    if (pendingDriver != null) return pendingDriver;
    final cached = (await _store.read(_store.cacheKey)).where(matches).firstOrNull;
    if (_client == null) return cached == null ? null : decode(cached);
    if (user == null) throw StateError('A verified driver session is required');
    final uid = user.id;
    try {
      final phones = '$normalized,${normalized.substring(1)},${normalized.substring(3)}';
      List<Map<String, dynamic>> rows;
      try {
        rows = await _client.from('drivers').select()
            .or('user_id.eq.$uid,phone.in.($phones)')
            .limit(3).timeout(const Duration(seconds: 8));
      } on PostgrestException catch (error) {
        if (error.code != '42703' && error.code != 'PGRST204') rethrow;
        // Supports installations that have not applied the optional UID column.
        rows = await _client.from('drivers').select()
            .inFilter('phone', [normalized, normalized.substring(1), normalized.substring(3)])
            .limit(3).timeout(const Duration(seconds: 8));
      }
      final owned = rows.where(matches).toList();
      owned.sort((a, b) => (b['user_id'] == uid ? 1 : 0)
          .compareTo(a['user_id'] == uid ? 1 : 0));
      for (final row in owned) {
        final driver = decode(row);
        if (driver != null) {
          await _store.put(_store.cacheKey, row);
          return driver;
        }
      }
      return null;
    } catch (_) {
      final fallback = cached == null ? null : decode(cached);
      if (fallback != null) return fallback;
      rethrow;
    }
  });

  Future<void> _flush() async {
    final pending = await _store.read(_store.pendingKey);
    syncPending = pending.isNotEmpty;
    if (_client == null) return;
    for (final row in pending) {
      try {
        final confirmed = await _client
            .from('drivers')
            .upsert(row, onConflict: 'phone')
            .select('id')
            .timeout(const Duration(seconds: 8));
        if (confirmed.length != 1 || confirmed.single['id'] != row['id']) {
          throw StateError('Cloud driver write was not confirmed');
        }
        await _store.remove(_store.pendingKey, row['id'] as String);
      } catch (_) {
        syncPending = true;
        return;
      }
    }
    syncPending = false;
  }

  Future<void> upsertDriver(DriverModel driver) => _queue.run(() async {
    final row = toRow(driver, _now());
    await _store.put(_store.pendingKey, row);
    await _store.put(_store.cacheKey, row);
    await _flush();
  });

  /// Uploads a picker-compressed JPEG into the signed-in driver's own folder.
  /// The bucket must be provisioned by the driver avatar migration.
  Future<String> uploadDriverAvatar({
    required String driverId,
    required Uint8List jpegBytes,
  }) async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      throw StateError('Sign in to update your driver photo');
    }
    if (jpegBytes.isEmpty || jpegBytes.lengthInBytes > 5 * 1024 * 1024) {
      throw const FormatException('Driver photo must be under 5 MB');
    }
    final path = '${user.id}/$driverId.jpg';
    await client.storage
        .from('driver-avatars')
        .uploadBinary(
          path,
          jpegBytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            cacheControl: '3600',
            upsert: true,
          ),
        )
        .timeout(const Duration(seconds: 30));
    return client.storage.from('driver-avatars').getPublicUrl(path);
  }

  Future<List<DriverModel>> getAvailableDrivers() => _queue.run(() async {
    await _flush();
    var rows = await _store.read(_store.cacheKey);
    usingCache = true;
    if (_client != null) {
      try {
        final fetched = await _client
            .from('drivers')
            .select('id,phone,name,base_village_id,current_spot_village_id,vehicle_type,capacity_tons,vehicle_number,specializations,is_available,avatar_url,card_style,updated_at')
            .eq('is_available', true)
            .order('updated_at', ascending: false)
            .timeout(const Duration(seconds: 8));
        // Validate before replacing the last known usable snapshot.
        for (final row in fetched) {
          fromRow(row);
        }
        rows = fetched;
        await _store.write(_store.cacheKey, rows);
        usingCache = false;
      } catch (_) {
        /* Keep the last successful snapshot while offline. */
      }
    }
    final merged = {for (final row in rows) row['id'] as String: row};
    for (final row in await _store.read(_store.pendingKey)) {
      merged[row['id'] as String] = row;
    }
    return List.unmodifiable(
      merged.values.map(fromRow).where((d) => d.isAvailable),
    );
  });
  Future<void> _update(String id, {bool? available, String? spot}) =>
      _queue.run(() async {
        final cloudId = OfflineTableStore.cloudId('drivers', id);
        var rows = await _store.read(_store.cacheKey);
        var row = rows.where((r) => r['id'] == cloudId).firstOrNull;
        if (row == null) {
          final local = await LocalDriverRepository().getProfile();
          if (local == null ||
              OfflineTableStore.cloudId('drivers', local.id) != cloudId) {
            throw StateError('Driver not cached');
          }
          row = toRow(local.toDriverModel(), _now());
        }
        final updated = {
          ...row,
          'is_available': ?available,
          'current_spot_village_id': ?spot,
          'updated_at': _now().toUtc().toIso8601String(),
        };
        await _store.put(_store.pendingKey, updated);
        await _store.put(_store.cacheKey, updated);
        await _flush();
      });
  Future<void> updateAvailability(String driverId, bool isAvailable) =>
      _update(driverId, available: isAvailable);
  Future<void> updateCurrentSpot(String driverId, String villageId) {
    if (KolleruVillages.find(villageId) == null) {
      throw ArgumentError('Unknown village');
    }
    return _update(driverId, spot: villageId);
  }
}
