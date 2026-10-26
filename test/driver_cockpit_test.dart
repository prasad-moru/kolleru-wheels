import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kolleru_wheels/core/constants/villages.dart';
import 'package:kolleru_wheels/core/theme/app_theme.dart';
import 'package:kolleru_wheels/data/models/driver_activity_model.dart';
import 'package:kolleru_wheels/data/models/driver_model.dart';
import 'package:kolleru_wheels/data/models/local_driver_profile.dart';
import 'package:kolleru_wheels/data/models/user_profile_model.dart';
import 'package:kolleru_wheels/data/models/vehicle_type.dart';
import 'package:kolleru_wheels/data/repositories/auth_repository.dart';
import 'package:kolleru_wheels/data/repositories/driver_activity_repository.dart';
import 'package:kolleru_wheels/data/repositories/local_driver_repository.dart';
import 'package:kolleru_wheels/data/repositories/supabase_driver_repository.dart';
import 'package:kolleru_wheels/presentation/common/call_button.dart';
import 'package:kolleru_wheels/presentation/directory/widgets/driver_visiting_card.dart';
import 'package:kolleru_wheels/presentation/driver/driver_dashboard_screen.dart';
import 'package:kolleru_wheels/presentation/driver/visiting_card_screen.dart';

final now = DateTime.utc(2026, 10, 26, 9);
LocalDriverProfile profile({bool verified = true}) => LocalDriverProfile(
  id: 'driver-cockpit',
  name: 'మూర్తి రవాణా / Murthy Transport',
  phone: '+919876543210',
  baseVillage: KolleruVillages.find('akividu-town')!,
  currentSpotVillage: KolleruVillages.find('akividu-town')!,
  vehicleType: VehicleType.boleroPickup,
  capacityTons: 2.5,
  specializations: const [],
  vehicleNumber: 'AP 37 TX 1234',
  isAvailable: true,
  isPhoneVerified: verified,
);

class FakeActivity extends DriverActivityRepository {
  FakeActivity() : super(now: () => now);
  bool fail = false;
  int reads = 0;
  @override
  Future<DriverActivity> fetchActivity(AuthRepository auth) async {
    reads++;
    if (fail) throw StateError('Offline');
    return DriverActivity(
      callsToday: 6,
      recentCalls: [
        DriverInquiry(
          id: 'first',
          createdAt: now.subtract(const Duration(minutes: 15)),
          location: 'సిద్ధాపురం చెరువు / Siddhapuram Pond',
          loadDetail: 'చేపల రవాణా / Fish transport',
        ),
        DriverInquiry(
          id: 'second',
          createdAt: now.subtract(const Duration(hours: 1)),
          location: 'గుండుగొలను / Gundugolanu',
          loadDetail: 'మేత సంచులు / Feed bags',
        ),
        DriverInquiry(
          id: 'third',
          createdAt: now.subtract(const Duration(hours: 2)),
          callerVillageId: 'pulaparru',
        ),
      ],
    );
  }
}

class FakeRemote extends SupabaseDriverRepository {
  final writes = <DriverModel>[];
  Completer<void>? pending;
  @override
  bool get isConfigured => true;
  @override
  Future<void> upsertDriver(DriverModel driver) async {
    writes.add(driver);
    await pending?.future;
  }
}

Finder get scrollable => find
    .descendant(
      of: find.byKey(const ValueKey('dashboard-scroll')),
      matching: find.byType(Scrollable),
    )
    .first;
