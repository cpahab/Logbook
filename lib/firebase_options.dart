import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) throw UnsupportedError('Web platform is not configured.');
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS     => ios,
      TargetPlatform.macOS   => macos,
      TargetPlatform.android => android,
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

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyB1sAEN7GS33LcsiOVUC5b3npgq6lxC--k',
    appId: '1:34296706111:ios:0c855c2dc50b42d9ebf48a',
    messagingSenderId: '34296706111',
    projectId: 'logbook-b19ed',
    storageBucket: 'logbook-b19ed.firebasestorage.app',
    iosBundleId: 'com.ziegler.logbook',
  );
  // Run `flutterfire configure --platforms=android` to register the Android app
  // in Firebase Console and replace the appId below with the generated value.
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyB1sAEN7GS33LcsiOVUC5b3npgq6lxC--k',
    appId: 'REPLACE_WITH_ANDROID_APP_ID',
    messagingSenderId: '34296706111',
    projectId: 'logbook-b19ed',
    storageBucket: 'logbook-b19ed.firebasestorage.app',
  );
}
