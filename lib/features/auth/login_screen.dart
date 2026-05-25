import 'package:flutter/material.dart';

import '../../core/supabase_config.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/neumo_card.dart';
import '../../shared/widgets/loading_skeleton.dart';
import '../../shared/widgets/no_internet_state.dart';
import '../../shared/utils/app_snackbar.dart';
import '../../shared/utils/session_handler.dart';
import 'role_redirect_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool loading = false;
  bool obscurePassword = true;
  bool noInternet = false;

  Future<void> login() async {
    setState(() => loading = true);

    try {
      await supabase.auth.signInWithPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const RoleRedirectScreen(),
        ),
      );
    } catch (e) {
      // Check for session errors
      if (SessionHandler.isSessionError(e)) {
        await SessionHandler.logoutExpired(context);
        return;
      }
      
      // Check for internet connection issues
      if (e.toString().toLowerCase().contains('failed host lookup') ||
          e.toString().toLowerCase().contains('socketexception') ||
          e.toString().toLowerCase().contains('network')) {
        setState(() => noInternet = true);
        return;
      }
      
      // Show error snackbar for other errors
      AppSnackBar.error(context, 'Login Failed: ${e.toString().split(':').first}');
    }

    if (mounted) {
      setState(() => loading = false);
    }
  }

  Future<void> loadData() async {
    setState(() {
      noInternet = false;
      loading = true;
    });
    
    // Small delay to ensure connection check
    await Future.delayed(const Duration(milliseconds: 500));
    
    await login();
  }

  Widget buildInputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(
            color: Color(0xFFC8D0D6),
            offset: Offset(4, 4),
            blurRadius: 10,
          ),
          BoxShadow(
            color: Colors.white,
            offset: Offset(-4, -4),
            blurRadius: 10,
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure ? obscurePassword : false,
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hint,
          prefixIcon: Icon(
            icon,
            color: AppTheme.primary,
          ),
          suffixIcon: obscure
              ? IconButton(
                  onPressed: () {
                    setState(() {
                      obscurePassword = !obscurePassword;
                    });
                  },
                  icon: Icon(
                    obscurePassword ? Icons.visibility_off : Icons.visibility,
                    color: AppTheme.textSoft,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  Widget buildLoginButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: loading ? null : login,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF314A5A),
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(
                color: Color(0xFFD5DDE3),
                offset: Offset(5, 5),
                blurRadius: 12,
              ),
              BoxShadow(
                color: Colors.white,
                offset: Offset(-5, -5),
                blurRadius: 12,
              ),
            ],
          ),
          child: Center(
            child: Text(
              loading ? 'Logging In...' : 'Login',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildHeader() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.background,
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(
                color: Color(0xFFC8D0D6),
                offset: Offset(5, 5),
                blurRadius: 12,
              ),
              BoxShadow(
                color: Colors.white,
                offset: Offset(-5, -5),
                blurRadius: 12,
              ),
            ],
          ),
          child: Image.asset(
            'assets/images/coclogo.png',
            height: 56,
          ),
        ),
        const SizedBox(height: 28),
        const Text(
          'FIELD MONITORING APP',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppTheme.textDark,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Show no internet state
    if (noInternet) {
      return Scaffold(
        body: SafeArea(
          child: NoInternetState(
            onRetry: loadData,
          ),
        ),
      );
    }

    // Show loading skeleton
    if (loading) {
      return const Scaffold(
        body: SafeArea(
          child: LoadingSkeleton(),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  buildHeader(),
                  const SizedBox(height: 40),
                  NeumoCard(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        buildInputField(
                          controller: emailController,
                          hint: 'Email',
                          icon: Icons.email_outlined,
                        ),
                        buildInputField(
                          controller: passwordController,
                          hint: 'Password',
                          icon: Icons.lock_outline,
                          obscure: true,
                        ),
                        const SizedBox(height: 10),
                        buildLoginButton(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}