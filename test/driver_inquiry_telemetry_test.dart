import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kolleru_wheels/data/repositories/telemetry_repository.dart';

void main() {
  test('Call and WhatsApp each insert one inquiry for the receiver used by daily activity', () async {
    final rows = <Map<String, dynamic>>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'public-test-key',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/rest/v1/call_telemetry');
        expect(request.method, 'POST');
        rows.add(Map<String, dynamic>.from(jsonDecode(request.body) as Map));
        return http.Response('', 201, request: request);
      }),
    );
    addTearDown(client.dispose);
    final telemetry = TelemetryRepository(client: client);
    for (final method in DriverContactMethod.values) {
      await telemetry.logDriverInquiry(
        driverId: 'driver-1',
        receiverPhone: '+919876543210',
        callerPhone: '+919999999999',
        callerRole: 'shipper',
        method: method,
      );
    }
    expect(rows.length, 2);
    expect(
      rows.map((row) => row['receiver_phone']),
      everyElement('+919876543210'),
    );
    expect(rows.map((row) => row['caller_role']), everyElement('shipper'));
    expect(rows.map((row) => row['context_note']).toList(), [
      'driver_connect:driver-1:call',
      'driver_connect:driver-1:whatsapp',
    ]);
    // The backend trigger supplies authoritative timestamps and identity.
    expect(rows.any((row) => row.containsKey('created_at')), isFalse);
  });
}
