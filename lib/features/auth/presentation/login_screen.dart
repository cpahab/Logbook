import 'package:flutter/material.dart';
import '../../../app/routes.dart';
import 'package:go_router/go_router.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          child: const Text('Login'),
          onPressed: () {
            // Fake login
            context.go(AppRoutes.home);
          },
        ),
      ),
    );
  }
}
