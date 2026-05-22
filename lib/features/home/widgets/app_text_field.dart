import 'package:flutter/material.dart';

class AppTextField extends StatelessWidget {
  final String hint;

  const AppTextField({super.key, required this.hint});

  @override
  Widget build(BuildContext context) {
    return TextField(decoration: InputDecoration(hintText: hint));
  }
}
