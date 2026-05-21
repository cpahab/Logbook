import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

class Nav {
  static void to(BuildContext context, String route) {
    context.go(route);
  }

  static void push(BuildContext context, String route) {
    context.push(route);
  }

  static void back(BuildContext context) {
    context.pop();
  }
}
