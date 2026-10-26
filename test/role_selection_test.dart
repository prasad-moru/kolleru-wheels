import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kolleru_wheels/core/theme/app_theme.dart';
import 'package:kolleru_wheels/data/models/local_driver_profile.dart';
import 'package:kolleru_wheels/data/models/driver_verification.dart';
import 'package:kolleru_wheels/data/models/user_profile_model.dart';
import 'package:kolleru_wheels/data/models/vehicle_type.dart';
import 'package:kolleru_wheels/data/repositories/auth_repository.dart';
import 'package:kolleru_wheels/data/repositories/local_driver_repository.dart';
import 'package:kolleru_wheels/data/repositories/supabase_driver_repository.dart';
import 'package:kolleru_wheels/presentation/auth/role_selection_screen.dart';
import 'package:kolleru_wheels/presentation/auth/session_router.dart';
import 'package:kolleru_wheels/presentation/driver/driver_dashboard_screen.dart';
import 'package:kolleru_wheels/presentation/farmer/home_directory_screen.dart';

class ControlledAuth extends AuthRepository {
  ControlledAuth() : super(mockMode: true);
  Completer<void>? pending;
  final submittedDrivers = <LocalDriverProfile?>[];
  @override
  Future<UserProfile> completeRegistration({
    required String phone,
    required String name,
    required String role,
    required String villageId,
    String? baseLocation,
    LocalDriverProfile? driver,
    Uint8List? avatarBytes,
  }) async {
    submittedDrivers.add(driver);
    await pending?.future;
    return super.completeRegistration(
      phone: phone,
      name: name,
      role: role,
      villageId: villageId,
      baseLocation: baseLocation,
      driver: driver,
      avatarBytes: avatarBytes,
    );
  }
}

Finder get registrationScroll => find
    .descendant(
      of: find.byKey(const ValueKey('registration-scroll')),
      matching: find.byType(Scrollable),
    )
    .first;
Future<void> reveal(WidgetTester tester, String key) async {
  tester.state<ScrollableState>(registrationScroll).position.jumpTo(0);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byKey(ValueKey(key)),
    150,
    scrollable: registrationScroll,
  );
  await tester.pumpAndSettle();
}

Future<void> enter(WidgetTester tester, String key, String text) async {
  await reveal(tester, key);
  await tester.enterText(find.byKey(ValueKey(key)), text);
}

Future<void> chooseMandal(WidgetTester tester, String id) async {
  await reveal(tester, 'mandal-dropdown');
  await tester.tap(find.byKey(const ValueKey('mandal-dropdown')));
  await tester.pumpAndSettle();
  await tester.tap(
    find
        .descendant(
          of: find.byKey(ValueKey('mandal-option-$id')).last,
          matching: find.byType(Text),
        )
        .last,
  );
  await tester.pumpAndSettle();
}

