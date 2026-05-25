import 'package:flutter/material.dart';
import '../../core/supabase_config.dart';
import '../../features/auth/login_screen.dart';
import 'app_snackbar.dart';

class SessionHandler {
  static Future<void> logoutExpired(BuildContext context) async {
    await supabase.auth.signOut();

    if (!context.mounted) return;

    AppSnackBar.warning(context, 'Session expired. Please login again.');

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  static bool isSessionError(Object e) {
    final message = e.toString().toLowerCase();

    return message.contains('jwt') ||
        message.contains('unauthorized') ||
        message.contains('invalid login') ||
        message.contains('session') ||
        message.contains('refresh token');
  }
}