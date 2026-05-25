import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import 'neumo_card.dart';

class NoInternetState extends StatelessWidget {
  final VoidCallback onRetry;

  const NoInternetState({
    super.key,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: NeumoCard(
        margin: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.wifi_off,
              size: 46,
              color: Colors.red,
            ),
            const SizedBox(height: 14),
            const Text(
              'No Internet Connection',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSoft),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}