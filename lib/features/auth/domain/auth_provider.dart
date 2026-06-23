import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../core/services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  User? _user;
  StreamSubscription<User?>? _sub;

  AuthProvider() {
    _sub = AuthService.authStateChanges.listen((user) {
      _user = user;
      notifyListeners();
    });
  }

  User? get user => _user;
  bool get isSignedIn => _user != null;
  String? get email => _user?.email;
  String? get displayName => _user?.displayName;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
