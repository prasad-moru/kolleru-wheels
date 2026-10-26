import 'onboarding_helpers.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kolleru_wheels/data/models/user_profile_model.dart';
import 'package:kolleru_wheels/data/repositories/auth_repository.dart';
import 'package:kolleru_wheels/data/repositories/telemetry_repository.dart';
import 'package:kolleru_wheels/presentation/auth/phone_otp_screen.dart';
import 'package:kolleru_wheels/presentation/auth/complete_profile_screen.dart';
import 'package:kolleru_wheels/presentation/auth/role_destination.dart';
import 'package:kolleru_wheels/presentation/common/call_button.dart';
import 'package:kolleru_wheels/presentation/driver/driver_dashboard_screen.dart';
import 'package:kolleru_wheels/presentation/driver/driver_registration_screen.dart';
import 'package:kolleru_wheels/data/repositories/local_driver_repository.dart';
import 'package:kolleru_wheels/data/repositories/supabase_driver_repository.dart';
import 'package:kolleru_wheels/core/constants/villages.dart';
import 'package:kolleru_wheels/presentation/farmer/home_directory_screen.dart';
import 'package:kolleru_wheels/presentation/admin/admin_dashboard_screen.dart';
import 'package:kolleru_wheels/main.dart';
import 'package:kolleru_wheels/presentation/driver/load_pool_board.dart';
import 'package:kolleru_wheels/presentation/common/mandal_village_picker.dart';

SupabaseClient mockClient(
  Future<http.Response> Function(http.Request) handler,
) {
  final client = SupabaseClient(
    'https://example.supabase.co',
    'public-key',
    httpClient: MockClient((request) async {
      final response = await handler(request);
      return http.Response.bytes(
        response.bodyBytes,
        response.statusCode,
        headers: response.headers,
        request: request,
      );
    }),
  );
  addTearDown(client.dispose);
  return client;
}

