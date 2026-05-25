import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class DashboardSectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;

  const DashboardSectionTitle({
    super.key,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {

    return Padding(
      padding: const EdgeInsets.only(
        bottom: 14,
      ),

      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,

        children: [

          Text(
            title,

            style: TextStyle(
              fontSize: 22,

              fontWeight:
                  FontWeight.bold,

              color:
                  AppTheme.textDark,
            ),
          ),

          if (subtitle != null) ...[

            const SizedBox(height: 4),

            Text(
              subtitle!,

              style: TextStyle(
                fontSize: 13,

                color:
                    AppTheme.textSoft,
              ),
            ),
          ],
        ],
      ),
    );
  }
}