import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class LoadingSkeleton extends StatelessWidget {
  final int count;

  const LoadingSkeleton({
    super.key,
    this.count = 5,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: count,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          height: 92,
          decoration: BoxDecoration(
            color: AppTheme.surface.withOpacity(0.75),
            borderRadius: BorderRadius.circular(22),
          ),
        );
      },
    );
  }
}