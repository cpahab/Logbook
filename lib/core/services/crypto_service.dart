import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// AES-256-GCM primitives for encrypting sensitive Firestore fields, photo
/// bytes, and GPS track blobs, backed by a single per-logbook symmetric key
/// (see [LogbookKeyStore]). Deliberately a plain shared key, not a
/// per-member asymmetric envelope scheme — this app's trust model is a crew
/// who already trust each other with a shared logbook, so sharing the key
/// itself directly (via the existing QR-invite flow) is an acceptable and
/// far simpler design than per-member key wrapping.
class CryptoService {
  CryptoService(this._key);

  final SecretKey _key;

  static final _algorithm = AesGcm.with256bits();

  /// Encrypts [plaintext] into a small JSON-safe envelope map, storable
  /// directly as a Firestore field value in place of the plain string. `v`
  /// is a format version so a future scheme change could coexist with
  /// entries encrypted under this one.
  ///
  /// [AesGcm.encrypt] generates a fresh random nonce for every call (visible
  /// on the returned [SecretBox]) — never replace this with a fixed or
  /// derived nonce, since reusing a nonce under the same key breaks AES-GCM's
  /// security guarantees entirely (key/plaintext recovery becomes possible).
  Future<Map<String, dynamic>> encryptText(String plaintext) async {
    final box = await _algorithm.encrypt(utf8.encode(plaintext), secretKey: _key);
    return {
      'v': 1,
      'n': base64Encode(box.nonce),
      'c': base64Encode(box.cipherText),
      'm': base64Encode(box.mac.bytes),
    };
  }

  /// Reverses [encryptText]. Throws [SecretBoxAuthenticationError] if the
  /// MAC doesn't match (tampered/corrupted ciphertext, or wrong key).
  Future<String> decryptText(Map<String, dynamic> envelope) async =>
      utf8.decode(await _decryptEnvelope(envelope));

  /// Encrypts a whole JSON-serializable object (one CrewMember,
  /// TimelineEntry, or TimelineAmendment) as a single envelope — one nonce
  /// per sub-object rather than one per individual string field, since
  /// these are always read/written as whole units.
  Future<Map<String, dynamic>> encryptJson(Map<String, dynamic> value) =>
      encryptText(jsonEncode(value));

  Future<Map<String, dynamic>> decryptJson(Map<String, dynamic> envelope) async =>
      jsonDecode(await decryptText(envelope)) as Map<String, dynamic>;

  /// Encrypts arbitrary bytes (a photo file, a GPX blob) into a single
  /// self-describing blob — nonce + ciphertext + MAC concatenated — so the
  /// stored Firebase Storage object needs no separate metadata to decrypt.
  /// Nonce handling is the same as [encryptText]: freshly generated per call,
  /// never fixed or derived.
  Future<Uint8List> encryptBytes(Uint8List plaintext) async {
    final box = await _algorithm.encrypt(plaintext, secretKey: _key);
    return box.concatenation();
  }

  /// Reverses [encryptBytes]. Throws [SecretBoxAuthenticationError] if the
  /// MAC doesn't match, or a [RangeError] if [blob] is too short to contain
  /// a valid nonce+MAC.
  Future<Uint8List> decryptBytes(Uint8List blob) async {
    final box = SecretBox.fromConcatenation(
      blob,
      nonceLength: _algorithm.nonceLength,
      macLength: _algorithm.macAlgorithm.macLength,
    );
    final clear = await _algorithm.decrypt(box, secretKey: _key);
    return Uint8List.fromList(clear);
  }

  Future<Uint8List> _decryptEnvelope(Map<String, dynamic> envelope) async {
    final box = SecretBox(
      base64Decode(envelope['c'] as String),
      nonce: base64Decode(envelope['n'] as String),
      mac: Mac(base64Decode(envelope['m'] as String)),
    );
    final clear = await _algorithm.decrypt(box, secretKey: _key);
    return Uint8List.fromList(clear);
  }

  /// True if [value] looks like an encrypted-field envelope produced by
  /// [encryptText]/[encryptJson] — used at the Firestore/backup read
  /// boundary to tell an encrypted field apart from a legacy plaintext one
  /// during the migration period (encrypted and pre-encryption records
  /// coexist; nothing forces a one-time bulk re-encryption pass).
  static bool isEnvelope(dynamic value) =>
      value is Map &&
      value['v'] == 1 &&
      value['n'] is String &&
      value['c'] is String &&
      value['m'] is String;
}
