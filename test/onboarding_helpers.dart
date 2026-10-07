import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kolleru_wheels/core/constants/villages.dart';

Future<void> chooseCluster(
  WidgetTester tester, {
  String mandalId = 'mandavalli',
  String villageId = 'pulaparru',
}) async {
  final mandal = KolleruVillages.mandals.firstWhere((m) => m.id == mandalId);
  await tester.ensureVisible(find.byKey(const ValueKey('mandal-picker')));
  await tester.tap(find.byKey(const ValueKey('mandal-picker')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('${mandal.teluguName} / ${mandal.name}').last);
  await tester.pumpAndSettle();
  final picker = find.byKey(ValueKey('village-picker-$mandalId'));
  await tester.ensureVisible(picker);
  await tester.tap(picker);
  await tester.pumpAndSettle();
  final village = find.text(KolleruVillages.find(villageId)!.label);
  await tester.scrollUntilVisible(
    village,
    150,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.tap(village.last);
  await tester.pumpAndSettle();
}
