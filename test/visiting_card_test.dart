import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kolleru_wheels/core/constants/app_strings.dart';
import 'package:kolleru_wheels/core/theme/app_theme.dart';
import 'package:kolleru_wheels/data/models/vehicle_type.dart';
import 'package:kolleru_wheels/data/repositories/mock_directory_repository.dart';
import 'package:kolleru_wheels/presentation/common/call_button.dart';
import 'package:kolleru_wheels/presentation/common/vehicle_badge.dart';
import 'package:kolleru_wheels/presentation/driver/visiting_card_screen.dart';

void main() {
  testWidgets('All five badges render at 64px and export as PNG', (
    tester,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final type in VehicleType.values)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: VehicleBadge(type: type, size: 64),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(VehicleBadge), findsNWidgets(5));
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        expect(bytes, isNotNull);
        expect(bytes!.buffer.asUint8List().take(8), [
          137,
          80,
          78,
          71,
          13,
          10,
          26,
          10,
        ]);
        if (Platform.environment['KOLLERU_RENDER_PREVIEWS'] == '1') {
          await Directory('build/previews').create(recursive: true);
          await File('build/previews/vehicle_badges.png')
              .writeAsBytes(bytes.buffer.asUint8List());
        }
      } finally {
        image.dispose();
      }
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('Visiting card includes details and exports the whole card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final driver = MockDirectoryRepository().getDrivers().first;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: VisitingCardScreen(driver: driver),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.cardHeader), findsOneWidget);
    expect(find.text(driver.phone), findsOneWidget);
    expect(
      find.text('${AppStrings.vehicleNumber}: ${driver.vehicleNumber}'),
      findsOneWidget,
    );
    expect(find.text(driver.specializations.single), findsOneWidget);
    expect(find.text(AppStrings.cardAvailable), findsOneWidget);
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find
          .ancestor(
            of: find.byType(TransportVisitingCard),
            matching: find.byType(RepaintBoundary),
          )
          .first,
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        expect(bytes, isNotNull);
        expect(image.width, 796);
        expect(image.height, greaterThan(1000));
        if (Platform.environment['KOLLERU_RENDER_PREVIEWS'] == '1') {
          await Directory('build/previews').create(recursive: true);
          await File('build/previews/visiting_card.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
        }
      } finally {
        image.dispose();
      }
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Visiting card and share control fit a narrow screen at 2x text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: VisitingCardScreen(
            driver: MockDirectoryRepository().getDrivers().first,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('share-visiting-card')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Demo call shows a notice without opening the dialer', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: CallButton(phone: '+910000000001', isDemo: true),
        ),
      ),
    );
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(find.text(AppStrings.demoCall), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
