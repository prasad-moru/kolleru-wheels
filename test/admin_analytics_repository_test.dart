import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kolleru_wheels/data/models/driver_verification.dart';
import 'package:kolleru_wheels/data/models/user_profile_model.dart';
import 'package:kolleru_wheels/data/repositories/admin_analytics_repository.dart';
import 'package:kolleru_wheels/data/repositories/auth_repository.dart';

class _AuthorizedAdmin extends AuthRepository {
  _AuthorizedAdmin() : super(mockMode: true);
  @override
  Future<bool> isLiveAdmin() async => true;
}

SupabaseClient _client(Future<http.Response> Function(http.Request) handler) {
  final client = SupabaseClient(
    'https://example.supabase.co',
    'test-key',
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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final decision in [
    DriverVerification.approved,
    DriverVerification.rejected,
  ]) {
    test(
      'Admin review sends only driver id and ${decision.name} to the protected RPC',
      () async {
        final auth = _AuthorizedAdmin();
        addTearDown(auth.dispose);
        var requests = 0;
        final repo = AdminAnalyticsRepository(
          client: _client((request) async {
            requests++;
            expect(request.url.path, '/rest/v1/rpc/review_kolleru_driver');
            expect(request.method, 'POST');
            expect(jsonDecode(request.body), {
              'driver_id': 'driver-2',
              'decision': decision.name,
            });
            return http.Response('', 204);
          }),
        );
        await repo.reviewDriver(auth, driverId: 'driver-2', decision: decision);
        expect(requests, 1);
      },
    );
  }

  test(
    'Cached admin and non-admin sessions cannot read or mutate operations data',
    () async {
      var requests = 0;
      final repo = AdminAnalyticsRepository(
        client: _client((_) async {
          requests++;
          return http.Response('[]', 200);
        }),
      );
      for (final role in ['admin', 'driver', 'shipper']) {
        final auth = AuthRepository(mockMode: true)
          ..currentProfile = UserProfile(phone: '+919111111111', role: role);
        addTearDown(auth.dispose);
        await expectLater(repo.fetchSnapshot(auth), throwsStateError);
        await expectLater(
          repo.reviewDriver(
            auth,
            driverId: 'driver-2',
            decision: DriverVerification.approved,
          ),
          throwsStateError,
        );
      }
      expect(requests, 0);
    },
  );

  test(
    'A rejected server mutation propagates instead of reporting approval',
    () async {
      final auth = _AuthorizedAdmin();
      addTearDown(auth.dispose);
      final repo = AdminAnalyticsRepository(
        client: _client(
          (_) async => http.Response(
            '{"message":"Driver has already been reviewed","code":"40001"}',
            409,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      await expectLater(
        repo.reviewDriver(
          auth,
          driverId: 'driver-2',
          decision: DriverVerification.approved,
        ),
        throwsA(isA<PostgrestException>()),
      );
      await expectLater(
        repo.reviewDriver(
          auth,
          driverId: '',
          decision: DriverVerification.pending,
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'Snapshot requests approval data and uses India midnight call boundaries',
    () async {
      final auth = _AuthorizedAdmin();
      addTearDown(auth.dispose);
      final requests = <http.Request>[];
      final repo = AdminAnalyticsRepository(
        now: () => DateTime.utc(2026, 10, 26, 1),
        client: _client((request) async {
          requests.add(request);
          return http.Response(
            '[]',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final snapshot = await repo.fetchSnapshot(auth);
      expect(snapshot.registeredDrivers, 0);
      expect(snapshot.pendingDrivers, isEmpty);
      expect(
        requests
            .singleWhere((r) => r.url.path.endsWith('/drivers'))
            .url
            .queryParameters['select'],
        contains('verification_status'),
      );
      final today = requests.singleWhere(
        (r) =>
            r.url.path.endsWith('/call_telemetry') &&
            r.url.queryParameters['select'] == 'caller_phone,created_at',
      );
      expect(today.url.queryParametersAll['created_at'], [
        'gte.2026-10-25T18:30:00.000Z',
        'lt.2026-10-26T18:30:00.000Z',
      ]);
    },
  );
}