Future<void> reveal(WidgetTester tester, Finder target) async {
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(target, 180, scrollable: scrollable);
  await tester.pumpAndSettle();
}

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'selected_language': 'english',
    }),
  );

  Future<FakeActivity> showCockpit(
    WidgetTester tester, {
    FakeActivity? activity,
    FakeRemote? remote,
    bool verified = true,
  }) async {
    final local = LocalDriverRepository();
    final saved = profile(verified: verified);
    await local.saveProfile(saved);
    final auth = AuthRepository(mockMode: true)
      ..currentProfile = UserProfile(phone: saved.phone, role: 'driver');
    addTearDown(auth.dispose);
    final repository = activity ?? FakeActivity();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: DriverDashboardScreen(
          profile: saved,
          repository: local,
          authRepository: auth,
          activityRepository: repository,
          remoteDriverRepository: remote,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets(
    'Availability persists, updates the preview, and prevents duplicate writes while syncing',
    (tester) async {
      final remote = FakeRemote();
      await showCockpit(tester, remote: remote);
      remote.pending = Completer<void>();
      await tester.tap(find.byKey(const ValueKey('driver-status-toggle')));
      await tester.pumpAndSettle();
      expect(
        (await LocalDriverRepository().getProfile())!.isAvailable,
        isFalse,
      );
      expect(
        tester
            .widget<Switch>(find.byKey(const ValueKey('driver-availability')))
            .onChanged,
        isNull,
      );
      expect(remote.writes.last.isAvailable, isFalse);
      expect(find.text('⚪ Offline - Off Duty'), findsOneWidget);
      remote.pending!.complete();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Switch>(find.byKey(const ValueKey('driver-availability')))
            .onChanged,
        isNotNull,
      );
      await reveal(tester, find.byKey(const ValueKey('driver-card-preview')));
      final preview = tester.widget<DriverVisitingCard>(
        find.byKey(const ValueKey('driver-card-preview')),
      );
      expect(preview.driver.isAvailable, isFalse);
      expect(preview.previewOnly, isTrue);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('driver-card-preview')),
          matching: find.byType(CallButton),
        ),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Cockpit metrics and two recent logs reflect the injected activity snapshot',
    (tester) async {
      await showCockpit(tester);
      await reveal(tester, find.byKey(const ValueKey('driver-call-counter')));
      expect(find.text('6 Calls'), findsOneWidget);
      expect(find.text('Verified Driver'), findsOneWidget);
      await reveal(tester, find.byKey(const ValueKey('driver-inquiry-second')));
      expect(find.text('Siddhapuram Pond'), findsOneWidget);
      expect(find.text('Fish transport'), findsOneWidget);
      expect(find.text('15m ago'), findsOneWidget);
      expect(find.text('1h ago'), findsOneWidget);
      expect(find.byKey(const ValueKey('driver-inquiry-third')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('driver-nav-calls')));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('driver-inquiry-third')));
      expect(find.text('Pulaparru'), findsOneWidget);
      expect(find.text('Transport inquiry'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Global language changes translate status, preview, metrics, logs, and load board',
    (tester) async {
      await showCockpit(tester);
      await tester.tap(find.byKey(const ValueKey('language-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('డ్రైవర్ డ్యాష్‌బోర్డ్'), findsOneWidget);
      expect(find.text('🟢 ఆర్డర్లకు సిద్ధం'), findsOneWidget);
      expect(find.textContaining(' / '), findsNothing);
      await reveal(tester, find.byKey(const ValueKey('driver-call-counter')));
      expect(find.text('6 కాల్స్'), findsOneWidget);
      await reveal(tester, find.byKey(const ValueKey('driver-inquiry-second')));
      expect(find.text('గుండుగొలను'), findsOneWidget);
      expect(find.text('1 గంటల క్రితం'), findsOneWidget);
      expect(find.text('Siddhapuram Pond'), findsNothing);
      await reveal(tester, find.byKey(const ValueKey('load-pool-empty')));
      expect(find.textContaining(' / '), findsNothing);
      await tester.tap(find.byKey(const ValueKey('language-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('Driver Cockpit'), findsOneWidget);
      expect(find.textContaining(' / '), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'My Card tab exposes the read-only preview and existing card editor',
    (tester) async {
      await showCockpit(tester);
      await tester.tap(find.byKey(const ValueKey('driver-nav-card')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('driver-card-preview')), findsOneWidget);
      expect(find.byKey(const ValueKey('driver-status-toggle')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('edit-driver-card')));
      await tester.pumpAndSettle();
      expect(find.byType(VisitingCardScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('driver-nav-dashboard')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('driver-status-toggle')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Unverified profiles are not presented as verified drivers', (
    tester,
  ) async {
    await showCockpit(tester, verified: false);
    await reveal(tester, find.byKey(const ValueKey('driver-call-counter')));
    expect(find.text('Verification Pending'), findsOneWidget);
    expect(find.text('Verified Driver'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Failed activity read provides retry and does not invent a count',
    (tester) async {
      final activity = FakeActivity()..fail = true;
      await showCockpit(tester, activity: activity);
      await reveal(tester, find.byKey(const ValueKey('retry-driver-activity')));
      expect(find.text('6 Calls'), findsNothing);
      activity.fail = false;
      await tester.tap(find.byKey(const ValueKey('retry-driver-activity')));
      await tester.pumpAndSettle();
      expect(activity.reads, 2);
      expect(find.byKey(const ValueKey('retry-driver-activity')), findsNothing);
      await reveal(tester, find.byKey(const ValueKey('driver-call-counter')));
      expect(find.text('6 Calls'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('320px cockpit supports doubled text in both languages', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await showCockpit(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('language-toggle')));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const ValueKey('driver-call-counter')));
    expect(tester.takeException(), isNull);
    await reveal(tester, find.byKey(const ValueKey('driver-inquiry-second')));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
