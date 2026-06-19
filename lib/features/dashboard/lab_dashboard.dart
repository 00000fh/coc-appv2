import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/supabase_config.dart';
import '../../core/theme/app_theme.dart';

import '../../shared/widgets/neumo_card.dart';
import '../../shared/widgets/loading_skeleton.dart';
import '../../shared/widgets/no_internet_state.dart';
import '../../shared/utils/app_snackbar.dart';
import '../../shared/utils/session_handler.dart';

import '../auth/login_screen.dart';
import '../coc/page6_lab_analysis/lab_analysis_screen.dart';
import '../notifications/notification_bell.dart';
import '../notifications/notification_service.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

class LabDashboard extends StatefulWidget {
  const LabDashboard({super.key});

  @override
  State<LabDashboard> createState() => _LabDashboardState();
}

class _LabDashboardState extends State<LabDashboard> {
  bool loading = true;
  bool noInternet = false;

  List<Map<String, dynamic>> records = [];

  String searchQuery = '';
  RealtimeChannel? dashboardChannel;

  List<Map<String, dynamic>> get filteredRecords {
    if (searchQuery.trim().isEmpty) {
      return records;
    }

    final query = searchQuery.trim().toLowerCase();

    return records.where((record) {
      final batchNumber =
          record['batch_number']?.toString().toLowerCase() ?? '';

      final projectName =
          record['project_name']?.toString().toLowerCase() ?? '';

      return batchNumber.contains(query) ||
          projectName.contains(query);
    }).toList();
  }

  // Helper method to check if a record is from the current month
  bool isCurrentMonthRecord(Map<String, dynamic> record) {
    final createdAt = record['created_at'];
    if (createdAt == null) return false;

    DateTime recordDate;
    if (createdAt is DateTime) {
      recordDate = createdAt;
    } else if (createdAt is String) {
      recordDate = DateTime.parse(createdAt);
    } else {
      return false;
    }

    final now = DateTime.now();
    return recordDate.year == now.year && recordDate.month == now.month;
  }

  // Get records only from current month
  List<Map<String, dynamic>> get currentMonthRecords {
    return records.where(isCurrentMonthRecord).toList();
  }

  @override
  void initState() {
    super.initState();
    loadAssignedRecords();
    listenToDashboardChanges();
  }

