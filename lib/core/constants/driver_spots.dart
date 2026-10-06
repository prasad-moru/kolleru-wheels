import 'villages.dart';

class DriverSpot {
  const DriverSpot({required this.villageId, required this.label});
  final String villageId;
  final String label;
}

abstract final class DriverSpots {
  static const hubs = <DriverSpot>[
    DriverSpot(
      villageId: 'kaikaluru-town',
      label: 'కైకలూరు అడ్డా / Kaikaluru Adda',
    ),
    DriverSpot(
      villageId: 'akividu-town',
      label: 'ఆకివీడు మార్కెట్ / Akividu Market',
    ),
  ];
  static List<DriverSpot> get all => [
    ...hubs,
    for (final village in KolleruVillages.all)
      DriverSpot(villageId: village.id, label: village.label),
  ];
}
