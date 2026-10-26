import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kolleru_wheels/core/constants/villages.dart';
import 'package:kolleru_wheels/core/localization/app_language_provider.dart';
import 'package:kolleru_wheels/core/theme/app_theme.dart';
import 'package:kolleru_wheels/data/models/driver_model.dart';
import 'package:kolleru_wheels/data/models/user_profile_model.dart';
import 'package:kolleru_wheels/data/models/vehicle_type.dart';
import 'package:kolleru_wheels/data/repositories/auth_repository.dart';
import 'package:kolleru_wheels/data/repositories/telemetry_repository.dart';
import 'package:kolleru_wheels/presentation/common/driver_directory_card.dart';
import 'package:kolleru_wheels/presentation/directory/widgets/direct_call_modal.dart';

DriverModel driver({bool demo = false, String phone = '+919876543210'}) =>
    DriverModel(
      id: 'driver-connect',
      name: 'మూర్తి రవాణా / Murthy Transport',
      phone: phone,
      village: KolleruVillages.find('akividu-town')!,
      baseLocation: 'ఆకివీడు / Akividu',
      currentSpot: 'akividu-town',
      vehicleType: VehicleType.boleroPickup,
      capacity: '2.5 టన్నులు / 2.5 Tons',
      capacityTons: 2.5,
      vehicleNumber: 'AP 37 TX 1234',
      isAvailable: true,
      isPhoneVerified: true,
      isDemo: demo,
    );

class InquiryTelemetry extends TelemetryRepository {
  final rows = <Map<String, String?>>[];
  Completer<void>? pending;
  @override
  Future<void> logCallIntent({
    String? callerPhone,
    required String receiverPhone,
    String? callerRole,
    String contextNote = 'directory',
  }) async {
    rows.add({
      'caller': callerPhone,
      'receiver': receiverPhone,
      'role': callerRole,
      'context': contextNote,
    });
    await pending?.future;
  }
}

