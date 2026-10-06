import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/load_request_model.dart';
import '../models/vehicle_type.dart';
import '../../core/constants/villages.dart';
import '../../core/utils/proximity_matcher.dart';

/// Shared locally across farmer and driver views. A backend is needed for
/// requests from other phones; writes notify listeners only after persistence.
class LoadRequestRepository extends ChangeNotifier {
  LoadRequestRepository({DateTime Function()? now})
    : _now = now ?? DateTime.now;
  static LoadRequestRepository instance = LoadRequestRepository();
  static const storageKey = 'urgent_load_requests_v1';
  final DateTime Function() _now;
  List<LoadRequestModel>? _requests;
  Future<void>? _pending;
  DateTime get currentTime => _now();

  Future<T> _serial<T>(Future<T> Function() operation) {
    final previous = _pending;
    final result = previous == null
        ? Future<T>.sync(operation)
        : previous.then((_) => operation());
    late final Future<void> tail;
    void clear() {
      if (identical(_pending, tail)) _pending = null;
    }

    tail = result.then<void>(
      (_) => clear(),
      onError: (Object error, StackTrace stack) => clear(),
    );
    _pending = tail;
    return result;
  }

  Future<void> _load() async {
    if (_requests != null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    _requests = raw == null
        ? []
        : (jsonDecode(raw) as List)
              .map(
                (e) => LoadRequestModel.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ),
              )
              .toList();
  }

  Future<void> _commit(List<LoadRequestModel> requests) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
      storageKey,
      jsonEncode(requests.map((r) => r.toJson()).toList()),
    )) {
      throw StateError('Could not save load requests');
    }
    _requests = requests;
    notifyListeners();
  }

  Future<LoadRequestModel> createRequest({
    required String posterName,
    required String posterPhone,
    required String fromLocation,
    String? toVillageId,
    Village? toVillage,
    required String materialType,
    VehicleType? vehicleTypeNeeded,
  }) => _serial(() async {
    final destinationId = toVillage?.id ?? toVillageId;
    if (posterName.trim().isEmpty ||
        !RegExp(r'^\+91[6-9][0-9]{9}$').hasMatch(posterPhone) ||
        fromLocation.trim().isEmpty ||
        materialType.trim().isEmpty ||
        KolleruVillages.find(destinationId) == null) {
      throw const FormatException('Invalid urgent request');
    }
    await _load();
    final now = _now();
    // ID does not depend on the injected clock's resolution.
    final request = LoadRequestModel(
      id: const Uuid().v4(),
      posterName: posterName.trim(),
      posterPhone: posterPhone,
      fromLocation: fromLocation.trim(),
      toVillageId: destinationId!,
      materialType: materialType.trim(),
      vehicleTypeNeeded: vehicleTypeNeeded,
      createdAt: now,
    );
    await _commit([..._requests!.where((r) => r.isActiveAt(now)), request]);
    return request;
  });

  Future<List<LoadRequestModel>> getActiveRequests({
    String? operationalMandalId,
  }) => _serial(() async {
    await _load();
    final now = _now();
    final active =
        _requests!
            .where(
              (r) =>
                  r.isActiveAt(now) &&
                  (operationalMandalId == null ||
                      ProximityMatcher.mandalId(r.toVillageId) ==
                          operationalMandalId),
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(active);
  });

  Future<void> closeRequest(String id) => _serial(() async {
    await _load();
    if (!_requests!.any((r) => r.id == id)) return;
    await _commit([for (final r in _requests!) r.id == id ? r.close() : r]);
  });
}
