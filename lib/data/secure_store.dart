/// data/secure_store.dart — key/value storage for secrets and the activation marker.
///
/// Two different stores for two different jobs:
///
///   KeystoreStore — the database encryption key. This IS a secret: anyone who
///   reads it can open the database file. It lives in the Android Keystore
///   (RSA-OAEP-wrapped AES-GCM), the strongest local storage Android offers.
///
///   PrefsStore — the "already activated" marker. This is NOT a secret: the
///   activation CODE is the secret, and it is stored only as a hash. The marker
///   is a single boolean, so plain SharedPreferences is enough. Keystore-backed
///   storage proved unreliable on API 25 devices — it silently failed to persist.
///
/// The store is behind an interface so the activation gate and the database can
/// be exercised in a test, where no Keystore exists.
library;

import 'dart:developer' as developer;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The operations the app needs from secure storage.
abstract class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<bool> contains(String key);
}

/// The real store, backed by the Android Keystore.
class KeystoreStore implements SecureStore {
  KeystoreStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              // The plugin's Android backend. encryptedSharedPreferences was
              // deprecated upstream in favour of the RSA-OAEP path this selects;
              // the option is set explicitly so the choice is visible rather
              // than implied by a plugin default that may change.
              aOptions: AndroidOptions(),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      // A Keystore read can fail after a device restore or an OS upgrade that
      // invalidates the key. Returning null lets the caller fall back (the
      // database then cannot open, and says so in Arabic) instead of crashing.
      developer.log('secure read failed for "$key": $e', name: 'secure_store');
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      developer.log('secure write failed for "$key": $e', name: 'secure_store');
      rethrow;
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      developer.log('secure delete failed for "$key": $e', name: 'secure_store');
    }
  }

  @override
  Future<bool> contains(String key) async {
    try {
      return await _storage.containsKey(key: key);
    } catch (e) {
      return false;
    }
  }
}

/// SharedPreferences-backed store for the activation marker.
///
/// The marker is a single boolean, not a secret: the activation CODE is the
/// secret, and it is stored only as a hash (see domain/activation.dart).
/// Keystore-backed storage proved unreliable on API 25 devices — it silently
/// failed to persist — so the marker lives in plain SharedPreferences instead.
class PrefsStore implements SecureStore {
  PrefsStore._(this._prefs);

  final SharedPreferences _prefs;

  static Future<PrefsStore> create() async {
    final prefs = await SharedPreferences.getInstance();
    return PrefsStore._(prefs);
  }

  @override
  Future<String?> read(String key) async => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) async {
    await _prefs.setString(key, value);
  }

  @override
  Future<void> delete(String key) async => _prefs.remove(key);

  @override
  Future<bool> contains(String key) async => _prefs.containsKey(key);
}

/// An in-memory store for tests, and for the desktop/web builds where the
/// Keystore does not exist.
///
/// Deliberately NOT persisted: a fallback that silently writes the database key
/// to a plain file would be worse than refusing to run, so this exists for
/// tests only and the app never selects it in production.
class MemoryStore implements SecureStore {
  MemoryStore([Map<String, String>? initial]) : _values = {...?initial};

  final Map<String, String> _values;

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<bool> contains(String key) async => _values.containsKey(key);
}
