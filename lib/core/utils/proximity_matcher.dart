import '../constants/villages.dart';
import '../../data/models/driver_model.dart';

enum ProximityTier { local, mandal, deltaBelt }

class ProximityResult {
  ProximityResult({
    required List<DriverModel> tier1,
    required List<DriverModel> tier2,
    required List<DriverModel> tier3,
  }) : tier1 = List.unmodifiable(tier1),
       tier2 = List.unmodifiable(tier2),
       tier3 = List.unmodifiable(tier3);
  final List<DriverModel> tier1;
  final List<DriverModel> tier2;
  final List<DriverModel> tier3;
}

class ProximityMatch {
  const ProximityMatch(this.driver, this.tier);
  final DriverModel driver;
  final ProximityTier tier;
}

/// Cluster proximity, not GPS distance. The other supported Kolleru mandals
/// form the wider delta-belt fallback; no road-distance claim is made.
abstract final class ProximityMatcher {
  static ProximityResult match(
    Iterable<DriverModel> drivers,
    Village selectedVillage,
  ) {
    final ranked = rank(drivers, selectedVillage.id);
    return ProximityResult(
      tier1: ranked
          .where((m) => m.tier == ProximityTier.local)
          .map((m) => m.driver)
          .toList(),
      tier2: ranked
          .where((m) => m.tier == ProximityTier.mandal)
          .map((m) => m.driver)
          .toList(),
      tier3: ranked
          .where((m) => m.tier == ProximityTier.deltaBelt)
          .map((m) => m.driver)
          .toList(),
    );
  }

  static String? mandalId(String? villageId) {
    for (final mandal in KolleruVillages.mandals) {
      if (mandal.villages.any((v) => v.id == villageId)) return mandal.id;
    }
    return null;
  }

  static ProximityTier? tierFor(DriverModel driver, String selectedVillageId) {
    final selectedMandal = mandalId(selectedVillageId);
    if (!driver.isAvailable || selectedMandal == null) return null;
    final base = mandalId(driver.village.id);
    final current = mandalId(driver.currentSpotVillageId);
    if (driver.village.id == selectedVillageId ||
        driver.currentSpotVillageId == selectedVillageId) {
      return ProximityTier.local;
    }
    if (base == selectedMandal || current == selectedMandal) {
      return ProximityTier.mandal;
    }
    if (base != null || current != null) return ProximityTier.deltaBelt;
    return null;
  }

  static List<ProximityMatch> rank(
    Iterable<DriverModel> drivers,
    String selectedVillageId,
  ) {
    final matches = <ProximityMatch>[];
    final seen = <String>{};
    for (final driver in drivers) {
      final tier = tierFor(driver, selectedVillageId);
      if (tier != null && seen.add(driver.id)) {
        matches.add(ProximityMatch(driver, tier));
      }
    }
    // Keep repository order inside a tier for deterministic, stable results.
    return [
      for (final tier in ProximityTier.values)
        ...matches.where((m) => m.tier == tier),
    ];
  }
}
