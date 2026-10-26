import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kolleru_wheels/data/models/user_profile_model.dart';
import 'package:kolleru_wheels/data/repositories/auth_repository.dart';
import 'package:kolleru_wheels/data/repositories/driver_activity_repository.dart';

SupabaseClient clientWith(
  Future<http.Response> Function(http.Request) handler,
) {
  final client = SupabaseClient(
    'https://example.supabase.co',
    'public-test-key',
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

  test('Driver activity uses the server-scoped RPC without a client-supplied receiver', () async {
    final auth = AuthRepository(mockMode: true)
      ..currentProfile = const UserProfile(
        phone: '+919876543210',
        role: 'driver',
      );
    addTearDown(auth.dispose);
    final repository = DriverActivityRepository(
      client: clientWith((request) async {
        expect(request.url.path, '/rest/v1/rpc/driver_activity_snapshot');
        expect(request.method, 'POST');
        expect(jsonDecode(request.body), isNull);
        return http.Response(
          jsonEncode({
            'calls_today': 6,
            'recent_calls': [
              {
                'id': 'call-1',
                'created_at': '2026-10-26T08:45:00Z',
                'caller_village_id': 'akividu-town',
                'load_detail': null,
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final activity = await repository.fetchActivity(auth);
    expect(activity.callsToday, 6);
    expect(activity.recentCalls.single.village!.name, 'Akividu Town');
    expect(activity.recentCalls.single.loadDetail, isNull);
    expect(activity.recentCalls.single.createdAt.isUtc, isTrue);
  });

  for (final role in ['shipper', 'admin']) {
    test(
      '$role cannot fetch driver inquiries through the repository',
      () async {
        var requests = 0;
        final auth = AuthRepository(mockMode: true)
          ..currentProfile = UserProfile(phone: '+919876543210', role: role);
        addTearDown(auth.dispose);
        final repository = DriverActivityRepository(
          client: clientWith((request) async {
            requests++;
            return http.Response('{}', 200);
          }),
        );
        await expectLater(repository.fetchActivity(auth), throwsStateError);
        expect(requests, 0);
      },
    );
  }

  test(
    'An endpoint failure is surfaced instead of returning invented activity',
    () async {
      final auth = AuthRepository(mockMode: true)
        ..currentProfile = const UserProfile(
          phone: '+919876543210',
          role: 'driver',
        );
      addTearDown(auth.dispose);
      final repository = DriverActivityRepository(
        client: clientWith(
          (request) async => http.Response(
            '{"message":"Unavailable","code":"503"}',
            503,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      await expectLater(
        repository.fetchActivity(auth),
        throwsA(isA<PostgrestException>()),
      );
    },
  );
}
