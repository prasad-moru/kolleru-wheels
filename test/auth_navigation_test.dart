import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kolleru_wheels/core/constants/app_strings.dart';
import 'package:kolleru_wheels/core/constants/villages.dart';
import 'package:kolleru_wheels/core/theme/app_theme.dart';
import 'package:kolleru_wheels/data/models/driver_model.dart';
import 'package:kolleru_wheels/data/models/local_driver_profile.dart';
import 'package:kolleru_wheels/data/models/user_profile_model.dart';
import 'package:kolleru_wheels/data/models/vehicle_type.dart';
import 'package:kolleru_wheels/data/repositories/auth_repository.dart';
import 'package:kolleru_wheels/data/repositories/local_driver_repository.dart';
import 'package:kolleru_wheels/data/repositories/supabase_driver_repository.dart';
import 'package:kolleru_wheels/presentation/auth/complete_profile_screen.dart';
import 'package:kolleru_wheels/presentation/auth/phone_otp_screen.dart';
import 'package:kolleru_wheels/presentation/auth/session_router.dart';
import 'package:kolleru_wheels/presentation/driver/driver_dashboard_screen.dart';
import 'package:kolleru_wheels/presentation/driver/driver_mode_screen.dart';
import 'package:kolleru_wheels/presentation/driver/driver_registration_screen.dart';
import 'package:kolleru_wheels/presentation/farmer/home_directory_screen.dart';
import 'package:kolleru_wheels/presentation/farmer/post_load_bottom_sheet.dart';

import 'onboarding_helpers.dart';

const owner = UserProfile(phone: '+919876543210', role: 'driver', name: 'Ramesh');

LocalDriverProfile savedDriver({String phone = '+919876543210'}) => LocalDriverProfile(
  id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  name: 'Ramesh',
  phone: phone,
  baseVillage: KolleruVillages.find('pulaparru')!,
  currentSpotVillage: KolleruVillages.find('kaikaluru-town')!,
  vehicleType: VehicleType.tataAce,
  capacityTons: 1.5,
  specializations: const ['Live Fish'],
  vehicleNumber: 'AP 39 AB 1234',
  isAvailable: false,
  cardStyle: 'gold_elite',
  avatarUrl: 'https://example.com/driver.jpg',
  isPhoneVerified: true,
);

class OwnedDrivers extends SupabaseDriverRepository {
  DriverModel? driver = savedDriver().toDriverModel();
  bool fail = false;
  final phones = <String>[];

