import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/supabase_config.dart';
import '../../core/constants/villages.dart';
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
    );
  }

  Future<void> _flush() async {
    final pending = await _store.read(_store.pendingKey);
    syncPending = pending.isNotEmpty;
    if (_client == null) return;
    for (final row in pending) {
      try {
        final confirmed = await _client
            .from('drivers')
            .upsert(row, onConflict: 'id')
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
  Future<List<DriverModel>> getAvailableDrivers() => _queue.run(() async {
    await _flush();
    var rows = await _store.read(_store.cacheKey);
    usingCache = true;
    if (_client != null) {
      try {
        final fetched = await _client
            .from('drivers')
            .select()
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
