import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../l10n/l10n_extension.dart';

class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  bool _isOffline = false;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  @override
  void initState() {
    super.initState();
    Connectivity().checkConnectivity().then((results) {
      if (mounted) {
        setState(() => _isOffline = _allNone(results));
      }
    });
    _sub = Connectivity().onConnectivityChanged.listen((results) {
      if (mounted) setState(() => _isOffline = _allNone(results));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  static bool _allNone(List<ConnectivityResult> results) =>
      results.every((r) => r == ConnectivityResult.none);

  @override
  Widget build(BuildContext context) {
    if (!_isOffline || FirebaseAuth.instance.currentUser == null) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      color: Colors.amber.shade700,
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 16),
      child: Text(
        context.l10n.offlineBanner,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
