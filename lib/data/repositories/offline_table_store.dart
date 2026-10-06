import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Repository-owned cache and durable pending writes, not an authentication store.
class OfflineTableStore {
  const OfflineTableStore(this.table);
  final String table;
  String get cacheKey => 'supabase_${table}_cache_v1';
  String get pendingKey => 'supabase_${table}_pending_v1';
  Future<List<Map<String, dynamic>>> read(String key) async {
    final raw = (await SharedPreferences.getInstance()).getString(key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> write(String key, List<Map<String, dynamic>> rows) async {
    if (!await (await SharedPreferences.getInstance()).setString(
      key,
      jsonEncode(rows),
    )) {
      throw StateError('Could not persist $table cache');
    }
  }

  Future<void> put(String key, Map<String, dynamic> row) async {
    final rows = await read(key);
    await write(key, [...rows.where((r) => r['id'] != row['id']), row]);
  }

  Future<void> remove(String key, String id) async {
    await write(key, (await read(key)).where((r) => r['id'] != id).toList());
  }

  static String cloudId(String table, String id) =>
      RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(id)
      ? id
      : const Uuid().v5(Namespace.url.value, 'kolleru-wheels:$table:$id');
}

/// Keep a repository's cache/outbox edits and network operations in order.
class RepositoryQueue {
  Future<void>? _pending;
  Future<T> run<T>(Future<T> Function() operation) {
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
}
