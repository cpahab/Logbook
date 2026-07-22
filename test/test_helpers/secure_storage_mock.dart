import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Installs an in-memory mock for flutter_secure_storage's platform channel,
/// so tests that exercise `HomeRepository.init`/`ThemeProvider.init`/
/// `EmergencyRepository.init`/`LocalLogbookService` (which all now resolve a
/// device Hive-encryption key via `DeviceHiveKeyStore`, backed by
/// flutter_secure_storage) don't hit a `MissingPluginException` — there's no
/// real Keychain/Keystore in a plain `flutter_test` unit test. Call this once
/// per test's `setUp`; each call gets a fresh in-memory store, matching a
/// clean Keychain on first app install.
void mockSecureStorage() {
  final store = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async {
      final args = (call.arguments as Map?)?.cast<String, dynamic>();
      switch (call.method) {
        case 'read':
          return store[args!['key'] as String];
        case 'write':
          store[args!['key'] as String] = args['value'] as String;
          return null;
        case 'delete':
          store.remove(args!['key'] as String);
          return null;
        case 'containsKey':
          return store.containsKey(args!['key'] as String);
        case 'readAll':
          return store;
        case 'deleteAll':
          store.clear();
          return null;
        default:
          return null;
      }
    },
  );
}