Future<void> tapAction(WidgetTester tester, String key) async {
  final action = find.byKey(ValueKey(key));
  await tester.ensureVisible(action);
  await tester.pumpAndSettle();
  await tester.tap(action);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<AppLanguageProvider> showSheet(
    WidgetTester tester, {
    InquiryTelemetry? telemetry,
    Future<bool> Function(Uri)? launcher,
    Future<bool> Function()? beforeContact,
    VoidCallback? onCall,
    VoidCallback? onWhatsApp,
    DriverModel? target,
    AuthRepository? authRepository,
    bool guest = false,
    bool fromCard = false,
    AppLanguage initialLanguage = AppLanguage.english,
  }) async {
    final language = AppLanguageProvider();
    await language.setLanguage(initialLanguage);
    addTearDown(language.dispose);
    final auth = authRepository ?? AuthRepository(mockMode: true);
    addTearDown(auth.dispose);
    if (guest) {
      await auth.browseAsGuest();
    } else {
      auth.currentProfile = const UserProfile(
        phone: '+919999999999',
        role: 'shipper',
      );
    }
    await tester.pumpWidget(
      AppLanguageScope(
        language: language,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => fromCard
                  ? SingleChildScrollView(
                      child: DriverDirectoryCard(
                        driver: target ?? driver(),
                        authRepository: auth,
                        telemetryRepository: telemetry,
                        launcher: launcher,
                        beforeCall: beforeContact,
                        onOpen: () {},
                        onWhatsApp: onWhatsApp ?? () {},
                        onCallLaunched: onCall,
                      ),
                    )
                  : FilledButton(
                      key: const ValueKey('open-sheet'),
                      onPressed: () => showDirectCallModal(
                        context: context,
                        driver: target ?? driver(),
                        authRepository: auth,
                        telemetryRepository: telemetry,
                        launcher: launcher,
                        beforeContact: beforeContact,
                        onCallLaunched: onCall,
                        onWhatsAppLaunched: onWhatsApp,
                      ),
                      child: const Text('Open'),
                    ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (!fromCard) {
      await tapAction(tester, 'open-sheet');
    }
    return language;
  }

  testWidgets(
    'Sheet shows summary, three checklist chips, rounded corners, and closes without logging',
    (tester) async {
      final telemetry = InquiryTelemetry();
      var launches = 0;
      await showSheet(
        tester,
        telemetry: telemetry,
        launcher: (_) async {
          launches++;
          return true;
        },
      );
      expect(find.text('Direct Driver Connect'), findsOneWidget);
      expect(find.text('Murthy Transport'), findsOneWidget);
      expect(find.text('Bolero pickup • 2.5 Tons'), findsOneWidget);
      expect(find.text('Akividu Delta Cluster'), findsOneWidget);
      expect(find.byIcon(Icons.verified), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('checklist-chips')),
          matching: find.byType(Chip),
        ),
        findsNWidgets(3),
      );
      final shape =
          tester.widget<BottomSheet>(find.byType(BottomSheet)).shape!
              as RoundedRectangleBorder;
      expect(
        shape.borderRadius.resolve(TextDirection.ltr).topLeft,
        const Radius.circular(28),
      );
      expect(find.byKey(const ValueKey('direct-call-handle')), findsOneWidget);
      await tapAction(tester, 'modal-close-button');
      expect(find.byKey(const ValueKey('direct-call-sheet')), findsNothing);
      expect(telemetry.rows, isEmpty);
      expect(launches, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Call records one inquiry and launches a normalized tel URI', (
    tester,
  ) async {
    final telemetry = InquiryTelemetry();
    final uris = <Uri>[];
    var calls = 0;
    await showSheet(
      tester,
      target: driver(phone: '91 98765-43210'),
      telemetry: telemetry,
      launcher: (uri) async {
        uris.add(uri);
        return true;
      },
      onCall: () => calls++,
    );
    await tapAction(tester, 'modal-call-button');
    expect(uris.single, Uri(scheme: 'tel', path: '+919876543210'));
    expect(telemetry.rows.single, {
      'caller': '+919999999999',
      'receiver': '+919876543210',
      'role': 'shipper',
      'context': 'driver_connect:driver-connect:call',
    });
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'WhatsApp records one inquiry with an encoded greeting in the active language',
    (tester) async {
      final telemetry = InquiryTelemetry();
      final uris = <Uri>[];
      var chats = 0;
      final language = await showSheet(
        tester,
        telemetry: telemetry,
        launcher: (uri) async {
          uris.add(uri);
          return true;
        },
        onWhatsApp: () => chats++,
      );
      await tapAction(tester, 'modal-whatsapp-button');
      expect(uris.single.host, 'wa.me');
      expect(uris.single.scheme, 'https');
      expect(uris.single.path, '/919876543210');
      expect(
        uris.single.queryParameters['text'],
        contains('Hello Murthy Transport'),
      );
      expect(uris.single.queryParameters['text'], contains('Kolleru delta'));
      expect(
        telemetry.rows.single['context'],
        'driver_connect:driver-connect:whatsapp',
      );
      expect(chats, 1);
      await language.setLanguage(AppLanguage.telugu);
      await tester.pumpAndSettle();
      expect(find.text('డ్రైవర్‌తో నేరుగా మాట్లాడండి'), findsOneWidget);
      expect(find.text('Direct Driver Connect'), findsNothing);
      expect(find.textContaining(' / '), findsNothing);
      await tapAction(tester, 'modal-whatsapp-button');
      expect(
        uris.last.queryParameters['text'],
        contains('నమస్కారం మూర్తి రవాణా'),
      );
      expect(uris.last.queryParameters['text'], isNot(contains('Hello')));
      expect(telemetry.rows.length, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Card contact buttons open the sheet without logging or launching early',
    (tester) async {
      final telemetry = InquiryTelemetry();
      var launches = 0;
      await showSheet(
        tester,
        fromCard: true,
        telemetry: telemetry,
        launcher: (_) async {
          launches++;
          return true;
        },
      );
      final call = find.descendant(
        of: find.byKey(const ValueKey('call-driver-connect')),
        matching: find.byType(FilledButton),
      );
      await tester.ensureVisible(call);
      await tester.pumpAndSettle();
      await tester.tap(call);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('direct-call-sheet')), findsOneWidget);
      expect(telemetry.rows, isEmpty);
      expect(launches, 0);
      await tapAction(tester, 'modal-call-button');
      expect(telemetry.rows.length, 1);
      expect(launches, 1);
      await tapAction(tester, 'modal-close-button');
      await tapAction(tester, 'whatsapp-driver-connect');
      expect(find.byKey(const ValueKey('direct-call-sheet')), findsOneWidget);
      expect(telemetry.rows.length, 1);
      await tapAction(tester, 'modal-whatsapp-button');
      expect(telemetry.rows.length, 2);
      expect(launches, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Telemetry delay or failure does not block launching a contact', (
    tester,
  ) async {
    final telemetry = InquiryTelemetry()..pending = Completer<void>();
    var launches = 0;
    await showSheet(
      tester,
      telemetry: telemetry,
      launcher: (_) async {
        launches++;
        return true;
      },
    );
    await tapAction(tester, 'modal-call-button');
    expect(launches, 1);
    expect(telemetry.rows.length, 1);
    telemetry.pending!.completeError(StateError('Offline'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Pending launch disables both actions and prevents duplicate inquiry writes',
    (tester) async {
      final telemetry = InquiryTelemetry();
      final pending = Completer<bool>();
      var launches = 0;
      await showSheet(
        tester,
        telemetry: telemetry,
        launcher: (_) {
          launches++;
          return pending.future;
        },
      );
      await tapAction(tester, 'modal-call-button');
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('modal-call-button')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('modal-whatsapp-button')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('modal-call-button')));
      await tester.pumpAndSettle();
      expect(telemetry.rows.length, 1);
      expect(launches, 1);
      pending.complete(true);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('modal-call-button')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Failed launcher shows a localized error and allows retry', (
    tester,
  ) async {
    final telemetry = InquiryTelemetry();
    var success = false;
    final language = await showSheet(
      tester,
      telemetry: telemetry,
      launcher: (_) async => success,
    );
    await tapAction(tester, 'modal-whatsapp-button');
    expect(find.text('Could not open WhatsApp. Please retry.'), findsOneWidget);
    await language.setLanguage(AppLanguage.telugu);
    await tester.pumpAndSettle();
    expect(
      find.text('వాట్సాప్ తెరవలేదు. మళ్లీ ప్రయత్నించండి.'),
      findsOneWidget,
    );
    success = true;
    await tapAction(tester, 'modal-whatsapp-button');
    expect(find.text('వాట్సాప్ తెరవలేదు. మళ్లీ ప్రయత్నించండి.'), findsNothing);
    expect(telemetry.rows.length, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Cancelled authorization records no inquiry and launches no app',
    (tester) async {
      final telemetry = InquiryTelemetry();
      var launches = 0;
      await showSheet(
        tester,
        telemetry: telemetry,
        beforeContact: () async => false,
        launcher: (_) async {
          launches++;
          return true;
        },
      );
      await tapAction(tester, 'modal-call-button');
      expect(telemetry.rows, isEmpty);
      expect(launches, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Guest verification is required and the verified identity is used for telemetry',
    (tester) async {
      final telemetry = InquiryTelemetry();
      var launches = 0;
      final auth = AuthRepository(mockMode: true);
      await auth.signInWithOtp(phone: '9999999999', role: 'shipper');
      await auth.verifyOTP(phone: '9999999999', token: '123456');
      await auth.createUserProfile(
        phone: '9999999999',
        name: 'Farmer',
        role: 'shipper',
      );
      // Use a fresh repository to avoid the sender's 60-second SMS cooldown.
      auth.dispose();
      final guest = AuthRepository(mockMode: true);
      await showSheet(
        tester,
        guest: true,
        authRepository: guest,
        telemetry: telemetry,
        launcher: (_) async {
          launches++;
          return true;
        },
      );
      await tapAction(tester, 'modal-call-button');
      expect(find.byKey(const ValueKey('connect-gate')), findsOneWidget);
      expect(telemetry.rows, isEmpty);
      expect(launches, 0);
      await tester.enterText(
        find.byKey(const ValueKey('connect-phone')),
        '9999999999',
      );
      await tapAction(tester, 'connect-submit');
      await tester.enterText(
        find.byKey(const ValueKey('connect-otp')),
        '123456',
      );
      await tapAction(tester, 'connect-submit');
      expect(launches, 1);
      expect(telemetry.rows.single['caller'], '+919999999999');
      expect(telemetry.rows.single['role'], 'shipper');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Demo and invalid phone records cannot launch or record inquiries',
    (tester) async {
      final telemetry = InquiryTelemetry();
      var launches = 0;
      await showSheet(
        tester,
        target: driver(demo: true),
        telemetry: telemetry,
        launcher: (_) async {
          launches++;
          return true;
        },
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('modal-call-button')),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      await showSheet(
        tester,
        target: driver(phone: '123'),
        telemetry: telemetry,
        launcher: (_) async {
          launches++;
          return true;
        },
      );
      await tapAction(tester, 'modal-call-button');
      expect(find.text('The driver phone number is invalid.'), findsOneWidget);
      expect(telemetry.rows, isEmpty);
      expect(launches, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Sheet supports 320px and doubled text in both languages', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final language = await showSheet(tester, launcher: (_) async => true);
    expect(tester.takeException(), isNull);
    await language.setLanguage(AppLanguage.telugu);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('modal-whatsapp-button')),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining(' / '), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
