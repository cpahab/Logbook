import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) throw UnsupportedError('Web platform is not configured.');
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => ios,
      _ => throw UnsupportedError(
          '${defaultTargetPlatform.name} is not configured.'),
    };
  }

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyB1sAEN7GS33LcsiOVUC5b3npgq6lxC--k',
    appId: '1:34296706111:ios:0c855c2dc50b42d9ebf48a',
    messagingSenderId: '34296706111',
    projectId: 'logbook-b19ed',
    storageBucket: 'logbook-b19ed.firebasestorage.app',
    iosBundleId: 'com.ziegler.logbook',
  );
}
