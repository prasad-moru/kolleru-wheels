import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kolleru_wheels/core/constants/app_strings.dart';
import 'package:kolleru_wheels/core/theme/app_theme.dart';
import 'package:kolleru_wheels/data/models/load_request_model.dart';
import 'package:kolleru_wheels/data/models/vehicle_type.dart';
import 'package:kolleru_wheels/data/repositories/load_request_repository.dart';
import 'package:kolleru_wheels/presentation/driver/load_pool_board.dart';
import 'package:kolleru_wheels/presentation/farmer/post_load_bottom_sheet.dart';

LoadRequestModel request(
  DateTime created, {
  String id = 'test',
  LoadRequestStatus status = LoadRequestStatus.open,
}) => LoadRequestModel(
  id: id,
  posterName: 'Farmer',
  posterPhone: '+919876543210',
  fromLocation: 'Kaikaluru Market',
  toVillageId: 'pulaparru',
  materialType: AppStrings.materials.first,
  vehicleTypeNeeded: VehicleType.boleroPickup,
  createdAt: created,
  status: status,
);
Future<LoadRequestModel> create(LoadRequestRepository repository) =>
    repository.createRequest(
      posterName: 'Farmer',
      posterPhone: '+919876543210',
      fromLocation: 'Kaikaluru Market',
      toVillageId: 'pulaparru',
      materialType: AppStrings.materials.first,
      vehicleTypeNeeded: VehicleType.boleroPickup,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'Posting sheet supports narrow screen with enlarged text and keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 250);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final repository = LoadRequestRepository();
      addTearDown(repository.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: PostLoadBottomSheet(repository: repository)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('post-load-submit')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'Expires at exactly 30 minutes, excludes closed and future requests',
    () {
      final now = DateTime.utc(2026, 10, 6, 10);
      expect(
        request(now.subtract(const Duration(minutes: 30))).isActiveAt(now),
        false,
      );
      expect(
        request(
          now
              .subtract(const Duration(minutes: 30))
              .add(const Duration(microseconds: 1)),
        ).isActiveAt(now),
        true,
      );
      expect(
        request(now.subtract(const Duration(minutes: 31))).isActiveAt(now),
        false,
      );
      expect(
        request(now, status: LoadRequestStatus.closed).isActiveAt(now),
        false,
      );
      expect(
        request(now.add(const Duration(seconds: 1))).isActiveAt(now),
        false,
      );
      final restored = LoadRequestModel.fromJson(request(now).toJson());
      expect(restored.createdAt, now);
      expect(restored.vehicleTypeNeeded, VehicleType.boleroPickup);
    },
  );
  test(
    'Persists, restores, closes, and expires with an injected clock',
    () async {
      var now = DateTime.utc(2026, 10, 6, 10);
      final repository = LoadRequestRepository(now: () => now);
      addTearDown(repository.dispose);
      final load = await create(repository);
      final reloaded = LoadRequestRepository(now: () => now);
      addTearDown(reloaded.dispose);
      expect((await reloaded.getActiveRequests()).single.id, load.id);
      now = now.add(const Duration(minutes: 29, seconds: 59));
      expect(await repository.getActiveRequests(), hasLength(1));
      now = now.add(const Duration(seconds: 1));
      expect(await repository.getActiveRequests(), isEmpty);
      expect(await reloaded.getActiveRequests(), isEmpty);
      final fresh = await create(repository);
      await repository.closeRequest(fresh.id);
      expect(await repository.getActiveRequests(), isEmpty);
      final afterClose = LoadRequestRepository(now: () => now);
      addTearDown(afterClose.dispose);
      expect(await afterClose.getActiveRequests(), isEmpty);
    },
  );
  test('Restored records exclude stale, future and closed requests and sort newest first', () async {
    final now = DateTime.utc(2026, 10, 6, 10);
    SharedPreferences.setMockInitialValues({
      LoadRequestRepository.storageKey: jsonEncode([
        request(
          now.subtract(const Duration(minutes: 10)),
          id: 'older',
        ).toJson(),
        request(
          now.subtract(const Duration(minutes: 31)),
          id: 'expired',
        ).toJson(),
        request(now, id: 'closed', status: LoadRequestStatus.closed).toJson(),
        request(now.add(const Duration(minutes: 1)), id: 'future').toJson(),
        request(now, id: 'newest').toJson(),
      ]),
    });
    final repository = LoadRequestRepository(now: () => now);
    addTearDown(repository.dispose);
    expect((await repository.getActiveRequests()).map((r) => r.id), [
      'newest',
      'older',
    ]);
    await repository.closeRequest('missing');
    expect(await repository.getActiveRequests(), hasLength(2));
  });
  test(
    'Serial creation keeps both requests and notifies after each save',
    () async {
      final repository = LoadRequestRepository();
      addTearDown(repository.dispose);
      var notifications = 0;
      repository.addListener(() => notifications++);
      final results = await Future.wait([
        create(repository),
        create(repository),
      ]);
      expect(results.map((r) => r.id).toSet(), hasLength(2));
      expect(await repository.getActiveRequests(), hasLength(2));
      expect(notifications, 2);
      await expectLater(
        repository.createRequest(
          posterName: 'A',
          posterPhone: 'bad',
          fromLocation: 'Market',
          toVillageId: 'pulaparru',
          materialType: 'Cement',
        ),
        throwsFormatException,
      );
      expect(await repository.getActiveRequests(), hasLength(2));
    },
  );
  test(
    'Corrupt stored data is reported and never silently overwritten',
    () async {
      SharedPreferences.setMockInitialValues({
        LoadRequestRepository.storageKey: '{bad',
      });
      final repository = LoadRequestRepository();
      addTearDown(repository.dispose);
      await expectLater(repository.getActiveRequests(), throwsFormatException);
      await expectLater(create(repository), throwsFormatException);
      expect(
        (await SharedPreferences.getInstance()).getString(
          LoadRequestRepository.storageKey,
        ),
        '{bad',
      );
    },
  );
  testWidgets('Board updates after posting and removes a load at expiry', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 10, 6, 10);
    final repository = LoadRequestRepository(now: () => now);
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: LoadPoolBoard(repository: repository),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.noLoads), findsOneWidget);
    await create(repository);
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.justPosted), findsOneWidget);
    expect(find.text(AppStrings.callShipper), findsOneWidget);
    now = now.add(const Duration(minutes: 29, seconds: 59));
    await tester.pump(const Duration(minutes: 29, seconds: 59));
    await tester.pumpAndSettle();
    expect(find.text('29 నిమిషాల క్రితం / minutes ago'), findsOneWidget);
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.noLoads), findsOneWidget);
    expect(find.text(AppStrings.callShipper), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Farmer sheet validates then posts and persists selected material',
    (tester) async {
      final repository = LoadRequestRepository();
      addTearDown(repository.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => PostLoadBottomSheet(
                    repository: repository,
                    initialVillageId: 'pulaparru',
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('post-load-submit')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('post-load-submit')));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.phoneInvalid), findsOneWidget);
      expect(await repository.getActiveRequests(), isEmpty);
      await tester.ensureVisible(find.text('కైకలూరు మార్కెట్'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('కైకలూరు మార్కెట్'));
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'సిమెంట్'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'సిమెంట్'));
      await tester.ensureVisible(find.byKey(const ValueKey('load-phone')));
      await tester.enterText(
        find.byKey(const ValueKey('load-phone')),
        '9876543210',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('post-load-submit')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('post-load-submit')));
      await tester.pumpAndSettle();
      expect(find.byType(PostLoadBottomSheet), findsNothing);
      final load = (await repository.getActiveRequests()).single;
      expect(load.materialType, 'సిమెంట్');
      expect(load.fromLocation, 'కైకలూరు మార్కెట్');
      expect(load.toVillageId, 'pulaparru');
      expect(load.posterPhone, '+919876543210');
    },
  );
}
