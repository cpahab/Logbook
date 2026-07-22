import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

import 'crypto_service.dart';

/// Stores each logbook's AES-256 encryption key in the OS Keychain/Keystore.
///
/// One key per logbook, generated once (by whichever device creates the
/// logbook) and shared with guests via the QR-invite flow
/// (logbook_service.dart) rather than derived from anything else — see
/// CryptoService's doc comment for why a plain shared key, not per-member
/// wrapping. A device that hasn't imported the key yet (e.g. a guest who
/// joined by typed code rather than QR scan) simply has no key stored for
/// that logbook until it's shared with them some other way; that logbook's
/// entries stay undecryptable on that device until then.
class LogbookKeyStore {
  const LogbookKeyStore._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static final Map<String, CryptoService> _cryptoCache = {};

  static String _storageKey(String logbookId) => 'logbook_key_v1_$logbookId';

  /// Returns a cached [CryptoService] for [logbookId], resolving (and
  /// caching) its key via [getOrCreateKey] on first call. Used by
  /// `PhotoService`'s static methods, which run once per photo (unlike
  /// `FirestoreService`/`StorageService`, constructed once per logbook
  /// attach) and would otherwise re-read secure storage on every photo view.
  static Future<CryptoService> getCryptoService(String logbookId) async {
    final cached = _cryptoCache[logbookId];
    if (cached != null) return cached;
    final key = await getOrCreateKey(logbookId);
    return _cryptoCache[logbookId] = CryptoService(key);
  }

  /// Returns the existing key for [logbookId], generating and persisting a
  /// fresh random AES-256 key if none exists yet on this device — e.g. a
  /// brand-new local-only logbook, or the very first device to create a
  /// shared one.
  static Future<SecretKey> getOrCreateKey(String logbookId) async {
    final existing = await loadKey(logbookId);
    if (existing != null) return existing;
    final key = await AesGcm.with256bits().newSecretKey();
    await _storage.write(
      key: _storageKey(logbookId),
      value: base64Encode(await key.extractBytes()),
    );
    return key;
  }

  /// Loads the stored key for [logbookId] as a [SecretKey], or null if none
  /// exists on this device yet.
  static Future<SecretKey?> loadKey(String logbookId) async {
    final b64 = await _storage.read(key: _storageKey(logbookId));
    return b64 == null ? null : SecretKey(base64Decode(b64));
  }

  /// The raw base64-encoded key for [logbookId], for embedding in a QR
  /// invite payload — or null if this device has no key for it yet.
  static Future<String?> exportKeyBase64(String logbookId) =>
      _storage.read(key: _storageKey(logbookId));

  /// Stores a key shared by another member (e.g. scanned from a QR invite)
  /// for [logbookId], overwriting any key already stored for it.
  static Future<void> importKeyBase64(String logbookId, String base64Key) async {
    await _storage.write(key: _storageKey(logbookId), value: base64Key);
    _cryptoCache.remove(logbookId);
  }

  /// Removes the stored key for [logbookId] on this device — used when
  /// leaving/deleting a logbook. Only removes it from *this* device; per
  /// the encryption assessment's stated limitation, this cannot revoke
  /// access from any other member's device that already holds the key.
  static Future<void> forgetKey(String logbookId) async {
    await _storage.delete(key: _storageKey(logbookId));
    _cryptoCache.remove(logbookId);
  }
}

/// Stores this device's own local Hive-at-rest encryption key — deliberately
/// a *separate* secret from any [LogbookKeyStore] logbook key, never shared,
/// and never rotated when the active logbook changes.
///
/// Cloud logbook switching (`HomeRepository.reattachAndSync`) reuses the
/// same on-disk Hive boxes in place (clears and repopulates them) rather
/// than closing and reopening them per logbook — so a Hive box's cipher
/// must stay fixed for the process lifetime regardless of which logbook's
/// data currently sits inside it. Scoping the Hive key to the *device*
/// instead of the logbook sidesteps that entirely: this key only protects
/// the local database file at rest (e.g. a lost/stolen device), which has
/// nothing to do with which logbook a device happens to be viewing.
class DeviceHiveKeyStore {
  const DeviceHiveKeyStore._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const _storageKey = 'device_hive_key_v1';
  static HiveAesCipher? _cachedCipher;

  /// Returns this device's Hive encryption key as raw bytes (32 bytes, for
  /// `HiveAesCipher`), generating and persisting a fresh random one on first
  /// call.
  static Future<List<int>> getOrCreateKeyBytes() async {
    final existing = await _storage.read(key: _storageKey);
    if (existing != null) return base64Decode(existing);
    final key = await AesGcm.with256bits().newSecretKey();
    final bytes = await key.extractBytes();
    await _storage.write(key: _storageKey, value: base64Encode(bytes));
    return bytes;
  }

  /// Returns this device's `HiveAesCipher`, cached in memory for the process
  /// lifetime after the first call — every `Hive.openBox` call site across
  /// the app (main.dart, theme_provider.dart, local_logbook_service.dart)
  /// needs the same cipher instance, and re-reading secure storage on every
  /// box open would be needless overhead.
  static Future<HiveAesCipher> getOrCreateCipher() async =>
      _cachedCipher ??= HiveAesCipher(await getOrCreateKeyBytes());
}
