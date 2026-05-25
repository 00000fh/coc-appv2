import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class SunkenCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double borderRadius;

  const SunkenCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 14),
    this.borderRadius = 22,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: const [
          BoxShadow(
            color: Color(0xFFD0D8DE),
            offset: Offset(-4, -4),
            blurRadius: 8,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: Color(0xFFFFFFFF),
            offset: Offset(4, 4),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: child,
    );
  }
}