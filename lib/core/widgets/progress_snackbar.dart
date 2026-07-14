import 'package:flutter/material.dart';

/// Shows a long-lived snackbar with a small spinner plus [message], for an
/// operation that takes real time (export, restore, ...). Dismiss it with
/// `ScaffoldMessenger.of(context).hideCurrentSnackBar()` once the operation
/// finishes, then show a success/error snackbar in its place.
void showProgressSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      duration: const Duration(minutes: 2),
      content: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}
