import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kolleru_wheels/core/constants/villages.dart';
import 'package:kolleru_wheels/data/models/driver_model.dart';
import 'package:kolleru_wheels/data/models/load_request_model.dart';
import 'package:kolleru_wheels/data/models/vehicle_type.dart';
import 'package:kolleru_wheels/data/repositories/offline_table_store.dart';
import 'package:kolleru_wheels/data/repositories/supabase_driver_repository.dart';
import 'package:kolleru_wheels/data/repositories/supabase_load_request_repository.dart';
import 'package:kolleru_wheels/data/repositories/load_request_repository.dart';

const driverId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const loadId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
final now = DateTime.utc(2026, 10, 6, 10);
DriverModel driver() => DriverModel(
  id: driverId,
  name: 'Ramesh',
  phone: '+919876543210',
  village: KolleruVillages.find('pulaparru')!,
  currentSpot: 'Kaikaluru Adda',
  currentSpotVillageId: 'kaikaluru-town',
  vehicleType: VehicleType.boleroPickup,
  capacity: '1.5 Tons',
  capacityTons: 1.5,
  vehicleNumber: 'AP 39 AB 1234',
  specializations: const ['Iron rods'],
  isAvailable: true,
);
LoadRequestModel load({DateTime? createdAt, bool closed = false}) =>
    LoadRequestModel(
      id: loadId,
      posterName: 'Farmer',
      posterPhone: '+919876543210',
      fromLocation: 'Market',
      toVillage: KolleruVillages.find('pulaparru')!,
      materialType: 'Cement',
      vehicleTypeNeeded: VehicleType.tataAce,
      createdAt: createdAt ?? now,
      isClosed: closed,
    );
