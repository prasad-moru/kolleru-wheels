import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kolleru_wheels/core/constants/villages.dart';

Future<void> revealInVerticalList(
  WidgetTester tester,
  Finder target, {
  Finder? scrollable,
  double delta = 50,
}) async {
  try {
    if (target.evaluate().isNotEmpty) {
      await tester.ensureVisible(target.first);
      await tester.pumpAndSettle();
      return;
    }
  } catch (_) {
    // The target may not be built yet; try scrolling next.
  }

  final scrollableFinder = scrollable ?? find.byType(Scrollable);
  if (scrollableFinder.evaluate().isEmpty) {
    await tester.pumpAndSettle();
    return;
  }

  try {
    await tester.scrollUntilVisible(
      target,
      delta,
      scrollable: scrollableFinder.first,
      maxScrolls: 30,
    );
    await tester.pumpAndSettle();
  } catch (_) {
    // Keep the helper usable when a target or scrollable disappears.
    await tester.pumpAndSettle();
  }
}

Future<void> chooseCluster(
  WidgetTester tester, {
  String mandalId = 'mandavalli',
  String villageId = 'pulaparru',
}) async {
  final mandalPicker = find.byKey(const ValueKey('mandal-picker'));
  await revealInVerticalList(tester, mandalPicker);
  await tester.tap(mandalPicker);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('mandal-option-$mandalId')).last);
  await tester.pumpAndSettle();
  final villageInput = find.byKey(const ValueKey('village-input-field'));
  if (villageInput.evaluate().isNotEmpty) {
    await revealInVerticalList(tester, villageInput);
    await tester.enterText(villageInput, KolleruVillages.find(villageId)!.name);
    return;
  }
  final picker = find.byKey(ValueKey('village-picker-$mandalId'));
  await revealInVerticalList(tester, picker);
  await tester.tap(picker);
  await tester.pumpAndSettle();
  final village = find.byKey(ValueKey('village-option-$villageId'));
  await tester.scrollUntilVisible(
    village,
    150,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.tap(village.last);
  await tester.pumpAndSettle();
}
