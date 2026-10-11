/// data/secure_store.dart — the Keystore-backed key/value store.
///
/// Two things live here and nowhere else: the database encryption key, and the
/// "already activated" marker. Both are small, both must not be readable by
/// another app or by a filesystem dump, and both must survive a reboot.
///
/// `flutter_secure_storage` puts them in the Android Keystore (RSA-OAEP-wrapped
/// AES-GCM), which is the strongest local storage Android offers without a
/// server. SharedPreferences would be plain XML — readable on a rooted device
/// and editable by anything with the file, which is exactly what the activation
/// marker must resist.
///
/// The store is behind an interface so the activation gate and the database can
/// be exercised in a test, where no Keystore exists.
library;

import 'dart:developer' as developer;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
