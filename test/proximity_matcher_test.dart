import 'package:flutter_test/flutter_test.dart';
import 'package:kolleru_wheels/core/constants/villages.dart';
import 'package:kolleru_wheels/core/utils/proximity_matcher.dart';
import 'package:kolleru_wheels/data/models/driver_model.dart';
import 'package:kolleru_wheels/data/models/vehicle_type.dart';

DriverModel driver(
  String id,
  String base, {
  String? current,
  bool available = true,
}) => DriverModel(
  id: id,
  name: id,
  phone: '+919876543210',
  village: KolleruVillages.find(base)!,
  currentSpot: 'Arbitrary market label',
  currentSpotVillageId: current,
  vehicleType: VehicleType.boleroPickup,
  capacity: '1.5 t',
  isAvailable: available,
);

void main() {
  test('Ranks current or base village first, mandal second, belt third', () {
    final inputs = [
      driver('delta', 'pulaparru'),
      driver('mandal-base', 'kovvadalanka'),
      driver('local-current', 'akividu-town', current: 'kaikaluru-town'),
      driver('local-base', 'kaikaluru-town', current: 'pulaparru'),
      driver('mandal-current', 'pulaparru', current: 'atapaka'),
      driver('busy-local', 'kaikaluru-town', available: false),
      driver('delta2', 'kalidindi'),
    ];
    final matches = ProximityMatcher.rank(inputs, 'kaikaluru-town');
    expect(matches.map((m) => m.driver.id), [
      'local-current',
      'local-base',
      'mandal-base',
      'mandal-current',
      'delta',
      'delta2',
    ]);
    expect(matches.map((m) => m.tier), [
      ProximityTier.local,
      ProximityTier.local,
      ProximityTier.mandal,
      ProximityTier.mandal,
      ProximityTier.deltaBelt,
      ProximityTier.deltaBelt,
    ]);
    expect(inputs.first.id, 'delta');
  });
  test('Stable within tiers; missing structured spot falls back to base', () {
    final a = driver('a', 'pulaparru');
    final b = driver('b', 'pulaparru');
    expect(
      ProximityMatcher.rank([b, a, b], 'pulaparru').map((m) => m.driver.id),
      ['b', 'a'],
    );
    expect(
      ProximityMatcher.tierFor(
        driver('x', 'kovvadalanka', current: 'unknown'),
        'atapaka',
      ),
      ProximityTier.mandal,
    );
  });
  test('Unknown selection and unavailable drivers do not produce matches', () {
    expect(
      ProximityMatcher.rank([driver('a', 'pulaparru')], 'missing'),
      isEmpty,
    );
    expect(
      ProximityMatcher.rank([
        driver('a', 'pulaparru', available: false),
      ], 'pulaparru'),
      isEmpty,
    );
    expect(ProximityMatcher.rank([], 'pulaparru'), isEmpty);
  });
  test('Every supplied village maps to exactly its declared mandal', () {
    for (final mandal in KolleruVillages.mandals) {
      for (final village in mandal.villages) {
        expect(ProximityMatcher.mandalId(village.id), mandal.id);
      }
    }
    expect(ProximityMatcher.mandalId(null), isNull);
    expect(ProximityMatcher.mandalId('missing'), isNull);
  });
}
