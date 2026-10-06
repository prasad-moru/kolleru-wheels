import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kolleru_wheels/core/constants/app_colors.dart';
import 'package:kolleru_wheels/core/constants/villages.dart';
import 'package:kolleru_wheels/data/models/user_profile_model.dart';
import 'package:kolleru_wheels/data/models/local_driver_profile.dart';
import 'package:kolleru_wheels/data/models/vehicle_type.dart';
import 'package:kolleru_wheels/data/repositories/auth_repository.dart';
import 'package:kolleru_wheels/data/repositories/local_driver_repository.dart';
import 'package:kolleru_wheels/data/repositories/mock_directory_repository.dart';
import 'package:kolleru_wheels/presentation/auth/phone_otp_screen.dart';
import 'package:kolleru_wheels/presentation/admin/admin_dashboard_screen.dart';
import 'package:kolleru_wheels/presentation/driver/driver_dashboard_screen.dart';
import 'package:kolleru_wheels/presentation/driver/visiting_card_screen.dart';
import 'package:kolleru_wheels/presentation/farmer/home_directory_screen.dart';
import 'package:kolleru_wheels/presentation/farmer/post_load_bottom_sheet.dart';

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
  final roleMenus = <String?, List<String>>{
    null: ['drawer-login'],
    'driver': [
      'drawer-driver-dashboard',
      'drawer-digital-card',
      'drawer-logout',
    ],
    'shipper': ['drawer-farmer-view', 'drawer-post-load', 'drawer-logout'],
    'admin': ['drawer-admin-monitor', 'drawer-logout'],
  };
  for (final role in roleMenus.keys) {
    testWidgets('${role ?? 'Guest'} drawer has only the expected actions', (
      tester,
    ) async {
      final auth = AuthRepository(mockMode: true);
      if (role != null) {
        auth.currentProfile = UserProfile(phone: '+919876543210', role: role);
      }
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
      final tiles = find.descendant(
        of: find.byType(Drawer),
        matching: find.byType(ListTile),
      );
      expect(tiles, findsNWidgets(roleMenus[role]!.length));
      for (final key in roleMenus[role]!) {
        expect(find.byKey(ValueKey(key)), findsOneWidget);
      }
      if (role == null) {
        await tester.tap(find.byKey(const ValueKey('drawer-login')));
        await tester.pumpAndSettle();
        expect(find.byType(PhoneOtpScreen), findsOneWidget);
      } else if (role == 'admin') {
        final tile = tester.widget<ListTile>(
          find.byKey(const ValueKey('drawer-admin-monitor')),
        );
        expect(tile.selectedTileColor, AppColors.green);
        expect(tile.selected, true);
        await tester.tap(find.byKey(const ValueKey('drawer-admin-monitor')));
        await tester.pumpAndSettle();
        expect(find.byType(AdminDashboardScreen), findsOneWidget);
      } else if (role == 'shipper') {
        await tester.tap(find.byKey(const ValueKey('drawer-post-load')));
        await tester.pumpAndSettle();
        expect(find.byType(PostLoadBottomSheet), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('Driver drawer opens the saved dashboard and own digital card', (
    tester,
  ) async {
    final local = LocalDriverRepository();
    final village = KolleruVillages.find('pulaparru')!;
    await local.saveProfile(
      LocalDriverProfile(
        id: 'local-test',
        name: 'Ramesh',
        phone: '+919876543210',
        baseVillage: village,
        currentSpotVillage: village,
        vehicleType: VehicleType.tataAce,
        capacityTons: 1,
        specializations: const [],
        vehicleNumber: 'AP 39 AB 1234',
        isAvailable: true,
      ),
    );
    final auth = AuthRepository(mockMode: true)
      ..currentProfile = const UserProfile(
        phone: '+919876543210',
        role: 'driver',
      );
    await tester.pumpWidget(
      MaterialApp(
        home: HomeDirectoryScreen(
          authRepository: auth,
          localDriverRepository: local,
          repository: MockDirectoryRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openDrawer(tester);
    await tester.tap(find.byKey(const ValueKey('drawer-driver-dashboard')));
    await tester.pumpAndSettle();
    expect(find.byType(DriverDashboardScreen), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    await openDrawer(tester);
    await tester.tap(find.byKey(const ValueKey('drawer-digital-card')));
    await tester.pumpAndSettle();
    expect(find.byType(VisitingCardScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Logout replaces role actions with the single guest login', (
    tester,
  ) async {
    final auth = AuthRepository(mockMode: true)
      ..currentProfile = const UserProfile(
        phone: '+919876543210',
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
    await tester.tap(find.byKey(const ValueKey('drawer-logout')));
    await tester.pumpAndSettle();
    await openDrawer(tester);
    expect(find.byKey(const ValueKey('drawer-login')), findsOneWidget);
    expect(find.byKey(const ValueKey('drawer-logout')), findsNothing);
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
