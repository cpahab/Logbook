import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logbook/core/services/crypto_service.dart';

void main() {
  late SecretKey key;
  late CryptoService crypto;

  setUp(() async {
    key = await AesGcm.with256bits().newSecretKey();
    crypto = CryptoService(key);
  });

  group('encryptText/decryptText', () {
    test('round-trips plain text, including empty and unicode strings', () async {
      for (final text in ['hello harbor', '', 'Fähre nach Öland ⛵️🌊']) {
        final envelope = await crypto.encryptText(text);
        expect(await crypto.decryptText(envelope), text);
      }
    });

    test('produces a fresh nonce every call, even for identical plaintext', () async {
      final a = await crypto.encryptText('same text');
      final b = await crypto.encryptText('same text');
      expect(a['n'], isNot(b['n']));
      expect(a['c'], isNot(b['c']));
    });

    test('fails to decrypt under a different key', () async {
      final envelope = await crypto.encryptText('secret notes');
      final otherKey = await AesGcm.with256bits().newSecretKey();
      final otherCrypto = CryptoService(otherKey);
      expect(
        () => otherCrypto.decryptText(envelope),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('rejects tampered ciphertext (GCM authentication)', () async {
      final envelope = await crypto.encryptText('do not tamper with me');
      final tampered = Map<String, dynamic>.from(envelope);
      // Flip the ciphertext to something else, same length.
      tampered['c'] = envelope['c'] == 'AAAA' ? 'BBBB' : 'AAAA';
      expect(
        () => crypto.decryptText(tampered),
        throwsA(anything),
      );
    });
  });

  group('encryptJson/decryptJson', () {
    test('round-trips a nested map', () async {
      final value = {
        'name': 'Skipper',
        'bloodType': 'O-',
        'allergies': null,
        'nested': {'a': 1, 'b': 2.5},
      };
      final envelope = await crypto.encryptJson(value);
      final decrypted = await crypto.decryptJson(envelope);
      expect(decrypted, value);
    });
  });

  group('encryptBytes/decryptBytes', () {
    test('round-trips arbitrary bytes', () async {
      final bytes = Uint8List.fromList(List<int>.generate(5000, (i) => i % 256));
      final encrypted = await crypto.encryptBytes(bytes);
      final decrypted = await crypto.decryptBytes(encrypted);
      expect(decrypted, bytes);
    });

    test('encrypted blob is larger than the plaintext (nonce+MAC overhead)', () async {
      final bytes = Uint8List.fromList(List<int>.generate(100, (i) => i));
      final encrypted = await crypto.encryptBytes(bytes);
      expect(encrypted.length, greaterThan(bytes.length));
    });

    test('rejects a corrupted blob', () async {
      final bytes = Uint8List.fromList(List<int>.generate(100, (i) => i));
      final encrypted = await crypto.encryptBytes(bytes);
      encrypted[encrypted.length - 1] ^= 0xFF; // flip last byte (part of the MAC)
      expect(() => crypto.decryptBytes(encrypted), throwsA(anything));
    });
  });

  group('isEnvelope', () {
    test('recognizes an encrypted envelope and rejects legacy plaintext', () async {
      final envelope = await crypto.encryptText('hi');
      expect(CryptoService.isEnvelope(envelope), isTrue);
      expect(CryptoService.isEnvelope('a plain legacy string'), isFalse);
      expect(CryptoService.isEnvelope(null), isFalse);
      expect(CryptoService.isEnvelope({'v': 2, 'n': 'x', 'c': 'y', 'm': 'z'}), isFalse);
      expect(CryptoService.isEnvelope({'v': 1, 'n': 'x'}), isFalse);
    });
  });
}