http.Response response(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> otpSession() {
  final expiry =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
      1000;
  final payload = base64Url
      .encode(utf8.encode(jsonEncode({'exp': expiry})))
      .replaceAll('=', '');
  return {
    'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.signature',
    'refresh_token': 'refresh',
    'token_type': 'bearer',
    'expires_in': 3600,
    'user': {
      'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'aud': 'authenticated',
      'phone': '919876543210',
      'created_at': '2026-10-07T10:00:00Z',
      'app_metadata': {},
      'user_metadata': {},
    },
  };
}

Map<String, dynamic> cloudDriver({String phone = '9876543210'}) => {
  'id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'user_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'phone': phone,
  'name': 'Existing Driver',
  'base_village_id': 'pulaparru',
  'current_spot_village_id': 'kaikaluru-town',
  'vehicle_type': 'tataAce',
  'capacity_tons': 1.5,
  'vehicle_number': 'AP 39 AB 1234',
  'specializations': ['Live Fish'],
  'is_available': false,
  'card_style': 'aqua_marine',
};

class SlowTelemetry extends TelemetryRepository {
  final completion = Completer<void>();
  bool called = false;
  @override
  Future<void> logCallIntent({
    String? callerPhone,
    required String receiverPhone,
    String? callerRole,
    String contextNote = 'directory',
  }) {
    called = true;
    return completion.future;
  }
}

class AuthorizedTestAdmin extends AuthRepository {
  AuthorizedTestAdmin() : super(mockMode: true);
  @override
  Future<bool> isLiveAdmin() async => true;
}

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'has_seen_welcome': true,
      'selected_language': 'english',
    }),
  );
  test('Indian phone variants normalize to the same verified identity', () {
    for (final phone in [
      '9876543210',
      '+91 98765 43210',
      '919876543210',
      '(+91) 98765-43210',
    ]) {
      expect(AuthRepository.normalizePhone(phone), '+919876543210');
    }
    for (final phone in ['+1 9876543210', '12345', '98letters76543210']) {
      expect(() => AuthRepository.normalizePhone(phone), throwsFormatException);
    }
  });

  test(
    'Owner lookup queries UID and normalized phone and includes busy drivers',
    () async {
      final client = mockClient((request) async {
        expect(request.url.path, '/rest/v1/drivers');
        final query = request.url.queryParameters;
        expect(
          query['or'],
          contains('user_id.eq.aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
        );
        expect(
          query['or'],
          contains('phone.in.(+919876543210,919876543210,9876543210)'),
        );
        expect(query, isNot(contains('is_available')));
        // UID match also handles a row whose phone differs from the current session.
        return response([cloudDriver(phone: '+919999999999')]);
      });
      await client.auth.recoverSession(jsonEncode(otpSession()));
      final driver = (await SupabaseDriverRepository(client: client)
          .getOwnDriver('91 98765 43210'))!;
      expect(driver.phone, '+919876543210');
      expect(driver.isAvailable, isFalse);
      expect(driver.cardStyle, 'aqua_marine');
    },
  );

  test(
    'Older schemas fall back to phone and a failed read uses the owned cache',
    () async {
      var offline = false;
      final client = mockClient((request) async {
        if (offline) throw StateError('Network unavailable');
        if (request.url.queryParameters.containsKey('or')) {
          return response({
            'code': '42703',
            'message': 'column user_id does not exist',
          }, 400);
        }
        expect(request.url.queryParameters['phone'], contains('9876543210'));
        return response([cloudDriver()..remove('user_id')]);
      });
      await client.auth.recoverSession(jsonEncode(otpSession()));
      final repository = SupabaseDriverRepository(client: client);
      expect(
        (await repository.getOwnDriver('9876543210'))!.name,
        'Existing Driver',
      );
      offline = true;
      expect(
        (await repository.getOwnDriver('9876543210'))!.name,
        'Existing Driver',
      );
      await expectLater(
        repository.getOwnDriver('9999999999'),
        throwsStateError,
      );
    },
  );

  test(
    'An empty owner read differs from an offline lookup without a cache',
    () async {
      var offline = false;
      final client = mockClient((request) async {
        if (offline) throw StateError('Network unavailable');
        return response([]);
      });
      await client.auth.recoverSession(jsonEncode(otpSession()));
      final repository = SupabaseDriverRepository(client: client);
      expect(await repository.getOwnDriver('9876543210'), isNull);
      offline = true;
      await expectLater(
        repository.getOwnDriver('9876543210'),
        throwsStateError,
      );
    },
  );

  test('OTP recovers a legacy driver without a user profile and retains the saved card', () async {
    Map<String, dynamic>? identity;
    final client = mockClient((request) async {
      if (request.url.path.endsWith('/otp')) return response({});
      if (request.url.path.endsWith('/verify')) return response(otpSession());
      if (request.url.path == '/rest/v1/drivers') {
        return response([cloudDriver()]);
      }
      expect(request.url.path, '/rest/v1/user_profiles');
      if (request.method == 'POST') {
        identity = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
        expect(identity!['role'], 'driver');
        expect(identity!['user_id'], 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
        return response(identity!);
      }
      return response(identity == null ? [] : [identity]);
    });
    final auth = AuthRepository(client: client, mockMode: false);
    addTearDown(auth.dispose);
    await auth.signInWithOtp(phone: '9876543210', role: 'shipper');
    final identityProfile = await auth.verifyOTP(
      phone: '9876543210',
      token: '123456',
    );
    expect(identityProfile!.role, 'driver');
    expect(auth.onboardingPhone, isNull);
    final restored = (await LocalDriverRepository().getProfile())!;
    expect(restored.phone, '+919876543210');
    expect(restored.isAvailable, isFalse);
    expect(restored.cardStyle, 'aqua_marine');
    expect(restored.id, cloudDriver()['id']);
  });

  testWidgets(
    'Commercial startup reveals no directory or load pool without a session',
    (tester) async {
      final auth = AuthRepository(mockMode: true);
      await tester.pumpWidget(KolleruWheelsApp(authRepository: auth));
      await tester.pumpAndSettle();
      expect(find.byType(PhoneOtpScreen), findsOneWidget);
      expect(find.byType(HomeDirectoryScreen), findsNothing);
      expect(find.byType(LoadPoolBoard), findsNothing);
      await tester.pumpWidget(
        MaterialApp(home: HomeDirectoryScreen(authRepository: auth)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PhoneOtpScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('login-hero')), findsOneWidget);
    },
  );
  testWidgets(
    'Mandal picker restricts villages and clears the previous selection',
    (tester) async {
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Form(
              child: MandalVillagePicker(
                onChanged: (value) => selected = value,
              ),
            ),
          ),
        ),
      );
      await chooseCluster(tester);
      expect(selected, 'pulaparru');
      await tester.tap(find.byKey(const ValueKey('mandal-picker')));
      await tester.pumpAndSettle();
      final kaikaluru = KolleruVillages.mandals.first;
      await tester.tap(
        find.text('${kaikaluru.teluguName} / ${kaikaluru.name}').last,
      );
      await tester.pumpAndSettle();
      expect(selected, isNull);
      final picker = tester.widget<DropdownButtonFormField<String>>(
        find.byKey(const ValueKey('village-picker-kaikaluru')),
      );
      expect(picker.initialValue, isNull);
      await tester.tap(find.byKey(const ValueKey('village-picker-kaikaluru')));
      await tester.pumpAndSettle();
      expect(find.text(KolleruVillages.find('pulaparru')!.label), findsNothing);
      expect(
        find.text(KolleruVillages.find('kaikaluru-town')!.label),
        findsWidgets,
      );
    },
  );
  testWidgets(
    'New driver saves vehicle details and user profile before dashboard',
    (tester) async {
      final auth = AuthRepository(mockMode: true);
      await auth.signInWithOtp(phone: '9876543210', role: 'driver');
      await auth.verifyOTP(phone: '9876543210', token: '123456');
      await tester.pumpWidget(
        MaterialApp(
          home: CompleteProfileScreen(phone: '+919876543210', repository: auth),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('complete-name')),
        'Ramesh',
      );
      await revealInVerticalList(
        tester,
        find.byKey(const ValueKey('complete-driver')),
      );
      await tester.tap(find.byKey(const ValueKey('complete-driver')));
      await chooseCluster(tester);
      await revealInVerticalList(
        tester,
        find.byKey(const ValueKey('vehicle-number-field')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('vehicle-number-field')),
        'AP 39 AB 1234',
      );
      expect(auth.currentProfile, isNull);
      await revealInVerticalList(
        tester,
        find.byKey(const ValueKey('complete-profile')),
      );
      await tester.tap(find.byKey(const ValueKey('complete-profile')));
      await tester.pumpAndSettle();
      expect(find.byType(DriverDashboardScreen), findsOneWidget);
      expect(auth.currentProfile!.role, 'driver');
      expect(auth.currentProfile!.name, 'Ramesh');
      expect(
        (await LocalDriverRepository().getProfile())!.phone,
        '+919876543210',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  test('Missing remote profile is null after OTP, then self registration persists it', () async {
    Map<String, dynamic>? profile;
    final client = mockClient((request) async {
      if (request.url.path.endsWith('/otp')) return response({});
      if (request.url.path.endsWith('/verify')) return response(otpSession());
      if (request.url.path == '/rest/v1/drivers') return response([]);
      expect(request.url.path, '/rest/v1/user_profiles');
      if (request.method == 'POST') {
        expect(request.url.queryParameters['on_conflict'], 'phone');
        expect(
          request.headers['prefer'],
          contains('resolution=ignore-duplicates'),
        );
        final row = jsonDecode(request.body) as Map;
        expect(row['user_id'], 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
        profile = {
          'phone': row['phone'],
          'name': row['name'],
          'role': row['role'],
        };
        return response(profile!);
      }
      expect(request.headers['accept'], 'application/json');
      return response(profile == null ? [] : [profile]);
    });
    final auth = AuthRepository(client: client);
    await auth.signInWithOtp(phone: '9876543210', role: 'shipper');
    expect(await auth.verifyOTP(phone: '9876543210', token: '123456'), isNull);
    expect(auth.onboardingPhone, '+919876543210');
    expect(await auth.getRole('9876543210'), isNull);
    expect(await auth.isLiveAdmin(), false);
    final saved = await auth.createUserProfile(
      phone: '9876543210',
      name: ' Farmer ',
      role: 'shipper',
    );
    expect(saved.name, 'Farmer');
    expect(saved.role, 'shipper');
    expect(auth.onboardingPhone, isNull);
    expect((await auth.restoreSession())!.name, 'Farmer');
  });
  test(
    'Profile creation requires verified phone and never allows admin signup',
    () async {
      final auth = AuthRepository(mockMode: true);
      await expectLater(
        auth.createUserProfile(
          phone: '9876543210',
          name: 'Farmer',
          role: 'shipper',
        ),
        throwsStateError,
      );
      await auth.signInWithOtp(phone: '9876543210', role: 'shipper');
      await auth.verifyOTP(phone: '9876543210', token: '123456');
      final restarted = AuthRepository(mockMode: true);
      expect(await restarted.restoreSession(), isNull);
      expect(restarted.onboardingPhone, '+919876543210');
      await expectLater(
        auth.createUserProfile(
          phone: '9876543210',
          name: 'Farmer',
          role: 'admin',
        ),
        throwsArgumentError,
      );
      await expectLater(
        auth.createUserProfile(
          phone: '9999999999',
          name: 'Farmer',
          role: 'shipper',
        ),
        throwsStateError,
      );
    },
  );
  testWidgets('New shipper completes name and role and reaches the directory', (
    tester,
  ) async {
    final auth = AuthRepository(mockMode: true);
    await auth.signInWithOtp(phone: '9876543210', role: 'shipper');
    await auth.verifyOTP(phone: '9876543210', token: '123456');
    await tester.pumpWidget(
      MaterialApp(
        home: CompleteProfileScreen(phone: '+919876543210', repository: auth),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('complete-name')),
      'Farmer',
    );
    await chooseCluster(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('complete-profile')));
    await tester.tap(find.byKey(const ValueKey('complete-profile')));
    await tester.pumpAndSettle();
    expect(find.byType(HomeDirectoryScreen), findsOneWidget);
    expect(auth.currentProfile!.name, 'Farmer');
    expect(auth.currentProfile!.role, 'shipper');
    await tester.pumpWidget(const SizedBox());
  });
  test('Admin snapshot uses exact counts, India day bounds, and limited newest calls', () async {
    final client = mockClient((request) async {
      if (request.url.path.endsWith('/call_telemetry')) {
        expect(request.url.queryParameters['limit'], '50');
        expect(
          request.url.queryParameters['order'],
          startsWith('created_at.desc'),
        );
        return response([
          {'caller_role': 'driver', 'receiver_phone': '+919876543210'},
        ]);
      }
      var count = 5;
      if (request.url.path.endsWith('/drivers') &&
          request.url.queryParameters['is_available'] == 'eq.true') {
        count = 3;
      }
      if (request.url.path.endsWith('/load_requests')) {
        count = 7;
        expect(
          request.url.queryParametersAll['created_at'],
          containsAll([
            'gte.2026-10-05T18:30:00.000Z',
            'lt.2026-10-06T18:30:00.000Z',
          ]),
        );
      }
      return http.Response('', 200, headers: {'content-range': '0-0/$count'});
    });
    final repository = TelemetryRepository(
      client: client,
      now: () => DateTime.utc(2026, 10, 6, 10),
    );
    final snapshot = await repository.getAdminSnapshot(AuthorizedTestAdmin());
    expect(snapshot['total'], 5);
    expect(snapshot['active'], 3);
    expect(snapshot['loads'], 7);
    expect(snapshot['calls'], hasLength(1));
  });
  test('Corrupt cached identity never grants an active session', () async {
    SharedPreferences.setMockInitialValues({'auth_identity_v1': '{bad json'});
    final auth = AuthRepository(mockMode: true);
    expect(await auth.restoreSession(), isNull);
    expect(await auth.isLiveAdmin(), false);
  });
  test('Demo OTP validates, persists, restores role, and signs out', () async {
    final auth = AuthRepository(mockMode: true);
    await auth.signInWithOtp(phone: '9876543210', role: 'driver');
    await expectLater(
      auth.verifyOTP(phone: '9876543210', token: '000000'),
      throwsFormatException,
    );
    expect(await auth.verifyOTP(phone: '9876543210', token: '123456'), isNull);
    final profile = await auth.createUserProfile(
      phone: '9876543210',
      name: 'Ramesh',
      role: 'driver',
    );
    expect(profile.phone, '+919876543210');
    final restarted = AuthRepository(mockMode: true);
    expect((await restarted.restoreSession())!.role, 'driver');
    expect(await restarted.getRole(profile.phone), 'driver');
    expect(await restarted.isLiveAdmin(), false);
    await restarted.signOut();
    expect(await restarted.restoreSession(), isNull);
  });
  test(
    'Seven days of inactivity expires the session; active restore refreshes it',
    () async {
      var now = DateTime.utc(2026, 10, 6, 10);
      final auth = AuthRepository(mockMode: true, now: () => now);
      await auth.signInWithOtp(phone: '9876543210', role: 'shipper');
      await auth.verifyOTP(phone: '9876543210', token: '123456');
      await auth.createUserProfile(
        phone: '9876543210',
        name: 'Farmer',
        role: 'shipper',
      );

      now = now.add(const Duration(days: 6, hours: 23));
      final restored = AuthRepository(mockMode: true, now: () => now);
      expect((await restored.restoreSession())?.role, 'shipper');

      now = now.add(const Duration(days: 7, minutes: 1));
      final expired = AuthRepository(mockMode: true, now: () => now);
      expect(await expired.restoreSession(), isNull);
      expect(
        (await SharedPreferences.getInstance()).getString('auth_identity_v1'),
        isNull,
      );
    },
  );
  test('Public onboarding cannot select admin, resend early, or replay expired OTP', () async {
    var now = DateTime.utc(2026, 10, 6);
    final auth = AuthRepository(mockMode: true, now: () => now);
    await expectLater(
      auth.signInWithOtp(phone: '9876543210', role: 'admin'),
      throwsArgumentError,
    );
    await expectLater(
      auth.signInWithOtp(phone: '123', role: 'shipper'),
      throwsFormatException,
    );
    await auth.signInWithOtp(phone: '9876543210', role: 'shipper');
    await expectLater(
      auth.signInWithOtp(phone: '9876543210', role: 'shipper'),
      throwsStateError,
    );
    now = now.add(const Duration(minutes: 5));
    await expectLater(
      auth.verifyOTP(phone: '9876543210', token: '123456'),
      throwsFormatException,
    );
  });
  test(
    'Supabase SMS OTP verifies a session and reads the authoritative role',
    () async {
      final calls = <String>[];
      final client = mockClient((request) async {
        calls.add(request.url.path);
        if (request.url.path.endsWith('/otp')) {
          expect((jsonDecode(request.body) as Map)['phone'], '+919876543210');
          return response({});
        }
        if (request.url.path.endsWith('/verify')) {
          expect((jsonDecode(request.body) as Map)['type'], 'sms');
          final expiry =
              DateTime.now()
                  .add(const Duration(hours: 1))
                  .millisecondsSinceEpoch ~/
              1000;
          final payload = base64Url
              .encode(utf8.encode(jsonEncode({'exp': expiry})))
              .replaceAll('=', '');
          return response({
            'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.signature',
            'refresh_token': 'refresh',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
              'aud': 'authenticated',
              'phone': '919876543210',
              'created_at': '2026-10-06T10:00:00Z',
              'app_metadata': {},
              'user_metadata': {},
            },
          });
        }
        expect(request.url.path, '/rest/v1/user_profiles');
        return response({
          'phone': '+919876543210',
          'role': 'shipper',
          'name': 'Farmer',
        });
      });
      final auth = AuthRepository(client: client, mockMode: false);
      await auth.signInWithOtp(phone: '9876543210', role: 'driver');
      expect(
        (await auth.verifyOTP(phone: '9876543210', token: '123456'))!.role,
        'shipper',
      );
      expect(
        calls,
        containsAll([
          '/auth/v1/otp',
          '/auth/v1/verify',
          '/rest/v1/user_profiles',
        ]),
      );
      expect((await auth.restoreSession())!.name, 'Farmer');
    },
  );
  test(
    'Configured auth errors do not fall back to demo authentication',
    () async {
      final client = mockClient(
        (request) async => response({'msg': 'SMS unavailable'}, 400),
      );
      final auth = AuthRepository(client: client, mockMode: false);
      await expectLater(
        auth.signInWithOtp(phone: '9876543210', role: 'driver'),
        throwsA(isA<AuthException>()),
      );
      expect(auth.currentProfile, isNull);
      await expectLater(
        auth.verifyOTP(phone: '9876543210', token: '123456'),
        throwsFormatException,
      );
    },
  );
  test(
    'Call telemetry sends the schema and silently handles rejection',
    () async {
      var reject = false;
      final client = mockClient((request) async {
        expect(request.url.path, '/rest/v1/call_telemetry');
        final row = jsonDecode(request.body) as Map;
        expect(row['caller_phone'], '+919876543210');
        expect(row['receiver_phone'], '+919999999999');
        expect(row['caller_role'], 'driver');
        expect(row['context_note'], 'urgent_load:id');
        return reject
            ? response({'message': 'denied', 'code': '42501'}, 403)
            : response([]);
      });
      final telemetry = TelemetryRepository(client: client);
      for (final denied in [false, true]) {
        reject = denied;
        await telemetry.logCallIntent(
          callerPhone: '+919876543210',
          receiverPhone: '+919999999999',
          callerRole: 'driver',
          contextNote: 'urgent_load:id',
        );
      }
      await expectLater(
        telemetry.getAdminSnapshot(AuthRepository(mockMode: true)),
        throwsStateError,
      );
    },
  );
  testWidgets(
    'Dialer launches before slow telemetry completes, even if logging fails',
    (tester) async {
      final telemetry = SlowTelemetry();
      var launched = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CallButton(
              phone: '+919876543210',
              telemetryRepository: telemetry,
              launcher: (uri) async {
                expect(uri.scheme, 'tel');
                launched = true;
                return true;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(telemetry.called, true);
      expect(launched, true);
      telemetry.completion.completeError(StateError('offline'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Missing login switches to registration with verified phone', (
    tester,
  ) async {
    final auth = AuthRepository(mockMode: true);
    UserProfile? verified;
    await tester.pumpWidget(
      MaterialApp(
        home: PhoneOtpScreen(repository: auth, onVerified: (p) => verified = p),
      ),
    );
    expect(find.byKey(const ValueKey('auth-name')), findsNothing);
    expect(find.byKey(const ValueKey('auth-driver')), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('auth-phone')),
      '9876543210',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('send-otp')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('send-otp')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('auth-otp')), '123456');
    await tester.ensureVisible(find.byKey(const ValueKey('verify-otp')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('verify-otp')));
    await tester.pumpAndSettle();
    expect(verified, isNull);
    expect(find.text('Select Your Role'), findsOneWidget);
    final name = find.byKey(const ValueKey('name-input-field'));
    await revealInVerticalList(tester, name);
    expect(find.text('Verified ✓'), findsOneWidget);
    expect(find.text('9876543210'), findsOneWidget);
    await tester.enterText(name, 'Ramesh');
    await chooseCluster(tester);
    await revealInVerticalList(
      tester,
      find.byKey(const ValueKey('complete-registration-button')),
    );
    await tester.tap(
      find.byKey(const ValueKey('complete-registration-button')),
    );
    await tester.pumpAndSettle();
    expect(verified?.role, 'shipper');
    expect(verified?.villageId, isNotNull);
    expect(find.byType(HomeDirectoryScreen), findsOneWidget);
    expect(find.byType(PhoneOtpScreen), findsNothing);
    expect(find.textContaining('Registration Successful!'), findsOneWidget);
    expect(
      Navigator.of(tester.element(find.byType(HomeDirectoryScreen))).canPop(),
      false,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Register driver collects details after OTP and persists before navigation',
    (tester) async {
      final auth = AuthRepository(mockMode: true);
      await tester.pumpWidget(KolleruWheelsApp(authRepository: auth));
      await tester.pumpAndSettle();
      final registerTab = find.byKey(const ValueKey('register-tab'));
      await revealInVerticalList(tester, registerTab);
      await tester.tap(registerTab);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('auth-phone')),
        '9876543210',
      );
      expect(await LocalDriverRepository().getProfile(), isNull);
      await revealInVerticalList(
        tester,
        find.byKey(const ValueKey('send-otp')),
      );
      await tester.tap(find.byKey(const ValueKey('send-otp')));
      await tester.pumpAndSettle();
      expect(auth.currentProfile, isNull);
      await tester.enterText(find.byKey(const ValueKey('auth-otp')), '123456');
      await revealInVerticalList(
        tester,
        find.byKey(const ValueKey('verify-otp')),
      );
      await tester.tap(find.byKey(const ValueKey('verify-otp')));
      await tester.pumpAndSettle();
      await revealInVerticalList(
        tester,
        find.byKey(const ValueKey('role-card-driver')),
      );
      await tester.tap(find.byKey(const ValueKey('role-card-driver')));
      await tester.pumpAndSettle();
      await revealInVerticalList(
        tester,
        find.byKey(const ValueKey('name-input-field')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('name-input-field')),
        'Ramesh',
      );
      await chooseCluster(tester);
      await revealInVerticalList(
        tester,
        find.byKey(const ValueKey('vehicle-number-field')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('vehicle-number-field')),
        'AP 16 AB 1234',
      );
      expect(auth.currentProfile, isNull);
      await revealInVerticalList(
        tester,
        find.byKey(const ValueKey('complete-registration-button')),
      );
      await tester.tap(
        find.byKey(const ValueKey('complete-registration-button')),
      );
      await tester.pumpAndSettle();
      expect(auth.currentProfile?.role, 'driver');
      expect(find.byType(DriverDashboardScreen), findsOneWidget);
      expect(find.byType(DriverRegistrationScreen), findsNothing);
      expect(find.byType(PhoneOtpScreen), findsNothing);
      expect(find.textContaining('Registration Successful!'), findsOneWidget);
      expect(
        Navigator.of(tester.element(find.byType(DriverDashboardScreen)))
            .canPop(),
        false,
      );
      final driver = await LocalDriverRepository().getProfile();
      expect(driver?.capacityTons, 2.5);
      expect(driver?.phone, '+919876543210');
      expect(driver?.vehicleNumber, 'AP 16 AB 1234');
      final restored = await AuthRepository(mockMode: true).restoreSession();
      expect(restored?.role, 'driver');
      expect(restored?.phone, driver?.phone);
      await tester.pumpWidget(
        KolleruWheelsApp(
          key: const ValueKey('restart'),
          authRepository: AuthRepository(mockMode: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DriverDashboardScreen), findsOneWidget);
      expect(find.byType(DriverRegistrationScreen), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'Register OTP defers an existing identity until coordinated completion',
    () async {
      final signup = AuthRepository(mockMode: true);
      await signup.signInWithOtp(phone: '9876543210', role: 'shipper');
      await signup.verifyOTP(phone: '9876543210', token: '123456');
      await signup.createUserProfile(
        phone: '9876543210',
        name: 'Farmer',
        role: 'shipper',
      );
      await signup.signOut();
      final auth = AuthRepository(mockMode: true);
      await auth.signInWithOtp(phone: '9876543210', role: 'shipper');
      final existing = await auth.verifyOTP(
        phone: '9876543210',
        token: '123456',
        publishSession: false,
      );
      expect(existing?.role, 'shipper');
      expect(auth.currentProfile, isNull);
      expect(await AuthRepository(mockMode: true).restoreSession(), isNull);
      final profile = await auth.completeRegistration(
        phone: '9876543210',
        name: 'Farmer',
        role: 'shipper',
        villageId: KolleruVillages.mandals.first.villages.first.id,
      );
      expect(auth.currentProfile, same(profile));
      expect(
        (await AuthRepository(mockMode: true).restoreSession())?.phone,
        profile.phone,
      );
    },
  );
  testWidgets('Existing Login routes through the gated session router', (
    tester,
  ) async {
    final signup = AuthRepository(mockMode: true);
    await signup.signInWithOtp(phone: '9876543210', role: 'shipper');
    await signup.verifyOTP(phone: '9876543210', token: '123456');
    await signup.createUserProfile(
      phone: '9876543210',
      name: 'Farmer',
      role: 'shipper',
    );
    await signup.signOut();
    final auth = AuthRepository(mockMode: true);
    await tester.pumpWidget(KolleruWheelsApp(authRepository: auth));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('auth-phone')),
      '9876543210',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('send-otp')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('send-otp')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('auth-otp')), '123456');
    await tester.ensureVisible(find.byKey(const ValueKey('verify-otp')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('verify-otp')));
    await tester.pumpAndSettle();
    expect(find.byType(HomeDirectoryScreen), findsOneWidget);
    expect(find.byType(PhoneOtpScreen), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Shipper returns to directory; cached admin cannot read monitor data',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RoleDestination(
            authRepository: AuthRepository(mockMode: true)
              ..currentProfile = const UserProfile(
                phone: '+919876543210',
                role: 'shipper',
              ),
            profile: UserProfile(phone: '+919876543210', role: 'shipper'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(HomeDirectoryScreen), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: AdminDashboardScreen(
            authRepository: AuthRepository(mockMode: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Admin authorization'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
