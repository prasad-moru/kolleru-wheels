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
import 'package:kolleru_wheels/presentation/auth/role_destination.dart';
import 'package:kolleru_wheels/presentation/common/call_button.dart';
import 'package:kolleru_wheels/presentation/driver/driver_registration_screen.dart';
import 'package:kolleru_wheels/presentation/farmer/home_directory_screen.dart';
import 'package:kolleru_wheels/presentation/admin/admin_dashboard_screen.dart';

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
  setUp(() => SharedPreferences.setMockInitialValues({}));
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
    final profile = await auth.verifyOTP(phone: '9876543210', token: '123456');
    expect(profile.phone, '+919876543210');
    final restarted = AuthRepository(mockMode: true);
    expect((await restarted.restoreSession())!.role, 'driver');
    expect(await restarted.getRole(profile.phone), 'driver');
    expect(await restarted.isLiveAdmin(), false);
    await restarted.signOut();
    expect(await restarted.restoreSession(), isNull);
  });
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
        (await auth.verifyOTP(phone: '9876543210', token: '123456')).role,
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
  testWidgets(
    'OTP screen verifies driver and role routing opens registration',
    (tester) async {
      final auth = AuthRepository(mockMode: true);
      UserProfile? verified;
      await tester.pumpWidget(
        MaterialApp(
          home: PhoneOtpScreen(
            repository: auth,
            onVerified: (profile) => verified = profile,
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth-phone')),
        '9876543210',
      );
      await tester.tap(find.byKey(const ValueKey('auth-driver')));
      await tester.tap(find.byKey(const ValueKey('send-otp')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Resend in 60s'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('auth-otp')), '123456');
      await tester.tap(find.byKey(const ValueKey('verify-otp')));
      await tester.pumpAndSettle();
      expect(verified!.role, 'driver');
      await tester.pumpWidget(
        MaterialApp(home: RoleDestination(profile: verified!)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DriverRegistrationScreen), findsOneWidget);
      expect(
        (tester.widget<TextField>(
          find.descendant(
            of: find.byKey(const ValueKey('driver-phone')),
            matching: find.byType(TextField),
          ),
        )).readOnly,
        true,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Shipper returns to directory; cached admin cannot read monitor data',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RoleDestination(
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
