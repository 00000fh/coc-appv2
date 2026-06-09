import 'package:flutter/material.dart';

class NeumoCard extends StatelessWidget {
  final Widget child;

  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  final double borderRadius;

  const NeumoCard({
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
        color: const Color(0xFFEAF1F5),

        borderRadius: BorderRadius.circular(borderRadius),

        border: Border.all(
          color: Colors.white.withValues(alpha: 0.45),

          width: 1,
        ),

        boxShadow: const [
          BoxShadow(
            color: Colors.white,

            offset: Offset(-7, -7),

            blurRadius: 16,

            spreadRadius: 1,
          ),

          BoxShadow(
            color: Color(0xFFBCC8D1),

            offset: Offset(7, 7),

            blurRadius: 16,

            spreadRadius: 1,
          ),
        ],
      ),

      child: child,
    );
  }
}
