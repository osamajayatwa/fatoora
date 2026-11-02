import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Retains a request key through timeouts and failed readback. A repository
/// completes it only after the whole operation has returned authoritative data.
/// Only hashes and random keys are persisted, with user and company isolation.
class PendingPostingKeys {
  const PendingPostingKeys._();
  static Future<void> _queue = Future.value();

  static String _storageKey(
    String operation,
    String uid,
    Map<String, dynamic> payload,
  ) {
    Object? canonical(Object? value) {
      if (value is Map) {
        final keys = value.keys.map((key) => key.toString()).toList()..sort();
        return {for (final key in keys) key: canonical(value[key])};
      }
      if (value is List) return value.map(canonical).toList();
      return value;
    }

    final digest = sha256.convert(
      utf8.encode(jsonEncode([operation, uid, canonical(payload)])),
    );
    return 'pending_posting_v1_$digest';
  }

  static Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = _queue.then((_) => operation());
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  static Future<String> acquire(
    String operation,
    String uid,
    Map<String, dynamic> payload,
  ) => _serialized(() async {
    final preferences = await SharedPreferences.getInstance();
    final storageKey = _storageKey(operation, uid, payload);
    final existing = preferences.getString(storageKey);
    if (existing != null) return existing;
    final random = Random.secure();
    final key = List.generate(
      20,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    if (!await preferences.setString(storageKey, key)) {
      throw StateError('Could not retain the posting request key.');
    }
    return key;
  });

  static Future<void> complete(
    String operation,
    String uid,
    Map<String, dynamic> payload,
    String key,
  ) => _serialized(() async {
    final preferences = await SharedPreferences.getInstance();
    final storageKey = _storageKey(operation, uid, payload);
    if (preferences.getString(storageKey) == key) {
      if (!await preferences.remove(storageKey)) {
        throw StateError('Could not complete the posting request key.');
      }
    }
  });
}
