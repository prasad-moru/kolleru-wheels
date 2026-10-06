import '../../core/constants/villages.dart';
import '../models/driver_model.dart';
import '../models/vehicle_type.dart';

abstract interface class DirectoryRepository {
  List<DriverModel> getDrivers({
    String? villageId,
    VehicleType? vehicleType,
    bool availableOnly = false,
  });
}

class MockDirectoryRepository implements DirectoryRepository {
  MockDirectoryRepository()
    : _drivers = List.unmodifiable([
        _driver(
          '1',
          'రమేష్ / Ramesh',
          'pulaparru',
          'పులపర్రు సెంటర్ / Pulaparru centre',
          VehicleType.boleroPickup,
          '1.5 టన్నులు / 1.5 Tons',
          true,
        ),
        _driver(
          '2',
          'శ్రీను / Srinu',
          'pulaparru',
          'చేపల చెరువులు / Fish ponds',
          VehicleType.tataAce,
          '750 కిలోలు / 750 kg',
          false,
        ),
        _driver(
          '3',
          'వెంకటేశ్ / Venkatesh',
          'kaikaluru-town',
          'మార్కెట్ యార్డ్ / Market yard',
          VehicleType.eicher14ft,
          '4 టన్నులు / 4 Tons • 14 ft',
          true,
        ),
        _driver(
          '4',
          'నాగరాజు / Nagaraju',
          'kaikaluru-town',
          'బస్ స్టాండ్ / Bus stand',
          VehicleType.dost,
          '1.25 టన్నులు / 1.25 Tons',
          true,
        ),
        _driver(
          '5',
          'సత్యం / Satyam',
          'kovvadalanka',
          'వంతెన దగ్గర / Near the bridge',
          VehicleType.boleroPickup,
          '1.5 టన్నులు / 1.5 Tons',
          false,
        ),
        _driver(
          '6',
          'ప్రసాద్ / Prasad',
          'kovvadalanka',
          'గ్రామ సెంటర్ / Village centre',
          VehicleType.tractor,
          'ట్రైలర్ / Trailer • 3 టన్నులు / 3 Tons',
          true,
        ),
      ]);
  final List<DriverModel> _drivers;
  static DriverModel _driver(
    String id,
    String name,
    String villageId,
    String spot,
    VehicleType type,
    String capacity,
    bool available,
  ) => DriverModel(
    id: id,
    name: name,
    phone: '+91000000000$id',
    village: KolleruVillages.find(villageId)!,
    currentSpot: spot,
    currentSpotVillageId: villageId,
    vehicleType: type,
    capacity: capacity,
    isAvailable: available,
    isDemo: true,
    vehicleNumber: 'AP • DEMO 00$id',
    specializations: switch (type) {
      VehicleType.boleroPickup => const ['ఐరన్ / పైపులు • Iron / Pipes'],
      VehicleType.tataAce => const ['లైవ్ ఫిష్ / చేపల ట్యాంక్ • Live fish'],
      VehicleType.dost => const ['మేత / ధాన్యం • Feed / Grain'],
      VehicleType.eicher14ft => const [
        'చేపల బాక్సులు • Fish boxes',
        'భారీ లోడ్లు • Heavy loads',
      ],
      VehicleType.tractor => const ['పంట / వ్యవసాయం • Farm loads'],
    },
  );
  @override
  List<DriverModel> getDrivers({
    String? villageId,
    VehicleType? vehicleType,
    bool availableOnly = false,
  }) => List.unmodifiable(
    _drivers.where(
      (d) =>
          (villageId == null || d.village.id == villageId) &&
          (vehicleType == null || d.vehicleType == vehicleType) &&
          (!availableOnly || d.isAvailable),
    ),
  );
}