  void listenToDashboardChanges() {
    dashboardChannel = supabase.channel('lab_dashboard_changes');

    dashboardChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'coc_records',
          callback: (payload) {
            if (mounted) {
              // Only refresh if the change affects records in lab statuses
              final newRecord = payload.newRecord as Map<String, dynamic>?;
              final oldRecord = payload.oldRecord as Map<String, dynamic>?;

              // Check if the affected record has any lab-related status
              final List<String> labStatuses = [
                'submitted_to_lab',
                'lab_in_progress',
                'lab_completed',
              ];

              bool shouldRefresh = false;

              if (newRecord != null) {
                final status = newRecord['status']?.toString() ?? '';
                if (labStatuses.contains(status)) {
                  shouldRefresh = true;
                }
              }

              if (oldRecord != null && !shouldRefresh) {
                final status = oldRecord['status']?.toString() ?? '';
                if (labStatuses.contains(status)) {
                  shouldRefresh = true;
                }
              }

              if (shouldRefresh) {
                loadAssignedRecords();
              }
            }
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (dashboardChannel != null) {
      supabase.removeChannel(dashboardChannel!);
    }
    super.dispose();
  }

  Future<void> createLabReminderNotifications() async {
    for (final record in records) {
      final status = record['status']?.toString() ?? '';

      if (status == 'lab_completed') {
        continue;
      }

      final createdAt = record['created_at']?.toString();

      if (createdAt == null) {
        continue;
      }

      final days = DateTime.now().difference(DateTime.parse(createdAt)).inDays;

      final recordId = record['id'].toString();

      final batchNumber = record['batch_number']?.toString() ?? '-';

      if (days >= 14) {
        await NotificationService.createReminderOnce(
          reminderKey: '${recordId}_lab_overdue_14',
          role: 'lab',
          recordId: recordId,
          title: 'Lab Analysis Overdue',
          message: 'Batch $batchNumber has been pending for over 14 days.',
          type: 'reminder',
        );
      } else if (days >= 7) {
        await NotificationService.createReminderOnce(
          reminderKey: '${recordId}_lab_reminder_7',
          role: 'lab',
          recordId: recordId,
          title: 'Lab Analysis Reminder',
          message: 'Batch $batchNumber has been pending for over 7 days.',
          type: 'reminder',
        );
      }
    }
  }

  Future<void> loadAssignedRecords() async {
    setState(() {
      loading = true;
      noInternet = false;
    });

    try {
      final response = await supabase
          .from('coc_records')
          .select('''
            id,
            batch_number,
            project_name,
            client_name,
            status,
            created_at
            ''')
          .inFilter('status', [
            'submitted_to_lab',
            'lab_in_progress',
            'lab_completed',
          ])
          .order('created_at', ascending: false);

      records = List<Map<String, dynamic>>.from(response);

      await createLabReminderNotifications();
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

      AppSnackBar.error(
        context,
        'Failed to load assigned records: ${e.toString().split(':').first}',
      );
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

    await loadAssignedRecords();
  }

  Future<void> logout() async {
    await supabase.auth.signOut();

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  String getStatusLabel(String status) {
    switch (status) {
      case 'submitted_to_lab':
        return 'New Assignment';

      case 'lab_in_progress':
        return 'In Progress';

      case 'lab_completed':
        return 'Completed';

      default:
        return status;
    }
  }

  Color getStatusColor(String status) {
    switch (status) {
      case 'submitted_to_lab':
        return Colors.orange;

      case 'lab_in_progress':
        return Colors.blue;

      case 'lab_completed':
        return Colors.green;

      default:
        return Colors.grey;
    }
  }

  IconData getStatusIcon(String status) {
    switch (status) {
      case 'submitted_to_lab':
        return Icons.fiber_new;

      case 'lab_in_progress':
        return Icons.science;

      case 'lab_completed':
        return Icons.check_circle;

      default:
        return Icons.info;
    }
  }

  Widget buildStatusChip(String status) {
    final color = getStatusColor(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(getStatusIcon(status), size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            getStatusLabel(status),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  String getDeadlineStatus(String createdAt, String status) {
    if (status == 'lab_completed') {
      return 'completed';
    }

    final createdDate = DateTime.parse(createdAt);

    final days = DateTime.now().difference(createdDate).inDays;

    if (days >= 14) {
      return 'overdue';
    }

    if (days >= 7) {
      return 'reminder';
    }

    return 'normal';
  }

  Widget buildDeadlineBadge(String createdAt, String status) {
    final deadlineStatus = getDeadlineStatus(createdAt, status);

    if (deadlineStatus == 'normal' || deadlineStatus == 'completed') {
      return const SizedBox();
    }

    final isOverdue = deadlineStatus == 'overdue';

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isOverdue
            ? Colors.red.withValues(alpha: 0.12)
            : Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isOverdue ? Colors.red : Colors.orange),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isOverdue ? Icons.warning : Icons.schedule,
            size: 16,
            color: isOverdue ? Colors.red : Colors.orange,
          ),
          const SizedBox(width: 6),
          Text(
            isOverdue ? 'Overdue: 14+ days' : 'Reminder: 7+ days',
            style: TextStyle(
              color: isOverdue ? Colors.red : Colors.orange,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildOverviewCard() {
    // Use current month records for the overview counts
    final currentMonthRecordsList = currentMonthRecords;
    
    final newCount = currentMonthRecordsList
        .where((r) => r['status']?.toString() == 'submitted_to_lab')
        .length;

    final progressCount = currentMonthRecordsList
        .where((r) => r['status']?.toString() == 'lab_in_progress')
        .length;

    final completedCount = currentMonthRecordsList
        .where((r) => r['status']?.toString() == 'lab_completed')
        .length;

    // Grand total (all time)
    final grandTotal = records.length;

    return NeumoCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Lab Work Overview',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_getMonthName(DateTime.now())} ${DateTime.now().year}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              buildOverviewItem('New', newCount.toString(), Colors.orange),
              buildDivider(),
              buildOverviewItem(
                'Progress',
                progressCount.toString(),
                Colors.blue,
              ),
              buildDivider(),
              buildOverviewItem(
                'Done',
                completedCount.toString(),
                Colors.green,
              ),
            ],
          ),
          // Subtle grand total indicator
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.history,
                  size: 14,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 6),
                Text(
                  'All-time total: $grandTotal lab records',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 4),
                Tooltip(
                  message: 'Total lab records assigned since you started using the app',
                  child: Icon(
                    Icons.info_outline,
                    size: 14,
                    color: Colors.grey.shade400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getMonthName(DateTime date) {
    const monthNames = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return monthNames[date.month - 1];
  }

  Widget buildOverviewItem(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.audiowide(
              fontSize: 24,
              color: color,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: AppTheme.textSoft),
          ),
        ],
      ),
    );
  }

  Widget buildDivider() {
    return Container(height: 36, width: 1, color: const Color(0xFFD6DEE4));
  }

  Widget buildSearchBar() {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Color(0xFFC8D0D6),
            offset: Offset(4, 4),
            blurRadius: 10,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: Colors.white,
            offset: Offset(-4, -4),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: TextField(
        onChanged: (value) {
          setState(() => searchQuery = value);
        },
        decoration: const InputDecoration(
          hintText: 'Search batch number or project',
          prefixIcon: Icon(Icons.search),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget buildRecordCard(Map<String, dynamic> record) {
    final status = record['status']?.toString() ?? '-';

    final isCompleted = status == 'lab_completed';

    return NeumoCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => LabAnalysisScreen(
                recordId: record['id'].toString(),
                batchNumber: record['batch_number'].toString(),
              ),
            ),
          ).then((_) => loadAssignedRecords());
        },
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: getStatusColor(status).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(getStatusIcon(status), color: getStatusColor(status)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record['batch_number']?.toString() ?? 'No batch number',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    record['project_name']?.toString() ?? '-',
                    style: const TextStyle(color: AppTheme.textSoft),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Client: ${record['client_name'] ?? '-'}',
                    style: const TextStyle(
                      color: AppTheme.textSoft,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  buildStatusChip(status),
                  buildDeadlineBadge(record['created_at'].toString(), status),
                ],
              ),
            ),
            Icon(
              isCompleted ? Icons.visibility : Icons.arrow_forward_ios,
              color: isCompleted ? Colors.green : AppTheme.primary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Show no internet state
    if (noInternet) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: AppTheme.appBarColor,
          foregroundColor: AppTheme.appBarText,
          elevation: 0,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(
              height: 1,
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          title: const Text(
            'Home',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.4,
            ),
          ),
          actions: [
            const NotificationBell(),
            IconButton(onPressed: logout, icon: const Icon(Icons.logout)),
          ],
        ),
        body: NoInternetState(onRetry: retryAfterNoInternet),
      );
    }

    // Show loading skeleton
    if (loading) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: AppTheme.appBarColor,
          foregroundColor: AppTheme.appBarText,
          elevation: 0,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(
              height: 1,
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          title: const Text(
            'Home',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.4,
            ),
          ),
          actions: [
            const NotificationBell(),
            IconButton(onPressed: logout, icon: const Icon(Icons.logout)),
          ],
        ),
        body: const LoadingSkeleton(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.appBarColor,
        foregroundColor: AppTheme.appBarText,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        title: const Text(
          'Home',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.4,
          ),
        ),
        actions: [
          const NotificationBell(),
          IconButton(onPressed: logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: loadAssignedRecords,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            buildOverviewCard(),
            const SizedBox(height: 18),
            buildSearchBar(),
            if (records.isEmpty)
              const NeumoCard(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'No assigned lab records yet.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            if (records.isNotEmpty && filteredRecords.isEmpty)
              const NeumoCard(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'No matching records found.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ...filteredRecords.map(buildRecordCard),
          ],
        ),
      ),
    );
  }
}