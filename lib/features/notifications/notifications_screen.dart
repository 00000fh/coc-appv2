import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_config.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/neumo_card.dart';
import '../../shared/widgets/loading_skeleton.dart';
import '../../shared/widgets/no_internet_state.dart';
import '../../shared/utils/app_snackbar.dart';
import '../../shared/utils/session_handler.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool loading = true;
  bool noInternet = false;

  RealtimeChannel? notificationChannel;

  List<Map<String, dynamic>> notifications = [];

  @override
  void initState() {
    super.initState();

    loadNotifications();
    listenToNotifications();
  }

  void listenToNotifications() {
    notificationChannel = supabase.channel('app_notifications_changes');

    notificationChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'app_notifications',
          callback: (payload) {
            if (mounted) {
              loadNotifications();
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'app_notifications',
          callback: (payload) {
            if (mounted) {
              loadNotifications();
            }
          },
        )
        .subscribe();
  }

  Future<void> loadNotifications() async {
    if (mounted) {
      setState(() {
        loading = true;
        noInternet = false;
      });
    }

    try {
      final response = await supabase
          .from('app_notifications')
          .select()
          .order('created_at', ascending: false);

      notifications = List<Map<String, dynamic>>.from(response);
    } catch (e) {
      if (!mounted) return;

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

      AppSnackBar.error(context, 'Failed to load notifications: ${e.toString().split(':').first}');
    }

    if (mounted) {
      setState(() => loading = false);
    }
  }

  Future<void> retryAfterNoInternet() async {
    setState(() {
      noInternet = false;
      loading = true;
    });

    // Small delay to ensure connection check
    await Future.delayed(const Duration(milliseconds: 500));

    await loadNotifications();
  }

  Future<void> markAsRead(String id) async {
    try {
      await supabase
          .from('app_notifications')
          .update({'is_read': true})
          .eq('id', id);

      await loadNotifications();
      AppSnackBar.success(context, 'Notification marked as read');
    } catch (e) {
      if (!mounted) return;

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

      AppSnackBar.error(context, 'Failed to mark as read: ${e.toString().split(':').first}');
    }
  }

  Future<void> markAllAsRead() async {
    try {
      final unreadIds = notifications
          .where((item) => item['is_read'] != true)
          .map((item) => item['id'].toString())
          .toList();

      if (unreadIds.isEmpty) {
        AppSnackBar.info(context, 'No unread notifications');
        return;
      }

      await supabase
          .from('app_notifications')
          .update({'is_read': true})
          .inFilter('id', unreadIds);

      await loadNotifications();
      AppSnackBar.success(context, 'All notifications marked as read');
    } catch (e) {
      if (!mounted) return;

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

      AppSnackBar.error(context, 'Failed to mark all as read: ${e.toString().split(':').first}');
    }
  }

  String formatDate(dynamic value) {
    if (value == null) return '-';

    final date = DateTime.tryParse(value.toString());

    if (date == null) return value.toString();

    return '${date.day}/${date.month}/${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  IconData getIcon(String type) {
    switch (type) {
      case 'new_assignment':
        return Icons.assignment;
      case 'submitted_to_lab':
        return Icons.send;
      case 'lab_in_progress':
        return Icons.science;
      case 'lab_completed':
        return Icons.check_circle;
      case 'reminder':
        return Icons.warning;
      default:
        return Icons.notifications;
    }
  }

  Color getColor(String type) {
    switch (type) {
      case 'new_assignment':
        return Colors.orange;
      case 'submitted_to_lab':
        return Colors.blue;
      case 'lab_in_progress':
        return Colors.blue;
      case 'lab_completed':
        return Colors.green;
      case 'reminder':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String getTypeLabel(String type) {
    switch (type) {
      case 'new_assignment':
        return 'New Assignment';
      case 'submitted_to_lab':
        return 'Submitted';
      case 'lab_in_progress':
        return 'Lab Started';
      case 'lab_completed':
        return 'Completed';
      case 'reminder':
        return 'Reminder';
      default:
        return 'Notification';
    }
  }

  Widget buildTypeChip(String type) {
    final color = getColor(type);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Text(
        getTypeLabel(type),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget buildSummaryCard(int unreadCount) {
    return NeumoCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.notifications,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Notification Center',
                  style: TextStyle(
                    color: AppTheme.textDark,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  unreadCount == 0
                      ? 'All notifications have been read.'
                      : '$unreadCount unread notification(s)',
                  style: const TextStyle(
                    color: AppTheme.textSoft,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (unreadCount > 0)
            TextButton(
              onPressed: markAllAsRead,
              child: const Text('Read all'),
            ),
        ],
      ),
    );
  }

  Widget buildNotificationCard(Map<String, dynamic> item) {
    final id = item['id'].toString();
    final type = item['type']?.toString() ?? 'info';
    final isRead = item['is_read'] == true;
    final color = getColor(type);

    return NeumoCard(
      padding: const EdgeInsets.all(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: isRead ? null : () => markAsRead(id),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    getIcon(type),
                    color: color,
                  ),
                ),
                if (!isRead)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppTheme.background,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['title']?.toString() ?? '-',
                    style: TextStyle(
                      color: AppTheme.textDark,
                      fontWeight: isRead ? FontWeight.w600 : FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    item['message']?.toString() ?? '-',
                    style: const TextStyle(
                      color: AppTheme.textSoft,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      buildTypeChip(type),
                      Text(
                        formatDate(item['created_at']),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSoft,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(
              isRead ? Icons.done : Icons.mark_email_read,
              color: isRead ? Colors.grey : AppTheme.primary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget buildEmptyState() {
    return const NeumoCard(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'No notifications yet.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.textSoft,
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    if (notificationChannel != null) {
      supabase.removeChannel(notificationChannel!);
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount =
        notifications.where((item) => item['is_read'] != true).length;

    // Show no internet state
    if (noInternet) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: AppTheme.appBarColor,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'Notifications',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: NoInternetState(
          onRetry: retryAfterNoInternet,
        ),
      );
    }

    // Show loading skeleton
    if (loading) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: AppTheme.appBarColor,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'Notifications',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: const LoadingSkeleton(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.appBarColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Notifications',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: loadNotifications,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            buildSummaryCard(unreadCount),
            if (notifications.isEmpty) buildEmptyState(),
            ...notifications.map(buildNotificationCard),
          ],
        ),
      ),
    );
  }
}