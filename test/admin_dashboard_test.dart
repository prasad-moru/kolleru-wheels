import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kolleru_wheels/data/models/admin_analytics_model.dart';
import 'package:kolleru_wheels/data/models/user_profile_model.dart';
import 'package:kolleru_wheels/data/repositories/admin_analytics_repository.dart';
import 'package:kolleru_wheels/data/repositories/auth_repository.dart';
import 'package:kolleru_wheels/presentation/admin/admin_dashboard_screen.dart';
import 'package:kolleru_wheels/presentation/auth/session_router.dart';

final _now = DateTime.utc(2026, 10, 12, 6);

AdminAnalyticsModel _sample() => AdminAnalyticsModel.aggregate(
  profiles: [
    {'phone': '+918523123498', 'role': 'shipper', 'village_id': 'pulaparru'},
    {'phone': '+919876543210', 'role': 'driver', 'village_id': 'kovvadalanka'},
    {'phone': '+919111111111', 'role': 'admin', 'village_id': null},
  ],
  drivers: [
    {'base_village_id': 'kovvadalanka', 'is_available': true},
    {'base_village_id': 'pulaparru', 'is_available': false},
  ],
  callsToday: [
    {'caller_phone': '+918523123498'},
    {'caller_phone': '+918523123498'},
    {'caller_phone': null},
  ],
  recentTelemetry: [
    {
      'created_at': '2026-10-12T05:50:00Z',
      'caller_role': 'shipper',
      'caller_phone': '+918523123498',
      'receiver_phone': '+919876543210',
      'context_note': 'visiting_card:driver-1',
    },
  ],
  loads: [
    {
      'id': 'live-1',
      'from_location': 'Pulaparru Market',
      'to_village_id': 'kovvadalanka',
      'material_type': 'Live Fish',
      'poster_phone': '+918523123498',
      'created_at': '2026-10-12T05:55:00Z',
      'is_closed': false,
    },
    {
      'id': 'expired',
      'from_location': 'Old Market',
      'to_village_id': 'kovvadalanka',
      'material_type': 'Paddy',
      'poster_phone': '+918523123498',
      'created_at': '2026-10-12T05:20:00Z',
      'is_closed': false,
    },
    {
      'id': 'closed',
      'from_location': 'Market',
      'to_village_id': 'kovvadalanka',
      'material_type': 'Cement',
      'poster_phone': '+918523123498',
      'created_at': '2026-10-12T05:55:00Z',
      'is_closed': true,
    },
  ],
  now: _now,
);

class _FakeAdminAnalyticsRepository extends AdminAnalyticsRepository {
  _FakeAdminAnalyticsRepository(this.model);
  final AdminAnalyticsModel model;
  @override
  Future<AdminAnalyticsModel> fetchSnapshot(AuthRepository auth) async => model;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('aggregates totals, mandal density, call counts and active loads', () {
    final analytics = _sample();
    expect(analytics.totalUsers, 3);
    expect(analytics.activeFarmers, 1);
    expect(analytics.registeredDrivers, 2);
    expect(analytics.activeDrivers, 1);
    expect(analytics.callsPlacedToday, 3);
    expect(analytics.activeLoads, 1);
    final mandavalli = analytics.mandals.singleWhere(
      (item) => item.id == 'mandavalli',
    );
    expect(mandavalli.farmerCount, 1);
    expect(mandavalli.callTally, 2);
    expect(analytics.liveLoads.single.category, 'Live Fish');
  });

  test('masks caller and receiver phone numbers in the audit model', () {
    final call = _sample().recentCalls.single;
    expect(call.callerPhone, '+91 8523***498');
    expect(call.receiverPhone, '+91 9876***210');
    expect(AdminAnalyticsModel.maskPhone(null), 'Guest');
  });

  testWidgets('SessionRouter opens the command hub only for an admin', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = AuthRepository(mockMode: true)
      ..currentProfile = const UserProfile(
        phone: '+919111111111',
        role: 'admin',
        name: 'Operations',
      );
    await tester.pumpWidget(
      MaterialApp(
        home: SessionRouter(
          repository: auth,
          adminAnalyticsRepository: _FakeAdminAnalyticsRepository(_sample()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AdminDashboardScreen), findsOneWidget);
    expect(find.text('Admin Command Hub'), findsOneWidget);
    expect(find.text('Calls Placed Today'), findsOneWidget);
    expect(find.text('Active Trucks'), findsOneWidget);
    expect(find.textContaining('active farmers today'), findsOneWidget);
  });

  testWidgets('A shipper session cannot route to the admin dashboard', (
    tester,
  ) async {
    final auth = AuthRepository(mockMode: true)
      ..currentProfile = const UserProfile(
        phone: '+918523123498',
        role: 'shipper',
        name: 'Farmer',
      );
    await tester.pumpWidget(MaterialApp(home: SessionRouter(repository: auth)));
    await tester.pumpAndSettle();
    expect(find.byType(AdminDashboardScreen), findsNothing);
  });

  testWidgets('A driver session cannot route to the admin dashboard', (
    tester,
  ) async {
    final auth = AuthRepository(mockMode: true)
      ..currentProfile = const UserProfile(
        phone: '+919876543210',
        role: 'driver',
        name: 'Driver',
      );
    await tester.pumpWidget(MaterialApp(home: SessionRouter(repository: auth)));
    await tester.pumpAndSettle();
    expect(find.byType(AdminDashboardScreen), findsNothing);
  });
}