http.Response jsonResponse(Object data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json'},
);
SupabaseClient clientWith(
  Future<http.Response> Function(http.Request) handler,
) {
  final client = SupabaseClient(
    'https://example.supabase.co',
    'public-test-key',
    httpClient: MockClient((request) async {
      final response = await handler(request);
      return http.Response.bytes(
        response.bodyBytes,
        response.statusCode,
        headers: response.headers,
        request: request,
      );
    }),
  );
  addTearDown(client.dispose);
  return client;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('Unconfirmed cloud writes remain pending', () async {
    final client = clientWith((request) async => jsonResponse([]));
    final repository = SupabaseDriverRepository(client: client, now: () => now);
    await repository.upsertDriver(driver());
    expect(repository.syncPending, true);
    expect(
      await const OfflineTableStore('drivers')
          .read('supabase_drivers_pending_v1'),
      hasLength(1),
    );
  });
  test(
    'Driver schema round trip uses typed capacity, stable IDs and village IDs',
    () {
      final row = SupabaseDriverRepository.toRow(driver(), now);
      expect(
        row.keys,
        containsAll([
          'id',
          'phone',
          'name',
          'base_village_id',
          'current_spot_village_id',
          'vehicle_type',
          'capacity_tons',
          'vehicle_number',
          'specializations',
          'is_available',
          'updated_at',
        ]),
      );
      final restored = SupabaseDriverRepository.fromRow(row);
      expect(restored.id, driverId);
      expect(restored.capacityTons, 1.5);
      expect(restored.currentSpotVillageId, 'kaikaluru-town');
      expect(restored.specializations, ['Iron rods']);
      expect(
        OfflineTableStore.cloudId('drivers', 'local-123'),
        OfflineTableStore.cloudId('drivers', 'local-123'),
      );
      expect(
        OfflineTableStore.cloudId('drivers', 'local-123'),
        isNot(OfflineTableStore.cloudId('load_requests', 'local-123')),
      );
    },
  );
  test('Available driver fetch uses the filter and falls back to the last snapshot', () async {
    var offline = false;
    final client = clientWith((request) async {
      if (offline) throw const SocketException('offline');
      expect(request.url.path, '/rest/v1/drivers');
      expect(request.url.queryParameters['is_available'], 'eq.true');
      return jsonResponse([SupabaseDriverRepository.toRow(driver(), now)]);
    });
    final repository = SupabaseDriverRepository(client: client, now: () => now);
    expect((await repository.getAvailableDrivers()).single.id, driverId);
    expect(repository.usingCache, false);
    offline = true;
    expect((await repository.getAvailableDrivers()).single.id, driverId);
    expect(repository.usingCache, true);
    final restarted = SupabaseDriverRepository(now: () => now);
    expect((await restarted.getAvailableDrivers()).single.id, driverId);
  });
  test('Offline driver writes persist, retry, and overlay stale cloud availability', () async {
    var offline = true;
    final mutations = <Map<String, dynamic>>[];
    final client = clientWith((request) async {
      if (offline) throw const SocketException('offline');
      if (request.method == 'POST') {
        expect(request.url.queryParameters['on_conflict'], 'phone');
        mutations.add(
          Map<String, dynamic>.from(jsonDecode(request.body) as Map),
        );
        return jsonResponse([
          {'id': mutations.last['id']},
        ]);
      }
      return jsonResponse([SupabaseDriverRepository.toRow(driver(), now)]);
    });
    final repository = SupabaseDriverRepository(client: client, now: () => now);
    await repository.upsertDriver(driver());
    expect(repository.syncPending, true);
    await repository.updateAvailability(driverId, false);
    expect(await repository.getAvailableDrivers(), isEmpty);
    await repository.updateCurrentSpot(driverId, 'kovvadalanka');
    final pending = await const OfflineTableStore('drivers')
        .read('supabase_drivers_pending_v1');
    expect(pending.single['is_available'], false);
    expect(pending.single['current_spot_village_id'], 'kovvadalanka');
    offline = false;
    await repository.getAvailableDrivers();
    expect(repository.syncPending, false);
    expect(mutations.single['is_available'], false);
    expect(
      await const OfflineTableStore('drivers')
          .read('supabase_drivers_pending_v1'),
      isEmpty,
    );
  });
  test('Load schema and remote query enforce closure, UTC cutoff and exact TTL', () async {
    final row = SupabaseLoadRequestRepository.toRow(load());
    expect(
      row.keys,
      containsAll([
        'id',
        'poster_name',
        'poster_phone',
        'from_location',
        'to_village_id',
        'material_type',
        'vehicle_type_needed',
        'is_closed',
        'created_at',
      ]),
    );
    expect(
      SupabaseLoadRequestRepository.fromRow(row).toVillage.id,
      'pulaparru',
    );
    final client = clientWith((request) async {
      expect(request.url.path, '/rest/v1/load_requests');
      expect(request.url.queryParameters['is_closed'], 'eq.false');
      expect(
        request.url.queryParametersAll['created_at'],
        containsAll([
          'gte.${now.subtract(const Duration(minutes: 30)).toIso8601String()}',
          'lte.${now.toIso8601String()}',
        ]),
      );
      return jsonResponse([
        row,
        {
          ...SupabaseLoadRequestRepository.toRow(
            load(createdAt: now.subtract(const Duration(minutes: 30))),
          ),
          'id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        },
        {
          ...SupabaseLoadRequestRepository.toRow(load(closed: true)),
          'id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
        },
      ]);
    });
    final repository = SupabaseLoadRequestRepository(
      client: client,
      now: () => now,
    );
    addTearDown(repository.dispose);
    expect(await repository.getActiveLoadRequests(), hasLength(1));
    expect(
      await repository.getActiveRequests(operationalMandalId: 'kaikaluru'),
      isEmpty,
    );
  });
  test(
    'Load cached fallback still expires using the repository clock',
    () async {
      var clock = now;
      var offline = false;
      final client = clientWith((request) async {
        if (offline) throw const SocketException('offline');
        return jsonResponse([SupabaseLoadRequestRepository.toRow(load())]);
      });
      final repository = SupabaseLoadRequestRepository(
        client: client,
        now: () => clock,
      );
      addTearDown(repository.dispose);
      expect(await repository.getActiveLoadRequests(), hasLength(1));
      offline = true;
      clock = now.add(const Duration(minutes: 29, seconds: 59));
      expect(await repository.getActiveLoadRequests(), hasLength(1));
      expect(repository.usingCache, true);
      clock = clock.add(const Duration(seconds: 1));
      expect(await repository.getActiveLoadRequests(), isEmpty);
    },
  );
  test(
    'Offline posting queues and retries; expired queued posts never upload',
    () async {
      var clock = now;
      var offline = true;
      var posts = 0;
      final client = clientWith((request) async {
        if (offline) throw const SocketException('offline');
        if (request.method == 'POST') {
          posts++;
          return jsonResponse([
            {'id': (jsonDecode(request.body) as Map)['id']},
          ]);
        }
        return jsonResponse([]);
      });
      final repository = SupabaseLoadRequestRepository(
        client: client,
        now: () => clock,
      );
      addTearDown(repository.dispose);
      await repository.createLoadRequest(load());
      expect(repository.syncPending, true);
      expect(await repository.getActiveLoadRequests(), hasLength(1));
      offline = false;
      await repository.getActiveLoadRequests();
      expect(posts, 1);
      expect(repository.syncPending, false);
      offline = true;
      await repository.createLoadRequest(load());
      clock = now.add(const Duration(minutes: 30));
      offline = false;
      expect(await repository.getActiveLoadRequests(), isEmpty);
      expect(posts, 1);
    },
  );
  test(
    'Close survives offline and retries without resurrecting old local records',
    () async {
      var offline = false;
      final cloud = <String, Map<String, dynamic>>{};
      final client = clientWith((request) async {
        if (offline) throw const SocketException('offline');
        if (request.method == 'POST') {
          final row = Map<String, dynamic>.from(
            jsonDecode(request.body) as Map,
          );
          cloud[row['id'] as String] = row;
          return jsonResponse([
            {'id': row['id']},
          ]);
        }
        return jsonResponse(
          cloud.values.where((r) => r['is_closed'] == false).toList(),
        );
      });
      final repository = SupabaseLoadRequestRepository(
        client: client,
        now: () => now,
      );
      addTearDown(repository.dispose);
      final request = await repository.createRequest(
        posterName: 'Farmer',
        posterPhone: '+919876543210',
        fromLocation: 'Market',
        toVillageId: 'pulaparru',
        materialType: 'Cement',
      );
      expect(await repository.getActiveLoadRequests(), hasLength(1));
      offline = true;
      await repository.closeLoadRequest(request.id);
      expect(await repository.getActiveLoadRequests(), isEmpty);
      offline = false;
      expect(await repository.getActiveLoadRequests(), isEmpty);
      offline = true;
      expect(await repository.getActiveLoadRequests(), isEmpty);
    },
  );
  test(
    'Legacy local active requests migrate once into the cloud outbox',
    () async {
      final local = LoadRequestRepository(now: () => now);
      addTearDown(local.dispose);
      await local.createRequest(
        posterName: 'Farmer',
        posterPhone: '+919876543210',
        fromLocation: 'Market',
        toVillageId: 'pulaparru',
        materialType: 'Cement',
      );
      final remote = SupabaseLoadRequestRepository(now: () => now);
      addTearDown(remote.dispose);
      expect(await remote.getActiveLoadRequests(), hasLength(1));
      expect(await remote.getActiveLoadRequests(), hasLength(1));
      expect(
        await const OfflineTableStore('load_requests')
            .read('supabase_load_requests_pending_v1'),
        hasLength(1),
      );
    },
  );
}
