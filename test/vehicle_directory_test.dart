import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kolleru_wheels/core/constants/villages.dart';
import 'package:kolleru_wheels/core/theme/app_theme.dart';
import 'package:kolleru_wheels/data/models/driver_model.dart';
import 'package:kolleru_wheels/data/models/user_profile_model.dart';
import 'package:kolleru_wheels/data/models/vehicle_type.dart';
import 'package:kolleru_wheels/data/repositories/auth_repository.dart';
import 'package:kolleru_wheels/data/repositories/mock_directory_repository.dart';
import 'package:kolleru_wheels/data/repositories/supabase_driver_repository.dart';
import 'package:kolleru_wheels/data/repositories/telemetry_repository.dart';
import 'package:kolleru_wheels/presentation/common/call_button.dart';
import 'package:kolleru_wheels/presentation/common/driver_directory_card.dart';
import 'package:kolleru_wheels/presentation/farmer/directory_states.dart';
import 'package:kolleru_wheels/presentation/farmer/home_directory_screen.dart';

DriverModel driver(String id, VehicleType type, String village) => DriverModel(
  id: id,
  name: 'రమేష్ / Ramesh',
  phone: '+919876543210',
  village: KolleruVillages.find(village)!,
  currentSpot: village,
  currentSpotVillageId: village,
  vehicleType: type,
  capacity: '2.5 Tons',
  capacityTons: 2.5,
  isAvailable: true,
  isPhoneVerified: true,
  vehicleNumber: 'AP 37 TX 1234',
);

class TestDirectory implements DirectoryRepository {
  final drivers = [
    driver('bolero', VehicleType.boleroPickup, 'pulaparru'),
    driver('709', VehicleType.miniTruck709, 'akividu-town'),
    driver('tipper', VehicleType.tipper, 'bhimavaram-town'),
  ];
  @override
  List<DriverModel> getDrivers({
    String? villageId,
    VehicleType? vehicleType,
    bool availableOnly = false,
  }) => drivers
      .where(
        (d) =>
            (villageId == null || d.village.id == villageId) &&
            (vehicleType == null || d.vehicleType == vehicleType) &&
            (!availableOnly || d.isAvailable),
      )
      .toList();
}

class EmptyLiveDirectory extends SupabaseDriverRepository {
  @override
  Future<List<DriverModel>> getAvailableDrivers() async => [];
}

class CountingTelemetry extends TelemetryRepository {
  int calls = 0;
  @override
  Future<void> logCallIntent({
    String? callerPhone,
    required String receiverPhone,
    String? callerRole,
    String contextNote = 'directory',
  }) async {
    calls++;
  }
}

