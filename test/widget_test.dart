import 'package:kolleru_wheels/data/repositories/auth_repository.dart';
import 'package:kolleru_wheels/data/models/user_profile_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kolleru_wheels/main.dart';
import 'package:kolleru_wheels/core/constants/villages.dart';
import 'package:kolleru_wheels/core/constants/app_strings.dart';
import 'package:kolleru_wheels/data/models/vehicle_type.dart';
import 'package:kolleru_wheels/data/repositories/mock_directory_repository.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'Selected village displays available drivers in three proximity sections',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'directory_village_id': 'kovvadalanka',
      });
      await tester.pumpWidget(
        KolleruWheelsApp(
          authRepository: AuthRepository(mockMode: true)
            ..currentProfile = const UserProfile(
              phone: '+919876543210',
              role: 'shipper',
            ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text(AppStrings.tierLocal), 200);
      expect(find.text(AppStrings.tierLocal), findsOneWidget);
      await tester.scrollUntilVisible(find.text(AppStrings.tierMandal), 200);
      expect(find.text(AppStrings.tierMandal), findsOneWidget);
      await tester.scrollUntilVisible(find.text(AppStrings.tierDelta), 200);
      expect(find.text(AppStrings.tierDelta), findsOneWidget);
      expect(find.text(AppStrings.busyDrivers), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  test('Unique villages and driver filtering', () {
    expect(KolleruVillages.all.length, 26);
    expect(KolleruVillages.all.map((v) => v.id).toSet().length, 26);
    final repo = MockDirectoryRepository();
    expect(repo.getDrivers().length, 6);
    expect(repo.getDrivers(villageId: 'pulaparru').length, 2);
    expect(repo.getDrivers(availableOnly: true).length, 4);
    expect(
      repo
          .getDrivers(
            vehicleType: VehicleType.boleroPickup,
            availableOnly: true,
          )
          .single
          .village
          .id,
      'pulaparru',
    );
    expect(repo.getDrivers(villageId: 'atapaka'), isEmpty);
  });
  testWidgets('Filter and open visiting card', (tester) async {
    await tester.pumpWidget(
      KolleruWheelsApp(
        authRepository: AuthRepository(mockMode: true)
          ..currentProfile = const UserProfile(
            phone: '+919876543210',
            role: 'shipper',
          ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Kolleru Wheels'), findsOneWidget);
    await tester.ensureVisible(
      find.widgetWithText(OutlinedButton, VehicleType.boleroPickup.label),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(OutlinedButton, VehicleType.boleroPickup.label),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('డ్రైవర్లు / Drivers: 1'), 250);
    expect(find.text('డ్రైవర్లు / Drivers: 1'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('రమేష్ / Ramesh'), 150);
    await tester.ensureVisible(find.text('రమేష్ / Ramesh'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('రమేష్ / Ramesh'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.call), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Narrow display and large text', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      KolleruWheelsApp(
        authRepository: AuthRepository(mockMode: true)
          ..currentProfile = const UserProfile(
            phone: '+919876543210',
            role: 'shipper',
          ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
