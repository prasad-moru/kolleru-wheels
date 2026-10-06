import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kolleru_wheels/core/constants/app_strings.dart';
import 'package:kolleru_wheels/core/constants/driver_spots.dart';
import 'package:kolleru_wheels/core/constants/villages.dart';
import 'package:kolleru_wheels/core/theme/app_theme.dart';
import 'package:kolleru_wheels/data/models/local_driver_profile.dart';
import 'package:kolleru_wheels/data/models/vehicle_type.dart';
import 'package:kolleru_wheels/data/repositories/local_driver_repository.dart';
import 'package:kolleru_wheels/main.dart';
import 'package:kolleru_wheels/presentation/driver/driver_dashboard_screen.dart';
import 'package:kolleru_wheels/presentation/driver/driver_mode_screen.dart';
import 'package:kolleru_wheels/presentation/driver/driver_registration_screen.dart';
import 'package:kolleru_wheels/presentation/driver/visiting_card_screen.dart';

LocalDriverProfile profile() => LocalDriverProfile(
  id: 'local-test',
  name: 'రమేష్ / Ramesh',
  phone: '+919876543210',
  baseVillage: KolleruVillages.find('pulaparru')!,
  currentSpotVillage: KolleruVillages.find('pulaparru')!,
  vehicleType: VehicleType.boleroPickup,
  capacityTons: 1.5,
  specializations: [AppStrings.specializationOptions.first],
  vehicleNumber: 'AP 39 AB 1234',
  isAvailable: true,
);

