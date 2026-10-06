import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/supabase_config.dart';
import '../../core/constants/villages.dart';
import '../../core/utils/proximity_matcher.dart';
import '../models/load_request_model.dart';
import '../models/vehicle_type.dart';
import 'load_request_repository.dart';
import 'offline_table_store.dart';

class SupabaseLoadRequestRepository extends LoadRequestRepository {
  SupabaseLoadRequestRepository({SupabaseClient? client, super.now})
    : _client = client ?? SupabaseConfig.client;
  final SupabaseClient? _client;
  final _store = const OfflineTableStore('load_requests');
  final _queue = RepositoryQueue();
  bool usingCache = false;
  bool syncPending = false;
  String get _knownKey => 'supabase_load_requests_known_v1';
  Future<void> _seedLocalRequests() async {
    final known = (await _store.read(_knownKey)).map((r) => r['id']).toSet();
    for (final request in await super.getActiveRequests()) {
      final row = toRow(request);
      if (known.add(row['id'])) {
        await _store.put(_store.pendingKey, row);
        await _store.put(_store.cacheKey, row);
        await _store.put(_knownKey, {'id': row['id']});
      }
    }
  }

  static Map<String, dynamic> toRow(LoadRequestModel request) => {
    'id': OfflineTableStore.cloudId('load_requests', request.id),
    'poster_name': request.posterName,
    'poster_phone': request.posterPhone,
    'from_location': request.fromLocation,
    'to_village_id': request.toVillageId,
    'material_type': request.materialType,
    'vehicle_type_needed': request.vehicleTypeNeeded?.name,
    'is_closed': request.isClosed,
    'created_at': request.createdAt.toUtc().toIso8601String(),
  };
  static LoadRequestModel fromRow(Map<String, dynamic> row) =>
      LoadRequestModel.fromJson({
        'id': row['id'],
        'posterName': row['poster_name'],
        'posterPhone': row['poster_phone'],
        'fromLocation': row['from_location'],
        'toVillageId': row['to_village_id'],
        'materialType': row['material_type'],
        'vehicleTypeNeeded': row['vehicle_type_needed'],
        'isClosed': row['is_closed'],
        'createdAt': row['created_at'],
      });
  Future<void> _flush() async {
    final pending = await _store.read(_store.pendingKey);
    syncPending = pending.isNotEmpty;
    if (_client == null) return;
    for (final row in pending) {
      try {
        if (row.length == 2) {
          final confirmed = await _client
              .from('load_requests')
              .update({'is_closed': true})
              .eq('id', row['id'])
              .select('id')
              .timeout(const Duration(seconds: 8));
          if (confirmed.length != 1 || confirmed.single['id'] != row['id']) {
            throw StateError('Cloud close was not confirmed');
          }
        } else if (!fromRow(row).isClosed &&
            !fromRow(row).isActiveAt(currentTime)) {
          // Expired offline posts must never be resurrected in the cloud.
          await _store.remove(_store.pendingKey, row['id'] as String);
          continue;
        } else {
          final confirmed = await _client
              .from('load_requests')
              .upsert(row, onConflict: 'id')
              .select('id')
              .timeout(const Duration(seconds: 8));
          if (confirmed.length != 1 || confirmed.single['id'] != row['id']) {
            throw StateError('Cloud load write was not confirmed');
          }
        }
        await _store.remove(_store.pendingKey, row['id'] as String);
      } catch (_) {
        syncPending = true;
        return;
      }
    }
    syncPending = false;
  }

  Future<void> createLoadRequest(LoadRequestModel request) =>
      _queue.run(() async {
        if (!request.isActiveAt(currentTime)) {
          throw ArgumentError('Only active requests may be posted');
        }
        final row = toRow(request);
        fromRow(row);
        await _store.put(_store.pendingKey, row);
        await _store.put(_store.cacheKey, row);
        await _flush();
        await _store.put(_knownKey, {'id': row['id']});
      });
  @override
  Future<LoadRequestModel> createRequest({
    required String posterName,
    required String posterPhone,
    required String fromLocation,
    String? toVillageId,
    Village? toVillage,
    required String materialType,
    VehicleType? vehicleTypeNeeded,
  }) async {
    final request = await super.createRequest(
      posterName: posterName,
      posterPhone: posterPhone,
      fromLocation: fromLocation,
      toVillageId: toVillageId,
      toVillage: toVillage,
      materialType: materialType,
      vehicleTypeNeeded: vehicleTypeNeeded,
    );
    await createLoadRequest(request);
    notifyListeners();
    return request;
  }

  Future<List<LoadRequestModel>> getActiveLoadRequests() => _queue.run(
    () async {
      await _seedLocalRequests();
      await _flush();
      var rows = await _store.read(_store.cacheKey);
      usingCache = true;
      if (_client != null) {
        try {
          final now = currentTime;
          final fetched = await _client
              .from('load_requests')
              .select()
              .eq('is_closed', false)
              .gte(
                'created_at',
                now
                    .subtract(LoadRequestModel.lifetime)
                    .toUtc()
                    .toIso8601String(),
              )
              .lte('created_at', now.toUtc().toIso8601String())
              .order('created_at', ascending: false)
              .timeout(const Duration(seconds: 8));
          for (final row in fetched) {
            fromRow(row);
          }
          rows = fetched;
          await _store.write(_store.cacheKey, rows);
          usingCache = false;
        } catch (_) {
          /* Offline/RLS failures retain the local snapshot. */
        }
      }
      final merged = {for (final row in rows) row['id'] as String: row};
      // Pending local posts and closes take precedence over a cloud snapshot.
      final pending = await _store.read(_store.pendingKey);
      for (final row in pending) {
        if (row.length == 2) {
          merged.remove(row['id']);
        } else {
          merged[row['id'] as String] = row;
        }
      }
      // Known local IDs are migrated once. Never reintroduce an old local copy
      // after an authoritative cloud snapshot has removed/closed its row.
      final active =
          merged.values
              .map(fromRow)
              .where((r) => r.isActiveAt(currentTime))
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return List.unmodifiable(active);
    },
  );
  @override
  Future<List<LoadRequestModel>> getActiveRequests({
    String? operationalMandalId,
  }) async => (await getActiveLoadRequests())
      .where(
        (r) =>
            operationalMandalId == null ||
            ProximityMatcher.mandalId(r.toVillageId) == operationalMandalId,
      )
      .toList();
  Future<void> closeLoadRequest(String requestId) => _queue.run(() async {
    final id = OfflineTableStore.cloudId('load_requests', requestId);
    await super.closeRequest(requestId);
    final cache = await _store.read(_store.cacheKey);
    final row = cache.where((r) => r['id'] == id).firstOrNull;
    final closed = row == null
        ? <String, dynamic>{'id': id, 'is_closed': true}
        : {...row, 'is_closed': true};
    await _store.put(_store.pendingKey, closed);
    if (row != null) await _store.put(_store.cacheKey, closed);
    await _flush();
    notifyListeners();
  });
  @override
  Future<void> closeRequest(String id) => closeLoadRequest(id);
}
