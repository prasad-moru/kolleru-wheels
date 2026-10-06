import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kolleru_wheels/core/constants/villages.dart';
import 'package:kolleru_wheels/core/utils/proximity_matcher.dart';
import 'package:kolleru_wheels/data/models/driver_model.dart';
import 'package:kolleru_wheels/data/models/load_request_model.dart';
import 'package:kolleru_wheels/data/models/vehicle_type.dart';
import 'package:kolleru_wheels/data/repositories/load_request_repository.dart';
import 'package:kolleru_wheels/presentation/driver/load_pool_board.dart';

DriverModel driver(
  String id,
  String base, {
  String? spot,
  bool available = true,
}) => DriverModel(
  id: id,
  name: id,
  phone: '+919876543210',
  village: KolleruVillages.find(base)!,
  currentSpot: 'Market',
  currentSpotVillageId: spot,
  vehicleType: VehicleType.tataAce,
  capacity: '750 kg',
  isAvailable: available,
);

LoadRequestModel load(DateTime createdAt, {bool isClosed = false}) =>
    LoadRequestModel(
      id: 'load-test',
      posterName: 'Farmer',
      posterPhone: '+919876543210',
      fromLocation: 'Market',
      toVillage: KolleruVillages.find('pulaparru')!,
      materialType: 'సిమెంట్',
      vehicleTypeNeeded: VehicleType.tataAce,
      createdAt: createdAt,
      isClosed: isClosed,
    );

Future<LoadRequestModel> post(
  LoadRequestRepository repository,
  String destination,
) => repository.createRequest(
  posterName: 'Farmer',
  posterPhone: '+919876543210',
  fromLocation: 'Market',
  toVillage: KolleruVillages.find(destination)!,
  materialType: 'సిమెంట్',
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Structured result groups best tier, excludes busy, and preserves input order', () {
    final inputs = [
      driver('delta', 'pulaparru'),
      driver('hub', 'kovvadalanka'),
      driver('moved-local', 'akividu-town', spot: 'kaikaluru-town'),
      driver('base-local', 'kaikaluru-town', spot: 'pulaparru'),
      driver('moved-hub', 'pulaparru', spot: 'atapaka'),
      driver('busy', 'kaikaluru-town', available: false),
    ];
    final result = ProximityMatcher.match(
      inputs,
      KolleruVillages.find('kaikaluru-town')!,
    );
    expect(result.tier1.map((d) => d.id), ['moved-local', 'base-local']);
    expect(result.tier2.map((d) => d.id), ['hub', 'moved-hub']);
    expect(result.tier3.map((d) => d.id), ['delta']);
    expect(inputs.first.id, 'delta');
    expect(() => result.tier1.clear(), throwsUnsupportedError);
  });

  test(
    'Structured result deduplicates and handles empty/unknown selections',
    () {
      final local = driver('local', 'pulaparru');
      expect(
        ProximityMatcher.match([
          local,
          local,
        ], KolleruVillages.find('pulaparru')!).tier1,
        hasLength(1),
      );
      final missing = ProximityMatcher.match([
        local,
      ], const Village(id: 'unknown', name: 'Unknown', teluguName: ''));
      expect([...missing.tier1, ...missing.tier2, ...missing.tier3], isEmpty);
      expect(
        ProximityMatcher.match([], KolleruVillages.find('pulaparru')!).tier1,
        isEmpty,
      );
    },
  );

  test(
    'Boolean closure and exact TTL boundary use the same active predicate',
    () {
      final now = DateTime.utc(2026, 10, 6, 10);
      expect(
        load(
          now
              .subtract(const Duration(minutes: 30))
              .add(const Duration(microseconds: 1)),
        ).isActiveAt(now),
        true,
      );
      expect(
        load(now.subtract(const Duration(minutes: 30))).isActiveAt(now),
        false,
      );
      expect(
        load(now.subtract(const Duration(minutes: 31))).isActiveAt(now),
        false,
      );
      expect(load(now, isClosed: true).isActiveAt(now), false);
      expect(load(now).close().isClosed, true);
      expect(load(now.add(const Duration(seconds: 1))).isActiveAt(now), false);
    },
  );

  test('Legacy status/id JSON and new village/boolean JSON both restore', () {
    final now = DateTime.utc(2026, 10, 6, 10);
    final legacy = load(now, isClosed: true).toJson()
      ..remove('isClosed')
      ..remove('toVillage');
    final modern = load(now, isClosed: true).toJson()
      ..remove('status')
      ..remove('toVillageId');
    for (final data in [legacy, modern]) {
      final restored = LoadRequestModel.fromJson(data);
      expect(restored.toVillage.id, 'pulaparru');
      expect(restored.isClosed, true);
      expect(restored.isActiveAt(now), false);
    }
  });

  test('Operational mandal filter uses structured destination and still enforces TTL', () async {
    var now = DateTime.utc(2026, 10, 6, 10);
    final repository = LoadRequestRepository(now: () => now);
    addTearDown(repository.dispose);
    final local = await post(repository, 'pulaparru');
    await post(repository, 'kaikaluru-town');
    await post(repository, 'mandavalli');
    expect(
      await repository.getActiveRequests(operationalMandalId: 'mandavalli'),
      hasLength(2),
    );
    expect(
      await repository.getActiveRequests(operationalMandalId: 'kaikaluru'),
      hasLength(1),
    );
    expect(
      await repository.getActiveRequests(operationalMandalId: 'unknown'),
      isEmpty,
    );
    await repository.closeRequest(local.id);
    expect(
      await repository.getActiveRequests(operationalMandalId: 'mandavalli'),
      hasLength(1),
    );
    now = now.add(const Duration(minutes: 30));
    expect(
      await repository.getActiveRequests(operationalMandalId: 'mandavalli'),
      isEmpty,
    );
    expect(await repository.getActiveRequests(), isEmpty);
  });

  test(
    'Persisted legacy expired/closed requests never appear after restart',
    () async {
      final now = DateTime.utc(2026, 10, 6, 10);
      final expired = load(now.subtract(const Duration(minutes: 30))).toJson()
        ..remove('isClosed')
        ..remove('toVillage');
      SharedPreferences.setMockInitialValues({
        LoadRequestRepository.storageKey: jsonEncode([
          expired,
          load(now, isClosed: true).toJson(),
        ]),
      });
      final repository = LoadRequestRepository(now: () => now);
      addTearDown(repository.dispose);
      expect(await repository.getActiveRequests(), isEmpty);
    },
  );

  testWidgets(
    'Board changes requests when the driver operational mandal changes',
    (tester) async {
      final repository = LoadRequestRepository();
      addTearDown(repository.dispose);
      await post(repository, 'pulaparru');
      await post(repository, 'kaikaluru-town');
      Widget board(String mandal) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LoadPoolBoard(
              repository: repository,
              operationalMandalId: mandal,
            ),
          ),
        ),
      );
      await tester.pumpWidget(board('mandavalli'));
      await tester.pumpAndSettle();
      expect(
        find.text('Market ➔ ${KolleruVillages.find('pulaparru')!.label}'),
        findsOneWidget,
      );
      expect(
        find.text('Market ➔ ${KolleruVillages.find('kaikaluru-town')!.label}'),
        findsNothing,
      );
      await tester.pumpWidget(board('kaikaluru'));
      await tester.pumpAndSettle();
      expect(
        find.text('Market ➔ ${KolleruVillages.find('pulaparru')!.label}'),
        findsNothing,
      );
      expect(
        find.text('Market ➔ ${KolleruVillages.find('kaikaluru-town')!.label}'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
