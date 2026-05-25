import 'package:flutter/material.dart';

import '../../core/supabase_config.dart';
import 'notifications_screen.dart';

class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  int unreadCount = 0;

  @override
  void initState() {
    super.initState();
    loadUnreadCount();
  }

  Future<void> loadUnreadCount() async {
    try {
      final response = await supabase
          .from('app_notifications')
          .select('id')
          .eq('is_read', false);

      if (mounted) {
        setState(() => unreadCount = response.length);
      }
    } catch (_) {
      // ignore count errors silently
    }
  }

  void openNotifications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const NotificationsScreen(),
      ),
    );

    loadUnreadCount();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IconButton(
          icon: const Icon(Icons.notifications),
          onPressed: openNotifications,
        ),

        if (unreadCount > 0)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: Text(
                unreadCount > 9 ? '9+' : unreadCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }
}