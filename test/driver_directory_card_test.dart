import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kolleru_wheels/core/constants/app_strings.dart';
import 'package:kolleru_wheels/core/theme/app_theme.dart';
import 'package:kolleru_wheels/core/theme/driver_card_style.dart';
import 'package:kolleru_wheels/data/models/driver_model.dart';
import 'package:kolleru_wheels/data/models/user_profile_model.dart';
import 'package:kolleru_wheels/data/repositories/auth_repository.dart';
import 'package:kolleru_wheels/data/repositories/mock_directory_repository.dart';
import 'package:kolleru_wheels/data/repositories/supabase_driver_repository.dart';
import 'package:kolleru_wheels/presentation/common/call_button.dart';
import 'package:kolleru_wheels/presentation/common/driver_directory_card.dart';
import 'package:kolleru_wheels/presentation/farmer/directory_states.dart';
import 'package:kolleru_wheels/presentation/farmer/home_directory_screen.dart';

class PendingDirectoryRepository extends SupabaseDriverRepository {
  final result = Completer<List<DriverModel>>();

  @override
  Future<List<DriverModel>> getAvailableDrivers() => result.future;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final palette in DriverCardStyle.styles) {
    testWidgets('${palette.label} uses its accent on a white directory card', (
      tester,
    ) async {
      final driver = MockDirectoryRepository().getDrivers().first.copyWith(
        cardStyle: palette.id,
      );
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: DriverDirectoryCard(
              driver: driver,
              onOpen: () {},
              onWhatsApp: () {},
            ),
          ),
        ),
      ));
      final strip = tester.widget<Container>(
        find.byKey(ValueKey('style-strip-${driver.id}')),
      );
      expect(strip.color, palette.accent);
      final material = tester.widget<Material>(
        find.descendant(
          of: find.byType(DriverDirectoryCard),
          matching: find.byType(Material),
        ).first,
      );
      expect(material.color, Colors.white);
      expect(find.text(driver.name), findsOneWidget);
      expect(find.byKey(ValueKey('availability-${driver.id}')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Directory contacts preserve identity and separate callbacks', (
    tester,
  ) async {
    final driver = SupabaseDriverRepository.fromRow(
      SupabaseDriverRepository.toRow(
        DriverModel(
          id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          name: 'రమేష్ / Ramesh',
          phone: '+919876543210',
          village: MockDirectoryRepository().getDrivers().first.village,
          currentSpot: 'Kaikaluru Adda',
          vehicleType: MockDirectoryRepository().getDrivers().first.vehicleType,
          capacity: '1.5 Tons',
          capacityTons: 1.5,
          isAvailable: true,
          vehicleNumber: 'AP 39 AB 1234',
          specializations: const ['Live Fish'],
        ),
        DateTime.utc(2026, 10, 12),
      ),
    );
    var opened = 0;
    var chats = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: DriverDirectoryCard(
            driver: driver,
            callerPhone: '+919999999999',
            onOpen: () => opened++,
            onWhatsApp: () => chats++,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final call = tester.widget<CallButton>(find.byType(CallButton));
    expect(call.phone, driver.phone);
    expect(call.callerPhone, '+919999999999');
    expect(call.callerRole, 'shipper');
    expect(call.contextNote, 'directory:${driver.id}');
    expect(find.byIcon(Icons.verified), findsOneWidget);
    await tester.tap(find.text(driver.name));
    expect(opened, 1);
    final whatsapp = find.byKey(ValueKey('whatsapp-${driver.id}'));
    await tester.ensureVisible(whatsapp);
    await tester.tap(whatsapp);
    expect(chats, 1);
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Directory card fits at 320px with double text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: DriverDirectoryCard(
            driver: MockDirectoryRepository().getDrivers().first,
            onOpen: () {},
            onWhatsApp: () {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(AppStrings.whatsapp));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Initial fetch shows skeletons and settles into directory cards', (
    tester,
  ) async {
    final remote = PendingDirectoryRepository();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: HomeDirectoryScreen(
        repository: MockDirectoryRepository(),
        remoteDriverRepository: remote,
        authRepository: AuthRepository(mockMode: true)
          ..currentProfile = const UserProfile(
            phone: '+919999999999',
            role: 'shipper',
          ),
      ),
    ));
    await tester.scrollUntilVisible(
      find.byType(DirectoryLoadingState),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(DirectoryLoadingState), findsOneWidget);
    expect(find.byType(DriverDirectoryCard), findsNothing);
    remote.result.complete(MockDirectoryRepository().getDrivers(availableOnly: true));
    await tester.pumpAndSettle();
    expect(find.byType(DirectoryLoadingState), findsNothing);
    expect(find.byType(DriverDirectoryCard), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Empty locality offers a working filter reset', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: HomeDirectoryScreen(
        repository: MockDirectoryRepository(),
        authRepository: AuthRepository(mockMode: true)
          ..currentProfile = const UserProfile(
            phone: '+919999999999',
            role: 'shipper',
          ),
      ),
    ));
    await tester.pumpAndSettle();
    final akividu = find.byKey(const ValueKey('mandal-akividu'));
    await tester.ensureVisible(akividu);
    await tester.tap(akividu);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byType(DirectoryEmptyState),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    final resetFinder = find.text(AppStrings.reset);
    await tester.ensureVisible(resetFinder);
    await tester.pumpAndSettle();
    await tester.tap(resetFinder);
    await tester.pumpAndSettle();
    expect(find.byType(DirectoryEmptyState), findsNothing);
    expect(find.byType(DriverDirectoryCard), findsWidgets);
    expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('mandal-all'))).selected, isTrue);
    expect(tester.takeException(), isNull);
  });
}