Future<void> completeFields(WidgetTester tester) async {
  await enter(tester, 'name-input-field', 'Murthy Raju');
  await chooseMandal(tester, 'akividu');
  await enter(tester, 'village-input-field', 'Siddhapuram');
}

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'selected_language': 'english',
    }),
  );

  Future<AuthRepository> showRegistration(
    WidgetTester tester, {
    bool verified = true,
    AuthRepository? repository,
  }) async {
    final auth = repository ?? AuthRepository(mockMode: true);
    addTearDown(auth.dispose);
    if (verified) {
      await auth.signInWithOtp(phone: '9876543210', role: 'shipper');
      await auth.verifyOTP(phone: '9876543210', token: '123456');
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: RoleSelectionScreen(phone: '+919876543210', repository: auth),
      ),
    );
    await tester.pumpAndSettle();
    return auth;
  }

  testWidgets(
    'Role switching reveals vehicle fields and preserves the typed draft',
    (tester) async {
      await showRegistration(tester);
      expect(find.byKey(const ValueKey('vehicle-type-selector')), findsNothing);
      await completeFields(tester);
      await reveal(tester, 'role-card-driver');
      await tester.tap(find.byKey(const ValueKey('role-card-driver')));
      await tester.pumpAndSettle();
      await enter(tester, 'vehicle-number-field', 'AP 37 TX 1234');
      await reveal(tester, 'registration-vehicle-miniTruck709');
      await tester.tap(
        find.byKey(const ValueKey('registration-vehicle-miniTruck709')),
      );
      await reveal(tester, 'role-card-farmer');
      await tester.tap(find.byKey(const ValueKey('role-card-farmer')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('vehicle-type-selector')), findsNothing);
      await reveal(tester, 'name-input-field');
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('name-input-field')),
            )
            .controller!
            .text,
        'Murthy Raju',
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('village-input-field')),
            )
            .controller!
            .text,
        'Siddhapuram',
      );
      await reveal(tester, 'role-card-driver');
      await tester.tap(find.byKey(const ValueKey('role-card-driver')));
      await tester.pumpAndSettle();
      await reveal(tester, 'vehicle-number-field');
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('vehicle-number-field')),
            )
            .controller!
            .text,
        'AP 37 TX 1234',
      );
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(const ValueKey('registration-vehicle-miniTruck709')),
            )
            .selected,
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Required fields and driver registration number validate before saving',
    (tester) async {
      final auth = await showRegistration(tester);
      await reveal(tester, 'complete-registration-button');
      await tester.tap(
        find.byKey(const ValueKey('complete-registration-button')),
      );
      await tester.pumpAndSettle();
      await reveal(tester, 'name-input-field');
      expect(find.text('Enter a name (2–80 characters)'), findsOneWidget);
      expect(find.text('Choose your mandal'), findsOneWidget);
      expect(
        find.text('Enter your village or base (2–80 characters)'),
        findsOneWidget,
      );
      expect(auth.currentProfile, isNull);
      await completeFields(tester);
      await reveal(tester, 'role-card-driver');
      await tester.tap(find.byKey(const ValueKey('role-card-driver')));
      await tester.pumpAndSettle();
      await enter(tester, 'vehicle-number-field', '1234');
      await reveal(tester, 'complete-registration-button');
      await tester.tap(
        find.byKey(const ValueKey('complete-registration-button')),
      );
      await tester.pumpAndSettle();
      await reveal(tester, 'vehicle-number-field');
      expect(
        find.text('Enter a valid vehicle registration number'),
        findsOneWidget,
      );
      expect(await LocalDriverRepository().getProfile(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Verified mobile is display-only and localization preserves values and errors',
    (tester) async {
      await showRegistration(tester);
      await completeFields(tester);
      expect(find.byKey(const ValueKey('auth-phone')), findsNothing);
      expect(find.text('Verified ✓'), findsOneWidget);
      await enter(tester, 'name-input-field', '');
      await reveal(tester, 'complete-registration-button');
      await tester.tap(
        find.byKey(const ValueKey('complete-registration-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('language-toggle')));
      await tester.pumpAndSettle();
      await reveal(tester, 'name-input-field');
      expect(find.text('పేరు ఇవ్వండి (2–80 అక్షరాలు)'), findsOneWidget);
      expect(find.text('ధృవీకరించబడింది ✓'), findsOneWidget);
      expect(find.text('Kolleru Wheels Registration'), findsNothing);
      expect(find.textContaining(' / '), findsNothing);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('village-input-field')),
            )
            .controller!
            .text,
        'Siddhapuram',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Unverified callers cannot claim a verified badge or publish a profile',
    (tester) async {
      final auth = await showRegistration(tester, verified: false);
      await completeFields(tester);
      expect(find.text('Verified ✓'), findsNothing);
      expect(find.text('Verification required'), findsOneWidget);
      await reveal(tester, 'complete-registration-button');
      await tester.tap(
        find.byKey(const ValueKey('complete-registration-button')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Verify your mobile number before registering.'),
        findsOneWidget,
      );
      expect(auth.currentProfile, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Shipper completion retains a free-text base and hands off to the directory',
    (tester) async {
      final auth = await showRegistration(tester);
      await completeFields(tester);
      await reveal(tester, 'complete-registration-button');
      await tester.tap(
        find.byKey(const ValueKey('complete-registration-button')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(HomeDirectoryScreen), findsOneWidget);
      expect(auth.currentProfile!.role, 'shipper');
      expect(auth.currentProfile!.villageId, 'akividu-town');
      expect(auth.currentProfile!.baseLocation, 'Siddhapuram');
      expect(await LocalDriverRepository().getProfile(), isNull);
      final restored = AuthRepository(mockMode: true);
      addTearDown(restored.dispose);
      expect((await restored.restoreSession())!.baseLocation, 'Siddhapuram');
      expect(
        Navigator.of(tester.element(find.byType(HomeDirectoryScreen))).canPop(),
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Driver completion persists the chosen vehicle and base before the cockpit',
    (tester) async {
      final auth = await showRegistration(tester);
      await completeFields(tester);
      await reveal(tester, 'role-card-driver');
      await tester.tap(find.byKey(const ValueKey('role-card-driver')));
      await tester.pumpAndSettle();
      await reveal(tester, 'registration-vehicle-miniTruck709');
      await tester.tap(
        find.byKey(const ValueKey('registration-vehicle-miniTruck709')),
      );
      await enter(tester, 'vehicle-number-field', 'ap 37 tx 1234');
      await reveal(tester, 'complete-registration-button');
      await tester.tap(
        find.byKey(const ValueKey('complete-registration-button')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DriverDashboardScreen), findsOneWidget);
      expect(auth.currentProfile!.role, 'driver');
      var local = (await LocalDriverRepository().getProfile())!;
      expect(local.vehicleType, VehicleType.miniTruck709);
      expect(local.capacityTons, 5);
      expect(local.verification, DriverVerification.pending);
      expect(local.toDriverModel().isPubliclyAvailable, isFalse);
      expect(find.text('Awaiting admin approval'), findsOneWidget);
      expect(local.vehicleNumber, 'AP 37 TX 1234');
      expect(local.baseLocation, 'Siddhapuram');
      await LocalDriverRepository().updateAvailability(false);
      local = (await LocalDriverRepository().getProfile())!;
      final row = SupabaseDriverRepository.toRow(
        local.toDriverModel(),
        DateTime.utc(2026, 10, 26),
      );
      expect(SupabaseDriverRepository.fromRow(row).baseLocation, 'Siddhapuram');
      expect(local.baseVillage.id, 'akividu-town');
      expect(
        Navigator.of(tester.element(find.byType(DriverDashboardScreen)))
            .canPop(),
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'A failed save retains the draft and retry identity while blocking duplicate submissions',
    (tester) async {
      final auth = ControlledAuth();
      await showRegistration(tester, repository: auth);
      await completeFields(tester);
      await reveal(tester, 'role-card-driver');
      await tester.tap(find.byKey(const ValueKey('role-card-driver')));
      await tester.pumpAndSettle();
      await enter(tester, 'vehicle-number-field', 'AP 37 TX 1234');
      auth.pending = Completer<void>();
      await reveal(tester, 'complete-registration-button');
      await tester.tap(
        find.byKey(const ValueKey('complete-registration-button')),
      );
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('complete-registration-button')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('language-toggle')),
            )
            .onPressed,
        isNull,
      );
      auth.pending!.completeError(StateError('Offline'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not save registration. Please retry.'),
        findsOneWidget,
      );
      expect(auth.currentProfile, isNull);
      auth.pending = null;
      await tester.tap(
        find.byKey(const ValueKey('complete-registration-button')),
      );
      await tester.pumpAndSettle();
      expect(auth.submittedDrivers.length, 2);
      expect(auth.submittedDrivers.first!.id, auth.submittedDrivers.last!.id);
      expect(find.byType(DriverDashboardScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('A verified onboarding draft resumes directly on Screen 04', (
    tester,
  ) async {
    final first = AuthRepository(mockMode: true);
    await first.signInWithOtp(phone: '9876543210', role: 'shipper');
    await first.verifyOTP(phone: '9876543210', token: '123456');
    first.dispose();
    final restarted = AuthRepository(mockMode: true);
    addTearDown(restarted.dispose);
    await tester.pumpWidget(
      MaterialApp(home: SessionRouter(repository: restarted)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(RoleSelectionScreen), findsOneWidget);
    await reveal(tester, 'name-input-field');
    expect(find.text('Verified ✓'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Registration supports 320px and doubled text in both languages',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await showRegistration(tester);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('language-toggle')));
      await tester.pumpAndSettle();
      await reveal(tester, 'role-card-driver');
      await tester.tap(find.byKey(const ValueKey('role-card-driver')));
      await tester.pumpAndSettle();
      await reveal(tester, 'vehicle-number-field');
      expect(tester.takeException(), isNull);
      await reveal(tester, 'complete-registration-button');
      expect(tester.takeException(), isNull);
      expect(find.textContaining(' / '), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
