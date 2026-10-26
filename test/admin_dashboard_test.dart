import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kolleru_wheels/data/models/admin_analytics_model.dart';
import 'package:kolleru_wheels/data/models/user_profile_model.dart';
import 'package:kolleru_wheels/data/models/driver_verification.dart';
import 'package:kolleru_wheels/data/repositories/admin_analytics_repository.dart';
import 'package:kolleru_wheels/data/repositories/auth_repository.dart';
import 'package:kolleru_wheels/presentation/admin/admin_dashboard_screen.dart';
import 'package:kolleru_wheels/presentation/auth/session_router.dart';

final _now = DateTime.utc(2026, 10, 12, 6);

AdminAnalyticsModel _sample({
  String status = 'pending',
  int extraCalls = 0,
  bool linkedLoad = false,
}) => AdminAnalyticsModel.aggregate(
  profiles: [
    {'phone': '+918523123498', 'role': 'shipper', 'village_id': 'pulaparru'},
    {'phone': '+919876543210', 'role': 'driver', 'village_id': 'kovvadalanka'},
    {'phone': '+919111111111', 'role': 'admin', 'village_id': null},
  ],
  drivers: [
    {
      'id': 'driver-1',
      'name': 'మూర్తి / Murthy',
      'phone': '+919876543210',
      'base_village_id': 'kovvadalanka',
      'is_available': true,
      'vehicle_type': 'boleroPickup',
      'vehicle_number': 'AP 37 TX 1234',
      'capacity_tons': 2.5,
      'verification_status': 'approved',
    },
    {
      'id': 'driver-2',
      'name': 'సురేష్ రవాణా / Suresh Transport',
      'phone': '+919222222222',
      'base_village_id': 'pulaparru',
      'is_available': false,
      'vehicle_type': 'tataAce',
      'vehicle_number': 'AP 37 Y 5678',
      'capacity_tons': 1.5,
      'verification_status': status,
    },
  ],
  callsToday: [
    {'caller_phone': '+918523123498'},
    {'caller_phone': '+918523123498'},
    {'caller_phone': null},
    for (var i = 0; i < extraCalls; i++) {'caller_phone': null},
  ],
  recentTelemetry: [
    {
      'created_at': '2026-10-12T05:50:00Z',
      'caller_role': 'shipper',
      'caller_phone': '+918523123498',
      'receiver_phone': '+919876543210',
      'context_note': linkedLoad
          ? 'urgent_load:live-1'
          : 'visiting_card:driver-1',
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
  AdminAnalyticsModel model;
  final changes = StreamController<void>.broadcast();
  final decisions = <DriverVerification>[];
  bool failReview = false;
  Completer<AdminAnalyticsModel>? nextSnapshot;
  @override
  Stream<void> watchChanges(AuthRepository auth) => changes.stream;
  @override
  Future<void> reviewDriver(
    AuthRepository auth, {
    required String driverId,
    required DriverVerification decision,
  }) async {
    expect(driverId, 'driver-2');
    if (failReview) throw StateError('Offline');
    decisions.add(decision);
    model = _sample(status: decision.name);
    changes.add(null);
  }

  @override
  Future<AdminAnalyticsModel> fetchSnapshot(AuthRepository auth) async =>
      nextSnapshot == null ? model : await nextSnapshot!.future;
}

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'selected_language': 'english',
    }),
  );

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
    expect(find.text('Admin Desk'), findsOneWidget);
    expect(find.text("Today's Calls"), findsOneWidget);
    expect(find.text('Total Vehicles'), findsOneWidget);
    expect(find.byKey(const ValueKey('admin-metrics-grid')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
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
  Future<(_FakeAdminAnalyticsRepository, AuthRepository)> openDesk(
    WidgetTester tester, {
    double width = 430,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = AuthRepository(mockMode: true)
      ..currentProfile = const UserProfile(
        phone: '+919111111111',
        role: 'admin',
      );
    final repo = _FakeAdminAnalyticsRepository(_sample());
    addTearDown(auth.dispose);
    addTearDown(() {
      unawaited(repo.changes.close());
    });
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: AdminDashboardScreen(
          authRepository: auth,
          analyticsRepository: repo,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (repo, auth);
  }

  for (final decision in [
    DriverVerification.approved,
    DriverVerification.rejected,
  ]) {
    testWidgets(
      'Review ${decision.name} removes pending card and appears in fleet',
      (tester) async {
        final (repo, _) = await openDesk(tester);
        expect(find.text('Suresh Transport • Mandavalli'), findsOneWidget);
        expect(find.textContaining('AP 37 Y 5678'), findsOneWidget);
        await tester.tap(
          find.byKey(
            ValueKey(
              decision == DriverVerification.approved
                  ? 'approve-driver-btn'
                  : 'reject-driver-btn',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(repo.decisions, [decision]);
        expect(find.text('No pending approvals'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('admin-fleet-tab')));
        await tester.pumpAndSettle();
        expect(
          find.text(
            decision == DriverVerification.approved ? 'Approved' : 'Rejected',
          ),
          findsWidgets,
        );
        expect(find.text('Suresh Transport • Mandavalli'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('Failed review retains the queue and reports retry state', (
    tester,
  ) async {
    final (repo, _) = await openDesk(tester);
    repo.failReview = true;
    await tester.tap(find.byKey(const ValueKey('approve-driver-btn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('driver-review-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('approve-driver-btn')), findsOneWidget);
    expect(repo.decisions, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Realtime notifications update metrics and phone-enriched activity',
    (tester) async {
      final (repo, _) = await openDesk(tester);
      expect(find.text('Shipper (Mandavalli) → Murthy'), findsOneWidget);
      expect(find.textContaining('Transport inquiry'), findsOneWidget);
      repo.model = _sample(extraCalls: 5);
      repo.changes.add(null);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('admin-metrics-grid')),
          matching: find.text('8'),
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('cluster-health-strip')),
      );
      expect(find.text('Kaikaluru: 1 Active'), findsOneWidget);
      expect(find.text('Bhimavaram: 0 Active'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Global language toggle keeps overview, fleet and reports single-language',
    (tester) async {
      await openDesk(tester);
      await tester.tap(find.byKey(const ValueKey('language-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('అడ్మిన్ డెస్క్'), findsOneWidget);
      expect(find.text('Admin Desk'), findsNothing);
      expect(find.textContaining('Suresh'), findsNothing);
      expect(find.textContaining(' / '), findsNothing);
      expect(find.text('సురేష్ రవాణా • మండవల్లి'), findsOneWidget);
      for (final key in [
        'admin-fleet-tab',
        'admin-reports-tab',
        'admin-overview-tab',
      ]) {
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
        expect(find.textContaining(' / '), findsNothing);
        expect(find.textContaining('Transport inquiry'), findsNothing);
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.byKey(const ValueKey('language-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('Admin Desk'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Demotion immediately removes admin data and cancels the feed', (
    tester,
  ) async {
    final (repo, auth) = await openDesk(tester);
    auth.currentProfile = const UserProfile(
      phone: '+919111111111',
      role: 'shipper',
    );
    repo.changes.add(null);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('admin-metrics-grid')), findsNothing);
    expect(find.text('Admin authorization required'), findsOneWidget);
    expect(repo.changes.hasListener, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Console fits a narrow phone with large text', (tester) async {
    await openDesk(tester, width: 320, scale: 2);
    expect(tester.takeException(), isNull);
    for (var i = 0; i < 5; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    for (final key in ['admin-fleet-tab', 'admin-reports-tab']) {
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('A snapshot arriving after demotion cannot restore admin data', (
    tester,
  ) async {
    final (repo, auth) = await openDesk(tester);
    repo.nextSnapshot = Completer<AdminAnalyticsModel>();
    repo.changes.add(null);
    await tester.pump();
    auth.currentProfile = const UserProfile(
      phone: '+919111111111',
      role: 'shipper',
    );
    await tester.pump();
    repo.nextSnapshot!.complete(_sample());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('admin-metrics-grid')), findsNothing);
    expect(find.text('Admin authorization required'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'Only approved online vehicles contribute to health and live driver totals',
    () {
      final snapshot = AdminAnalyticsModel.aggregate(
        profiles: [],
        callsToday: [],
        recentTelemetry: [],
        loads: [],
        now: _now,
        drivers: [
          for (final status in ['approved', 'pending', 'rejected'])
            {
              'id': status,
              'base_village_id': 'akividu-town',
              'is_available': true,
              'verification_status': status,
            },
        ],
      );
      expect(snapshot.registeredDrivers, 3);
      expect(snapshot.activeDrivers, 1);
      expect(snapshot.pendingDrivers, hasLength(1));
      expect(
        snapshot.mandals
            .singleWhere((m) => m.id == 'akividu')
            .activeDriverCount,
        1,
      );
    },
  );
  testWidgets(
    'Recorded load category is shown and localized without inventing tonnage',
    (tester) async {
      final (repo, _) = await openDesk(tester);
      repo.model = _sample(linkedLoad: true);
      repo.changes.add(null);
      await tester.pumpAndSettle();
      expect(find.textContaining('Live Fish • Bolero pickup'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('language-toggle')));
      await tester.pumpAndSettle();
      expect(find.textContaining('లైవ్ ఫిష్ • బొలెరో పికప్'), findsOneWidget);
      expect(find.textContaining('Live Fish'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
