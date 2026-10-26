import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kolleru_wheels/core/localization/app_language_provider.dart';
import 'package:kolleru_wheels/data/models/user_profile_model.dart';
import 'package:kolleru_wheels/data/repositories/auth_repository.dart';
import 'package:kolleru_wheels/data/repositories/local_driver_repository.dart';
import 'package:kolleru_wheels/main.dart';
import 'package:kolleru_wheels/presentation/auth/complete_profile_screen.dart';
import 'package:kolleru_wheels/presentation/auth/phone_otp_screen.dart';
import 'package:kolleru_wheels/presentation/farmer/home_directory_screen.dart';
import 'package:kolleru_wheels/presentation/driver/driver_registration_screen.dart';
import 'package:kolleru_wheels/presentation/onboarding/components/aqua_illustrations.dart';
import 'package:kolleru_wheels/presentation/onboarding/welcome_discovery_screen.dart';

import 'onboarding_helpers.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'Language defaults to Telugu, persists and restores the last rapid choice',
    () async {
      final language = AppLanguageProvider();
      addTearDown(language.dispose);
      await language.load();
      expect(language.selectedLanguage, AppLanguage.telugu);
      expect(language.tr(te: 'పేరు', en: 'Name'), 'పేరు');
      await language.setLanguage(AppLanguage.english);
      expect(language.tr(te: 'పేరు', en: 'Name'), 'Name');
      await Future.wait([language.toggleLanguage(), language.toggleLanguage()]);
      final restored = AppLanguageProvider();
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.selectedLanguage, AppLanguage.english);
      expect(
        (await SharedPreferences.getInstance()).getString('selected_language'),
        'english',
      );
    },
  );

  test(
    'A pending preference read cannot replace a new language selection',
    () async {
      final language = AppLanguageProvider();
      addTearDown(language.dispose);
      final loading = language.load();
      await language.setLanguage(AppLanguage.english);
      await loading;
      expect(language.selectedLanguage, AppLanguage.english);
    },
  );

  testWidgets(
    'First launch discovers three slides and remembers language and completion',
    (tester) async {
      final auth = AuthRepository(mockMode: true);
      addTearDown(auth.dispose);
      await tester.pumpWidget(KolleruWheelsApp(authRepository: auth));
      await tester.pumpAndSettle();
      expect(find.byType(WelcomeDiscoveryScreen), findsOneWidget);
      expect(find.byType(PhoneOtpScreen), findsNothing);
      expect(find.text('OTP పొందండి'), findsOneWidget);
      expect(find.textContaining(' / '), findsNothing);

      await tester.tap(find.byKey(const ValueKey('language-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('Get OTP'), findsOneWidget);
      expect(find.text('Choose Vehicle for Any Load'), findsOneWidget);
      final pages = find.byKey(const ValueKey('welcome-pages'));
      await tester.drag(pages, const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(tester.widget<PageView>(pages).controller!.page, closeTo(1, 0.01));
      expect(find.text('Check Driver & Ton Capacity'), findsOneWidget);
      await tester.drag(pages, const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(tester.widget<PageView>(pages).controller!.page, closeTo(2, 0.01));
      expect(find.text('Direct Call & Zero Commission'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('phone-input-field')),
        '9876543210',
      );
      await tester.tap(find.byKey(const ValueKey('get-otp-button')));
      await tester.pumpAndSettle();
      expect(find.byType(PhoneOtpScreen), findsOneWidget);
      expect(find.byType(WelcomeDiscoveryScreen), findsNothing);
      expect(find.byKey(const ValueKey('browse-guest')), findsOneWidget);
      expect(
        Navigator.of(tester.element(find.byType(PhoneOtpScreen))).canPop(),
        isFalse,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('has_seen_welcome'), isTrue);
      expect(prefs.getString('selected_language'), 'english');
      expect(find.byKey(const ValueKey('auth-otp')), findsOneWidget);
      expect(find.textContaining(' / '), findsNothing);

      await tester.pumpWidget(const SizedBox());
      final restarted = AuthRepository(mockMode: true);
      addTearDown(restarted.dispose);
      await tester.pumpWidget(KolleruWheelsApp(authRepository: restarted));
      await tester.pumpAndSettle();
      expect(find.byType(WelcomeDiscoveryScreen), findsNothing);
      expect(find.byType(PhoneOtpScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Discovery validates phone and opens the directory without authentication',
    (tester) async {
      final auth = AuthRepository(mockMode: true);
      addTearDown(auth.dispose);
      await tester.pumpWidget(KolleruWheelsApp(authRepository: auth));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('get-otp-button')));
      await tester.pumpAndSettle();
      expect(find.text('సరైన 10 అంకెల మొబైల్ నెంబర్ ఇవ్వండి'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('phone-input-field')),
        '9876543210',
      );
      await tester.tap(find.byKey(const ValueKey('language-toggle')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('phone-input-field')),
            )
            .controller!
            .text,
        '9876543210',
      );
      expect(find.text('Explore Available Vehicles'), findsOneWidget);
      final guest = find.byKey(const ValueKey('guest-exit-button'));
      await tester.ensureVisible(guest);
      await tester.tap(guest);
      await tester.pumpAndSettle();
      expect(auth.isGuest, isTrue);
      expect(find.byType(HomeDirectoryScreen), findsOneWidget);
      expect(find.byType(PhoneOtpScreen), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Returning authenticated users retain their authoritative route',
    (tester) async {
      SharedPreferences.setMockInitialValues({'has_seen_welcome': true});
      final auth = AuthRepository(mockMode: true)
        ..currentProfile = const UserProfile(
          phone: '+919876543210',
          role: 'shipper',
          name: 'Farmer',
        );
      addTearDown(auth.dispose);
      await tester.pumpWidget(KolleruWheelsApp(authRepository: auth));
      await tester.pumpAndSettle();
      expect(find.byType(HomeDirectoryScreen), findsOneWidget);
      expect(find.byType(WelcomeDiscoveryScreen), findsNothing);
      expect(find.byType(PhoneOtpScreen), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Auth language changes preserve typed data and existing keys', (
    tester,
  ) async {
    final auth = AuthRepository(mockMode: true);
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: PhoneOtpScreen(repository: auth, onVerified: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    final phone = find.byKey(const ValueKey('auth-phone'));
    await revealInVerticalList(tester, phone);
    await tester.enterText(phone, '9876543210');
    await tester.tap(find.byKey(const ValueKey('language-toggle')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(phone).controller!.text, '9876543210');
    expect(find.text('Phone number'), findsOneWidget);
    expect(find.byKey(const ValueKey('send-otp')), findsOneWidget);
    expect(find.byKey(const ValueKey('browse-guest')), findsOneWidget);
    expect(find.textContaining(' / '), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Farmer onboarding shows one language and switches location labels',
    (tester) async {
      final auth = AuthRepository(mockMode: true);
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: CompleteProfileScreen(phone: '+919876543210', repository: auth),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('onboarding-back')), findsOneWidget);
      expect(find.textContaining(' / '), findsNothing);
      await tester.tap(find.byKey(const ValueKey('language-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('Kolleru Wheels Registration'), findsOneWidget);
      await revealInVerticalList(
        tester,
        find.byKey(const ValueKey('mandal-dropdown')),
      );
      expect(find.text('Your Mandal'), findsOneWidget);
      expect(find.text('Village or Base'), findsOneWidget);
      expect(find.textContaining(' / '), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Driver registration switches language without losing form values',
    (tester) async {
      final auth = AuthRepository(mockMode: true);
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: DriverRegistrationScreen(
            repository: LocalDriverRepository(),
            authRepository: auth,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final name = find.byKey(const ValueKey('driver-name'));
      await revealInVerticalList(tester, name);
      await tester.enterText(name, 'Ramesh');
      expect(find.textContaining(' / '), findsNothing);
      await tester.tap(find.byKey(const ValueKey('language-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('Driver registration'), findsOneWidget);
      expect(tester.widget<TextFormField>(name).controller!.text, 'Ramesh');
      await revealInVerticalList(
        tester,
        find.byKey(const ValueKey('driver-specialization-2')),
      );
      expect(find.text('Live Fish'), findsOneWidget);
      expect(find.textContaining(' / '), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Existing validation errors follow the selected language', (
    tester,
  ) async {
    final auth = AuthRepository(mockMode: true);
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: PhoneOtpScreen(repository: auth, onVerified: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    final phone = find.byKey(const ValueKey('auth-phone'));
    await revealInVerticalList(tester, phone);
    await tester.enterText(phone, '987');
    final send = find.byKey(const ValueKey('send-otp'));
    await revealInVerticalList(tester, send);
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(find.text('సరైన 10 అంకెల మొబైల్ నెంబర్ ఇవ్వండి'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('language-toggle')));
    await tester.pumpAndSettle();
    expect(
      find.text('Enter a valid 10-digit Indian mobile number'),
      findsOneWidget,
    );
    expect(find.text('సరైన 10 అంకెల మొబైల్ నెంబర్ ఇవ్వండి'), findsNothing);
    expect(tester.widget<TextFormField>(phone).controller!.text, '987');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Welcome supports narrow screens and enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final auth = AuthRepository(mockMode: true);
    addTearDown(auth.dispose);
    await tester.pumpWidget(KolleruWheelsApp(authRepository: auth));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final start = find.byKey(const ValueKey('get-otp-button'));
    await tester.ensureVisible(start);
    await tester.pumpAndSettle();
    expect(tester.getRect(start).bottom, lessThanOrEqualTo(640));
    await tester.tap(find.byKey(const ValueKey('language-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Get OTP'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (var step = 0; step < 3; step++) {
    testWidgets('Vector illustration $step paints offline in both languages', (
      tester,
    ) async {
      for (final language in AppLanguage.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 280,
                  child: OnboardingIllustrationCard(
                    step: step,
                    language: language,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('welcome-illustration-$step')),
          findsOneWidget,
        );
        expect(find.byType(Image), findsNothing);
        expect(tester.takeException(), isNull);
      }
    });
  }
}
