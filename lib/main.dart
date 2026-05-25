import 'package:flutter/material.dart';

import 'core/supabase_config.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/role_redirect_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeSupabase();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'COC Field Monitoring',
      theme: AppTheme.lightTheme,
      home: supabase.auth.currentUser == null
          ? const LoginScreen()
          : const RoleRedirectScreen(),
    );
  }
}