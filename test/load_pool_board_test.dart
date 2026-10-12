import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kolleru_wheels/core/constants/app_strings.dart';
import 'package:kolleru_wheels/core/constants/villages.dart';
import 'package:kolleru_wheels/core/theme/app_theme.dart';
import 'package:kolleru_wheels/core/utils/proximity_matcher.dart';
import 'package:kolleru_wheels/data/models/load_request_model.dart';
import 'package:kolleru_wheels/data/models/local_driver_profile.dart';
import 'package:kolleru_wheels/data/models/user_profile_model.dart';
import 'package:kolleru_wheels/data/models/vehicle_type.dart';
import 'package:kolleru_wheels/data/repositories/auth_repository.dart';
import 'package:kolleru_wheels/data/repositories/load_request_repository.dart';
import 'package:kolleru_wheels/data/repositories/local_driver_repository.dart';
import 'package:kolleru_wheels/data/repositories/telemetry_repository.dart';
import 'package:kolleru_wheels/presentation/driver/driver_dashboard_screen.dart';
import 'package:kolleru_wheels/presentation/driver/load_dispatch_card.dart';
import 'package:kolleru_wheels/presentation/driver/load_pool_board.dart';

final timestamp = DateTime.utc(2026, 10, 12, 10);

LoadRequestModel load(
  String id, {
  String destination = 'pulaparru',
  VehicleType? vehicle,
  String material = 'Live Fish',
}) => LoadRequestModel(
  id: id,
  posterName: 'రైతు / Farmer',
  posterPhone: '+919876543210',
  fromLocation: 'చేపల చెరువు / Fish pond',
  toVillageId: destination,
  materialType: material,
  vehicleTypeNeeded: vehicle,
  createdAt: timestamp,
);

class BoardRepository extends LoadRequestRepository {
  int reads = 0;
  bool fail = false;
  List<LoadRequestModel> requests = [];

  @override
  DateTime get currentTime => timestamp;

  @override
  Future<List<LoadRequestModel>> getActiveRequests({
    String? operationalMandalId,
  }) async {
    reads++;
    if (fail) throw StateError('Offline');
    return requests.where((request) => request.isActiveAt(currentTime) &&
        (operationalMandalId == null ||
            ProximityMatcher.mandalId(request.toVillageId) == operationalMandalId)).toList();
  }

  void publish(List<LoadRequestModel> updated) {
    requests = updated;
    notifyListeners();
  }
}

class PendingTelemetry extends TelemetryRepository {
  final completion = Completer<void>();
  Map<String, String?>? event;

  @override
  Future<void> logCallIntent({
    String? callerPhone,
    required String receiverPhone,
    String? callerRole,
    String contextNote = 'directory',
  }) {
    event = {
      'caller_phone': callerPhone,
      'receiver_phone': receiverPhone,
      'caller_role': callerRole,
      'context_note': contextNote,
    };
    return completion.future;
  }
}

Widget host(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Board matches vehicle and mandal, including any-vehicle loads', (
    tester,
  ) async {
    final repository = BoardRepository()..requests = [
      load('matching', vehicle: VehicleType.boleroPickup),
      load('any'),
      load('wrong-vehicle', vehicle: VehicleType.tractor),
      load('wrong-mandal', destination: 'kaikaluru-town'),
    ];
    addTearDown(repository.dispose);
    await tester.pumpWidget(host(LoadPoolBoard(
      repository: repository,
      operationalMandalId: 'mandavalli',
      vehicleType: VehicleType.boleroPickup,
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('load-matching')), findsOneWidget);
    expect(find.byKey(const ValueKey('load-any')), findsOneWidget);
    expect(find.byKey(const ValueKey('load-wrong-vehicle')), findsNothing);
    expect(find.byKey(const ValueKey('load-wrong-mandal')), findsNothing);
    repository.publish([load('wrong-vehicle', vehicle: VehicleType.tractor)]);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('load-pool-empty')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Board recovers from refresh failure and switches repositories', (
    tester,
  ) async {
    final first = BoardRepository()..fail = true;
    final second = BoardRepository()..requests = [load('second')];
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await tester.pumpWidget(host(LoadPoolBoard(repository: first)));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.loadFailedPool), findsOneWidget);
    first.fail = false;
    first.requests = [load('recovered')];
    await tester.ensureVisible(find.text(AppStrings.retry));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.retry));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('load-recovered')), findsOneWidget);
    await tester.pumpWidget(host(LoadPoolBoard(repository: second)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('load-second')), findsOneWidget);
    first.publish([load('old')]);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('load-old')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Call Farmer logs the load context without delaying the dialer', (
    tester,
  ) async {
    final telemetry = PendingTelemetry();
    final request = load('call-load');
    Uri? launched;
    await tester.pumpWidget(host(LoadDispatchCard(
      request: request,
      now: timestamp,
      callerPhone: '+919999999999',
      telemetryRepository: telemetry,
      launcher: (uri) async {
        launched = uri;
        return true;
      },
    )));
    await tester.ensureVisible(find.text(AppStrings.callFarmer));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.callFarmer));
    await tester.pumpAndSettle();
    expect(launched, Uri(scheme: 'tel', path: request.posterPhone));
    expect(telemetry.event, {
      'caller_phone': '+919999999999',
      'receiver_phone': request.posterPhone,
      'caller_role': 'driver',
      'context_note': 'urgent_load:call-load',
    });
    telemetry.completion.complete();
    expect(tester.takeException(), isNull);
  });

  for (final material in ['Live Fish', 'Paddy', 'Animal Feed', 'Shrimp']) {
    testWidgets('$material dispatch ticket fits a narrow screen at 2x text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(host(Padding(
        padding: const EdgeInsets.all(16),
        child: LoadDispatchCard(
          request: load('narrow', material: material),
          now: timestamp.add(const Duration(minutes: 26)),
        ),
      )));
      await tester.pumpAndSettle();
      expect(find.text(material), findsOneWidget);
      expect(find.text('4 నిమి / min left'), findsOneWidget);
      await tester.ensureVisible(find.text(AppStrings.callFarmer));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Dashboard pull-to-refresh reloads the operational load board', (
    tester,
  ) async {
    final repository = BoardRepository();
    addTearDown(repository.dispose);
    final profile = LocalDriverProfile(
      id: 'driver-test',
      name: 'రమేష్ / Ramesh',
      phone: '+919999999999',
      baseVillage: KolleruVillages.find('pulaparru')!,
      currentSpotVillage: KolleruVillages.find('pulaparru')!,
      vehicleType: VehicleType.boleroPickup,
      capacityTons: 1.5,
      specializations: const [],
      vehicleNumber: 'AP 39 AB 1234',
      isAvailable: true,
    );
    final auth = AuthRepository(mockMode: true)
      ..currentProfile = const UserProfile(phone: '+919999999999', role: 'driver');
    addTearDown(auth.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: DriverDashboardScreen(
        profile: profile,
        repository: LocalDriverRepository(),
        loadRequestRepository: repository,
        authRepository: auth,
      ),
    ));
    await tester.pumpAndSettle();
    final readsBefore = repository.reads;
    await tester.drag(find.byKey(const ValueKey('dashboard-scroll')), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(repository.reads, greaterThan(readsBefore));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