Finder get feed => find
    .descendant(
      of: find.byKey(const ValueKey('directory-list')),
      matching: find.byType(Scrollable),
    )
    .first;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<AuthRepository> showDirectory(
    WidgetTester tester, {
    bool guest = false,
    SupabaseDriverRepository? remote,
    AuthRepository? authRepository,
  }) async {
    final auth = authRepository ?? AuthRepository(mockMode: true);
    addTearDown(auth.dispose);
    if (guest) {
      await auth.browseAsGuest();
    } else {
      auth.currentProfile = const UserProfile(
        phone: '+919999999999',
        role: 'shipper',
        name: 'Farmer',
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomeDirectoryScreen(
          repository: TestDirectory(),
          authRepository: auth,
          remoteDriverRepository: remote,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return auth;
  }

  testWidgets(
    'Locality and vehicle chips filter exact vehicle types and reset',
    (tester) async {
      await showDirectory(tester);
      final bhimavaram = find.byKey(const ValueKey('mandal-bhimavaram'));
      await tester.ensureVisible(bhimavaram);
      await tester.tap(bhimavaram);
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(bhimavaram).selected, isTrue);
      expect(
        tester
            .widget<DriverDirectoryCard>(find.byType(DriverDirectoryCard).first)
            .driver
            .id,
        'tipper',
      );
      final tipper = find.byKey(const ValueKey('vehicle-tipper'));
      await tester.ensureVisible(tipper);
      await tester.tap(tipper);
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(tipper).selected, isTrue);
      expect(
        find.byKey(const ValueKey('directory-driver-tipper')),
        findsOneWidget,
      );
      await tester.tap(tipper);
      final all = find.byKey(const ValueKey('mandal-all'));
      await tester.ensureVisible(all);
      await tester.tap(all);
      final truck = find.byKey(const ValueKey('vehicle-miniTruck709'));
      await tester.ensureVisible(truck);
      await tester.tap(truck);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('directory-driver-709')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('directory-driver-bolero')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'Directory copy and card details switch globally without bilingual text',
    (tester) async {
      await showDirectory(tester);
      expect(find.text('వాహనాల డైరెక్టరీ'), findsOneWidget);
      expect(find.textContaining(' / '), findsNothing);
      expect(find.text('2.5 టన్నులు'), findsWidgets);
      expect(find.byIcon(Icons.verified), findsWidgets);
      expect(find.text('AP 37 TX 1234'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('language-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('Vehicle Directory'), findsOneWidget);
      expect(find.text('2.5 Tons'), findsWidgets);
      expect(find.text('కాల్ చేయండి'), findsNothing);
      expect(find.text('Call'), findsWidgets);
      expect(find.textContaining(' / '), findsNothing);
      expect(find.text('వాహనాల డైరెక్టరీ'), findsNothing);
    },
  );

  for (final action in ['call', 'whatsapp']) {
    testWidgets('Guest $action opens a dismissible connect gate', (
      tester,
    ) async {
      final auth = await showDirectory(tester, guest: true);
      final target = action == 'call'
          ? find.descendant(
              of: find.byKey(const ValueKey('call-bolero')),
              matching: find.byType(FilledButton),
            )
          : find.byKey(const ValueKey('whatsapp-bolero'));
      await tester.scrollUntilVisible(target, 100, scrollable: feed);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('connect-gate')), findsOneWidget);
      expect(auth.isGuest, isTrue);
      await tester.enterText(
        find.byKey(const ValueKey('connect-phone')),
        '9876543210',
      );
      await tester.tap(find.byKey(const ValueKey('connect-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('connect-otp')), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('connect-gate')), findsNothing);
      expect(auth.isGuest, isTrue);
    });
  }

  testWidgets('Search narrows the feed by registration number and clears', (
    tester,
  ) async {
    await showDirectory(tester);
    await tester.tap(find.byKey(const ValueKey('directory-search')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('directory-search-field')),
      'no-match',
    );
    await tester.pumpAndSettle();
    expect(find.byType(DirectoryEmptyState), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('directory-search-field')),
      'AP 37 TX 1234',
    );
    await tester.pumpAndSettle();
    expect(find.byType(DirectoryEmptyState), findsNothing);
    expect(find.byType(DriverDirectoryCard), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('directory-search')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('directory-search-field')), findsNothing);
  });

  testWidgets(
    'Guest verification allows the pending contact for an existing shipper',
    (tester) async {
      var now = DateTime.utc(2026, 10, 26);
      final auth = await showDirectory(
        tester,
        guest: true,
        authRepository: AuthRepository(mockMode: true, now: () => now),
      );
      await auth.signInWithOtp(phone: '9876543210', role: 'shipper');
      await auth.verifyOTP(phone: '9876543210', token: '123456');
      await auth.createUserProfile(
        phone: '9876543210',
        name: 'Farmer',
        role: 'shipper',
      );
      await auth.browseAsGuest();
      now = now.add(const Duration(seconds: 61));
      await tester.pumpAndSettle();
      final call = tester.widget<CallButton>(
        find.byKey(const ValueKey('call-bolero')),
      );
      final allowed = call.beforeCall!();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('connect-phone')),
        '9876543210',
      );
      await tester.tap(find.byKey(const ValueKey('connect-submit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('connect-otp')),
        '123456',
      );
      await tester.tap(find.byKey(const ValueKey('connect-submit')));
      await tester.pumpAndSettle();
      expect(await allowed, isTrue);
      expect(auth.isGuest, isFalse);
      expect(auth.currentProfile!.role, 'shipper');
    },
  );

  testWidgets('Navigation switches to real history and profile views', (
    tester,
  ) async {
    final auth = await showDirectory(tester);
    await tester.tap(find.byKey(const ValueKey('nav-call-history')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('directory-call-history')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('nav-profile')));
    await tester.pumpAndSettle();
    expect(find.text(auth.currentProfile!.phone), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nav-vehicles')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('directory-list')), findsOneWidget);
  });

  testWidgets(
    'Successful empty live fetch does not substitute demonstration drivers',
    (tester) async {
      await showDirectory(tester, remote: EmptyLiveDirectory());
      expect(find.byType(DirectoryEmptyState), findsOneWidget);
      expect(find.byType(DriverDirectoryCard), findsNothing);
    },
  );

  testWidgets(
    'Contact guard blocks the launcher and telemetry until approved',
    (tester) async {
      final telemetry = CountingTelemetry();
      var allowed = false;
      var launches = 0;
      var recorded = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CallButton(
              phone: '+919876543210',
              beforeCall: () async => allowed,
              launcher: (_) async {
                launches++;
                return true;
              },
              telemetryRepository: telemetry,
              onCallLaunched: () => recorded++,
            ),
          ),
        ),
      );
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(launches, 0);
      expect(telemetry.calls, 0);
      allowed = true;
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(launches, 1);
      expect(telemetry.calls, 1);
      expect(recorded, 1);
    },
  );

  testWidgets('Directory fits 320px at double text size in both languages', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await showDirectory(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('language-toggle')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Vehicle Directory'), findsOneWidget);
  });
}
