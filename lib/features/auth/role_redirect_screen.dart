import 'package:flutter/material.dart';

import '../../core/supabase_config.dart';

import '../dashboard/admin_dashboard.dart';
import '../dashboard/initiator_dashboard.dart';
import '../dashboard/lab_dashboard.dart';

import 'login_screen.dart';

class RoleRedirectScreen extends StatefulWidget {
  const RoleRedirectScreen({super.key});

  @override
  State<RoleRedirectScreen> createState() =>
      _RoleRedirectScreenState();
}

class _RoleRedirectScreenState
    extends State<RoleRedirectScreen> {

  @override
  void initState() {
    super.initState();
    checkRole();
  }

  Future<void> checkRole() async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const LoginScreen(),
        ),
      );
      return;
    }

    final profile = await supabase
        .from('profiles')
        .select('role')
        .eq('id', user.id)
        .single();

    final role = profile['role'];

    if (!mounted) return;

    if (role == 'initiator') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const InitiatorDashboard(),
        ),
      );
    }

    else if (role == 'lab') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const LabDashboard(),
        ),
      );
    }

    else if (role == 'admin') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const AdminDashboard(),
        ),
      );
    }

    else {
      await supabase.auth.signOut();

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const LoginScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}