class FailingWritesRepository extends LocalDriverRepository {
  @override
  Future<LocalDriverProfile> updateAvailability(bool isAvailable) async {
    throw StateError('Simulated storage failure');
  }
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      250,
      scrollable: find.byType(Scrollable).last,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'Profile survives repository recreation and concurrent field updates',
    () async {
      final repository = LocalDriverRepository();
      await repository.saveProfile(profile());
      await Future.wait([
        repository.updateAvailability(false),
        LocalDriverRepository().updateCurrentSpot(
          KolleruVillages.find('kaikaluru-town')!,
          label: DriverSpots.hubs.first.label,
        ),
      ]);
      final restored = (await LocalDriverRepository().getProfile())!;
      expect(restored.name, profile().name);
      expect(restored.phone, profile().phone);
      expect(restored.baseVillage.id, 'pulaparru');
      expect(restored.currentSpotVillage.id, 'kaikaluru-town');
      expect(restored.currentSpotLabel, DriverSpots.hubs.first.label);
      expect(restored.isAvailable, false);
      expect(restored.capacityTons, 1.5);
      expect(restored.vehicleNumber, 'AP 39 AB 1234');
      expect(restored.specializations, profile().specializations);
      expect(restored.toDriverModel().isDemo, false);
    },
  );

  test(
    'Corrupt profile surfaces an error and preserves original data',
    () async {
      SharedPreferences.setMockInitialValues({
        LocalDriverRepository.profileKey: '{broken json',
      });
      await expectLater(
        LocalDriverRepository().getProfile(),
        throwsFormatException,
      );
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getString(LocalDriverRepository.profileKey),
        '{broken json',
      );
    },
  );

  testWidgets(
    'Register, persist, update dashboard, and return to farmer view',
    (tester) async {
      await tester.pumpWidget(const KolleruWheelsApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('driver-mode')));
      await tester.pumpAndSettle();
      expect(find.byType(DriverRegistrationScreen), findsOneWidget);
      for (final entry in {
        'driver-name': 'రమేష్ / Ramesh',
        'driver-phone': '9876543210',
        'driver-vehicle-number': 'ap 39 ab 1234',
        'driver-capacity': '1.5',
      }.entries) {
        final field = find.byKey(ValueKey(entry.key));
        await tester.ensureVisible(field);
        await tester.enterText(field, entry.value);
      }
      await tapVisible(
        tester,
        find.byKey(const ValueKey('register-vehicle-tataAce')),
      );
      await tapVisible(tester, find.byType(DropdownButtonFormField<String>));
      final pulaparru = find.text(
        '${KolleruVillages.find('pulaparru')!.label} (Mandavalli)',
      );
      await tester.scrollUntilVisible(
        pulaparru,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(pulaparru.last);
      await tester.pumpAndSettle();
      await tapVisible(
        tester,
        find.widgetWithText(FilterChip, AppStrings.specializationOptions[2]),
      );
      await tapVisible(tester, find.byKey(const ValueKey('register-driver')));
      for (final error in [
        AppStrings.nameRequired,
        AppStrings.phoneInvalid,
        AppStrings.numberInvalid,
        AppStrings.capacityInvalid,
        AppStrings.villageRequired,
        AppStrings.saveFailed,
      ]) {
        expect(find.text(error), findsNothing, reason: error);
      }
      expect(find.byType(DriverDashboardScreen), findsOneWidget);
      final registered = (await LocalDriverRepository().getProfile())!;
      expect(registered.name, 'రమేష్ / Ramesh');
      expect(registered.phone, '+919876543210');
      expect(registered.vehicleType, VehicleType.tataAce);
      expect(registered.vehicleNumber, 'AP 39 AB 1234');
      expect(registered.specializations, [AppStrings.specializationOptions[2]]);
      expect(registered.baseVillage.id, 'pulaparru');
      await tapVisible(
        tester,
        find.byKey(const ValueKey('driver-availability')),
      );
      expect(find.text(AppStrings.currentlyBusy), findsOneWidget);
      await tapVisible(tester, find.byKey(const ValueKey('current-spot')));
      await tester.tap(find.text(DriverSpots.hubs.first.label));
      await tester.pumpAndSettle();
      expect(
        (await LocalDriverRepository().getProfile())!.currentSpotVillage.id,
        'kaikaluru-town',
      );
      await tapVisible(
        tester,
        find.byKey(const ValueKey('dashboard-visiting-card')),
      );
      final card = tester.widget<VisitingCardScreen>(
        find.byType(VisitingCardScreen),
      );
      expect(card.driver.isAvailable, false);
      expect(card.driver.currentSpot, DriverSpots.hubs.first.label);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const ValueKey('farmer-view')));
      await tester.scrollUntilVisible(find.text('డ్రైవర్లు / Drivers: 7'), 300);
      expect(find.text('డ్రైవర్లు / Drivers: 7'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('driver-mode')));
      await tester.pumpAndSettle();
      expect(find.byType(DriverDashboardScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('డ్రైవర్లు / Drivers: 7'), 300);
      expect(find.text('డ్రైవర్లు / Drivers: 7'), findsOneWidget);
      // Restart the widget tree: Driver Mode must reopen the saved dashboard.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(const KolleruWheelsApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('driver-mode')));
      await tester.pumpAndSettle();
      expect(find.byType(DriverRegistrationScreen), findsNothing);
      expect(find.text(AppStrings.currentlyBusy), findsOneWidget);
      expect(find.text(DriverSpots.hubs.first.label), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Invalid registration does not create a profile', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: DriverModeScreen(repository: LocalDriverRepository()),
      ),
    );
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const ValueKey('register-driver')));
    expect(find.text(AppStrings.nameRequired), findsOneWidget);
    expect(find.text(AppStrings.phoneInvalid), findsOneWidget);
    expect(find.text(AppStrings.villageRequired), findsOneWidget);
    expect(await LocalDriverRepository().getProfile(), isNull);
  });

  testWidgets('Onboarding and dashboard support narrow screen and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: DriverModeScreen(repository: LocalDriverRepository()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('register-driver')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await LocalDriverRepository().saveProfile(profile());
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: DriverDashboardScreen(
          profile: profile(),
          repository: LocalDriverRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('farmer-view')),
      250,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('Stored JSON contains all required fields', () async {
    await LocalDriverRepository().saveProfile(profile());
    final preferences = await SharedPreferences.getInstance();
    final data = jsonDecode(
      preferences.getString(LocalDriverRepository.profileKey)!,
    ) as Map<String, dynamic>;
    expect(
      data.keys,
      containsAll([
        'id',
        'name',
        'phone',
        'baseVillage',
        'currentSpotVillage',
        'vehicleType',
        'capacityTons',
        'specializations',
        'vehicleNumber',
        'isAvailable',
      ]),
    );
  });

  testWidgets('Failed availability save keeps the previous state', (
    tester,
  ) async {
    await LocalDriverRepository().saveProfile(profile());
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: DriverDashboardScreen(
          profile: profile(),
          repository: FailingWritesRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const ValueKey('driver-availability')));
    expect(find.text(AppStrings.availableForLoads), findsOneWidget);
    expect(find.text(AppStrings.saveFailed), findsOneWidget);
    expect((await LocalDriverRepository().getProfile())!.isAvailable, true);
  });

  testWidgets('Profile load error retries without replacing stored data', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      LocalDriverRepository.profileKey: '{broken',
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: DriverModeScreen(repository: LocalDriverRepository()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.loadFailed), findsOneWidget);
    await LocalDriverRepository().saveProfile(profile());
    await tester.tap(find.text(AppStrings.retry));
    await tester.pumpAndSettle();
    expect(find.byType(DriverDashboardScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