  @override
  Future<DriverModel?> getOwnDriver(String phone) async {
    phones.add(phone);
    if (fail) throw StateError('Offline');
    return driver;
  }
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('A new device restores the busy driver and opens the dashboard', (tester) async {
    final drivers = OwnedDrivers();
    final auth = AuthRepository(mockMode: true, driverRepository: drivers)
      ..currentProfile = owner;
    addTearDown(auth.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: SessionRouter(repository: auth),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(DriverDashboardScreen), findsOneWidget);
    expect(find.byType(DriverRegistrationScreen), findsNothing);
    expect(drivers.phones, ['+919876543210']);
    final restored = (await LocalDriverRepository().getProfile())!;
    expect(restored.toJson(), savedDriver().toJson());
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('A failed owner lookup offers retry rather than registration', (tester) async {
    final drivers = OwnedDrivers()..fail = true;
    final auth = AuthRepository(mockMode: true, driverRepository: drivers)
      ..currentProfile = owner;
    addTearDown(auth.dispose);
    await tester.pumpWidget(MaterialApp(home: DriverModeScreen(
      authRepository: auth, repository: LocalDriverRepository(),
    )));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.loadFailed), findsOneWidget);
    expect(find.byType(DriverRegistrationScreen), findsNothing);
    drivers.fail = false;
    await tapVisible(tester, find.text(AppStrings.retry));
    expect(find.byType(DriverDashboardScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Only a confirmed missing driver needs vehicle registration', (tester) async {
    final drivers = OwnedDrivers()..driver = null;
    final auth = AuthRepository(mockMode: true, driverRepository: drivers)
      ..currentProfile = owner;
    addTearDown(auth.dispose);
    await tester.pumpWidget(MaterialApp(home: SessionRouter(repository: auth)));
    await tester.pumpAndSettle();
    expect(find.byType(DriverRegistrationScreen), findsOneWidget);
    expect(find.byType(DriverDashboardScreen), findsNothing);
    await tapVisible(tester, find.byKey(const ValueKey('onboarding-back')));
    expect(find.byType(HomeDirectoryScreen), findsOneWidget);
    expect(auth.isGuest, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  test('Another phone on the device is replaced by the signed-in driver', () async {
    final local = LocalDriverRepository();
    await local.saveProfile(savedDriver(phone: '+919999999999'));
    final drivers = OwnedDrivers();
    final auth = AuthRepository(mockMode: true, driverRepository: drivers)
      ..currentProfile = owner;
    addTearDown(auth.dispose);
    expect((await auth.restoreDriverProfile(localRepository: local))!.phone, owner.phone);
    expect(drivers.phones, [owner.phone]);
    expect((await local.getProfile())!.phone, owner.phone);
  });

  test('Registration preserves an existing driver instead of replacing vehicle details', () async {
    final drivers = OwnedDrivers();
    final auth = AuthRepository(mockMode: true, driverRepository: drivers);
    addTearDown(auth.dispose);
    await auth.signInWithOtp(phone: owner.phone, role: 'driver');
    await auth.verifyOTP(phone: owner.phone, token: '123456');
    await auth.completeRegistration(
      phone: owner.phone, name: 'Replacement', role: 'driver',
      villageId: 'pulaparru', driver: savedDriver().copyWith(cardStyle: 'aqua_marine'),
    );
    expect((await LocalDriverRepository().getProfile())!.toJson(), savedDriver().toJson());
    expect(auth.currentProfile?.role, 'driver');
  });

  for (final screen in ['phone', 'farmer', 'driver']) {
    for (final action in ['back', 'cancel', 'system-back']) {
      testWidgets('$screen onboarding $action clears identity and opens the guest directory', (tester) async {
        final auth = AuthRepository(mockMode: true);
        addTearDown(auth.dispose);
        await auth.signInWithOtp(phone: owner.phone, role: 'driver');
        await auth.verifyOTP(phone: owner.phone, token: '123456');
        final Widget form = switch (screen) {
          'phone' => PhoneOtpScreen(repository: auth, onVerified: (_) => fail('Cancelled draft published')),
          'farmer' => CompleteProfileScreen(phone: owner.phone, repository: auth),
          _ => DriverRegistrationScreen(
            repository: LocalDriverRepository(), authRepository: auth,
            verifiedPhone: owner.phone, completeUserProfile: true,
          ),
        };
        await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: form));
        await tester.pumpAndSettle();
        if (action == 'system-back') {
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
        } else {
          await tapVisible(tester, find.byKey(ValueKey(
            action == 'back' ? 'onboarding-back' : 'cancel-onboarding',
          )));
        }
        expect(auth.isGuest, isTrue);
        expect(auth.currentProfile, isNull);
        expect(auth.onboardingPhone, isNull);
        expect(auth.verifiedPhone, isNull);
        expect(await LocalDriverRepository().getProfile(), isNull);
        expect(find.byType(HomeDirectoryScreen), findsOneWidget);
        expect(find.byType(PhoneOtpScreen), findsNothing);
        expect(find.byType(DriverRegistrationScreen), findsNothing);
        final navigator = Navigator.of(tester.element(find.byType(HomeDirectoryScreen)));
        expect(navigator.canPop(), isFalse);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('Guest exit stays visible and posting returns to sign-in', (tester) async {
    final auth = AuthRepository(mockMode: true);
    addTearDown(auth.dispose);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light,
      home: SessionRouter(repository: auth)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('login-hero')), findsOneWidget);
    expect(find.text('+91'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('browse-guest')));
    await tester.pumpAndSettle();
    expect(find.byType(HomeDirectoryScreen), findsOneWidget);
    expect(auth.isGuest, isTrue);
    expect(auth.currentProfile, isNull);
    final postLoad = find.byKey(const ValueKey('post-urgent-load'));
    expect(postLoad, findsOneWidget);
    expect(find.text(AppStrings.signInToPost), findsOneWidget);
    await tapVisible(tester, postLoad);
    expect(find.byType(PhoneOtpScreen), findsOneWidget);
    expect(find.byType(HomeDirectoryScreen), findsNothing);
    expect(find.byType(PostLoadBottomSheet), findsNothing);
    expect(auth.isGuest, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Login supports a narrow viewport and enlarged text', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final auth = AuthRepository(mockMode: true);
    addTearDown(auth.dispose);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light,
      home: PhoneOtpScreen(repository: auth, onVerified: (_) {})));
    await tester.pumpAndSettle();
    final loginList = find.descendant(
      of: find.byType(PhoneOtpScreen),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );
    final phone = find.byKey(const ValueKey('auth-phone'));
    await revealInVerticalList(tester, phone, scrollable: loginList);
    expect(phone, findsOneWidget);
    expect(tester.takeException(), isNull);
    final guest = find.byKey(const ValueKey('browse-guest'));
    expect(tester.getRect(guest).bottom, lessThanOrEqualTo(800));
    await tester.tap(guest);
    await tester.pumpAndSettle();
    expect(find.byType(HomeDirectoryScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
