import 'package:kolleru_wheels/presentation/driver/load_pool_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kolleru_wheels/core/constants/villages.dart';
import 'package:kolleru_wheels/data/models/user_profile_model.dart';
import 'package:kolleru_wheels/data/models/local_driver_profile.dart';
import 'package:kolleru_wheels/data/models/vehicle_type.dart';
import 'package:kolleru_wheels/data/repositories/auth_repository.dart';
import 'package:kolleru_wheels/data/repositories/local_driver_repository.dart';
import 'package:kolleru_wheels/data/repositories/mock_directory_repository.dart';
import 'package:kolleru_wheels/presentation/auth/phone_otp_screen.dart';
import 'package:kolleru_wheels/presentation/driver/driver_dashboard_screen.dart';
import 'package:kolleru_wheels/presentation/driver/visiting_card_screen.dart';
import 'package:kolleru_wheels/presentation/farmer/home_directory_screen.dart';

Future<void> openDrawer(WidgetTester tester) async {
  tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
  await tester.pumpAndSettle();
}

class GatewayFailureAuth extends AuthRepository {
  GatewayFailureAuth() : super(mockMode: false);
  int requests = 0;
  String? phoneSent;
  @override
  Future<void> signInWithOtp({
    required String phone,
    required String role,
  }) async {
    requests++;
    phoneSent = AuthRepository.normalizePhone(phone);
    throw const AuthException('SMS gateway unavailable', statusCode: '400');
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('Farmer drawer has only own profile, posted loads and logout', (
    tester,
  ) async {
    final auth = AuthRepository(mockMode: true)
      ..currentProfile = const UserProfile(
        phone: '+919876543210',
        name: 'Farmer',
        role: 'shipper',
      );
    await tester.pumpWidget(
      MaterialApp(
        home: HomeDirectoryScreen(
          authRepository: auth,
          repository: MockDirectoryRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openDrawer(tester);
    expect(
      find.descendant(of: find.byType(Drawer), matching: find.byType(ListTile)),
      findsNWidgets(3),
    );
    expect(find.byKey(const ValueKey('farmer-profile')), findsOneWidget);
    expect(find.byKey(const ValueKey('my-posted-loads')), findsOneWidget);
    expect(find.byKey(const ValueKey('driver-mode')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('drawer-logout')));
    await tester.pumpAndSettle();
    expect(find.byType(PhoneOtpScreen), findsOneWidget);
    expect(find.byType(HomeDirectoryScreen), findsNothing);
    expect(find.byType(LoadPoolBoard), findsNothing);
  });
  testWidgets('Driver drawer has only own profile, card and logout', (
    tester,
  ) async {
    final village = KolleruVillages.find('pulaparru')!;
    final local = LocalDriverRepository();
    final driver = LocalDriverProfile(
      id: 'driver-test',
      name: 'Ramesh',
      phone: '+919876543210',
      baseVillage: village,
      currentSpotVillage: village,
      vehicleType: VehicleType.tataAce,
      capacityTons: 1,
      specializations: const [],
      vehicleNumber: 'AP 39 AB 1234',
      isAvailable: true,
    );
    await local.saveProfile(driver);
    final auth = AuthRepository(mockMode: true)
      ..currentProfile = const UserProfile(
        phone: '+919876543210',
        role: 'driver',
      );
    await tester.pumpWidget(
      MaterialApp(
        home: DriverDashboardScreen(
          profile: driver,
          repository: local,
          authRepository: auth,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openDrawer(tester);
    expect(
      find.descendant(of: find.byType(Drawer), matching: find.byType(ListTile)),
      findsNWidgets(3),
    );
    expect(find.byKey(const ValueKey('driver-profile')), findsOneWidget);
    expect(find.byKey(const ValueKey('farmer-view')), findsNothing);
    expect(find.byType(HomeDirectoryScreen), findsNothing);
    await tester.tap(find.byKey(const ValueKey('drawer-digital-card')));
    await tester.pumpAndSettle();
    expect(find.byType(VisitingCardScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Invalid phone never requests SMS; Auth 400 shows the Telugu snackbar',
    (tester) async {
      final auth = GatewayFailureAuth();
      await tester.pumpWidget(
        MaterialApp(
          home: PhoneOtpScreen(repository: auth, onVerified: (_) {}),
        ),
      );
      await tester.enterText(find.byKey(const ValueKey('auth-phone')), '12345');
      await tester.tap(find.byKey(const ValueKey('send-otp')));
      await tester.pumpAndSettle();
      expect(auth.requests, 0);
      expect(find.textContaining('Enter a valid 10-digit'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('auth-phone')),
        '+91 9876543210',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('send-otp')));
      await tester.tap(find.byKey(const ValueKey('send-otp')));
      await tester.pumpAndSettle();
      expect(auth.requests, 1);
      expect(auth.phoneSent, '+919876543210');
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(
            'SMS పంపడం విఫలమైంది. దయచేసి సరైన నెంబర్ సరిచూడండి లేదా టెస్ట్ నెంబర్ వాడండి.',
          ),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('auth-otp')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
