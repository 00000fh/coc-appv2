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
import '../coc/page7_report/report_preview_screen.dart';
import '../notifications/notification_bell.dart';
import '../notifications/notification_service.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  bool loading = true;
  bool noInternet = false;
  List<Map<String, dynamic>> records = [];
  String searchQuery = '';
  RealtimeChannel? dashboardChannel;

  List<Map<String, dynamic>> get filteredRecords {
    if (searchQuery.trim().isEmpty) return records;

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

  @override
  void initState() {
    super.initState();
    loadRecords();
    listenToDashboardChanges();
  }

  void listenToDashboardChanges() {
    dashboardChannel = supabase.channel('admin_dashboard_changes');

    dashboardChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'coc_records',
          callback: (payload) {
            if (mounted) {
              loadRecords();
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'app_notifications',
          callback: (payload) {
            if (mounted) {
              loadRecords();
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

  Future<void> createAdminReminderNotifications() async {
    for (final record in records) {
      final status = record['status']?.toString() ?? '';

      if (status == 'lab_completed' ||
          status == 'report_ready' ||
          status == 'completed') {
        continue;
      }

      final createdAt = record['created_at']?.toString();

      if (createdAt == null) continue;

      final days = DateTime.now().difference(DateTime.parse(createdAt)).inDays;
      final recordId = record['id'].toString();
      final batchNumber = record['batch_number']?.toString() ?? '-';

      if (days >= 14) {
        await NotificationService.createReminderOnce(
          reminderKey: '${recordId}_admin_overdue_14',
          role: 'admin',
          recordId: recordId,
          title: 'Lab Analysis Overdue',
          message: 'Batch $batchNumber has not been completed after 14 days.',
          type: 'reminder',
        );
      } else if (days >= 7) {
        await NotificationService.createReminderOnce(
          reminderKey: '${recordId}_admin_reminder_7',
          role: 'admin',
          recordId: recordId,
          title: 'Lab Analysis Reminder',
          message: 'Batch $batchNumber is still pending after 7 days.',
          type: 'reminder',
        );
      }
    }
  }

  Future<void> loadRecords() async {
    setState(() {
      loading = true;
      noInternet = false;
    });

    try {
      final response = await supabase
          .from('coc_records')
          .select(
            'id, batch_number, project_name, client_name, status, created_at, labs(lab_name)',
          )
          .order('created_at', ascending: false);

      records = List<Map<String, dynamic>>.from(response);

      await createAdminReminderNotifications();
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
        'Failed to load records: ${e.toString().split(':').first}',
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

    await loadRecords();
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
      case 'draft':
        return 'Draft';
      case 'submitted_to_lab':
        return 'Submitted';
      case 'lab_in_progress':
        return 'In Progress';
      case 'lab_completed':
        return 'Lab Done';
      case 'report_ready':
        return 'Report Ready';
      case 'completed':
        return 'Completed';
      default:
        return status;
    }
  }

  Color getStatusColor(String status) {
    switch (status) {
      case 'draft':
        return Colors.grey;
      case 'submitted_to_lab':
        return Colors.orange;
      case 'lab_in_progress':
        return Colors.blue;
      case 'lab_completed':
        return Colors.green;
      case 'report_ready':
        return Colors.purple;
      case 'completed':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  IconData getStatusIcon(String status) {
    switch (status) {
      case 'draft':
        return Icons.edit_note;
      case 'submitted_to_lab':
        return Icons.send;
      case 'lab_in_progress':
        return Icons.science;
      case 'lab_completed':
        return Icons.check_circle;
      case 'report_ready':
        return Icons.picture_as_pdf;
      case 'completed':
        return Icons.verified;
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
    if (status == 'completed' ||
        status == 'report_ready' ||
        status == 'lab_completed') {
      return 'completed';
    }

    final createdDate = DateTime.parse(createdAt);
    final days = DateTime.now().difference(createdDate).inDays;

    if (days >= 14) return 'overdue';
    if (days >= 7) return 'reminder';

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
    final submittedCount = records
        .where((r) => r['status']?.toString() == 'submitted_to_lab')
        .length;

    final progressCount = records
        .where((r) => r['status']?.toString() == 'lab_in_progress')
        .length;

    final labDoneCount = records
        .where((r) => r['status']?.toString() == 'lab_completed')
        .length;

    final overdueCount = records.where((r) {
      final status = r['status']?.toString() ?? '';
      final createdAt = r['created_at']?.toString();

      if (createdAt == null) return false;

      if (status == 'lab_completed' ||
          status == 'report_ready' ||
          status == 'completed') {
        return false;
      }

      final days = DateTime.now().difference(DateTime.parse(createdAt)).inDays;

      return days >= 14;
    }).length;

    return NeumoCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Admin Overview',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              buildOverviewItem(
                'Total',
                records.length.toString(),
                AppTheme.primary,
              ),
              buildDivider(),
              buildOverviewItem(
                'Submitted',
                submittedCount.toString(),
                Colors.orange,
              ),
              buildDivider(),
              buildOverviewItem(
                'Progress',
                progressCount.toString(),
                Colors.blue,
              ),
              buildDivider(),
              buildOverviewItem('Done', labDoneCount.toString(), Colors.green),
              buildDivider(),
              buildOverviewItem('Overdue', overdueCount.toString(), Colors.red),
            ],
          ),
        ],
      ),
    );
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
            style: const TextStyle(fontSize: 10, color: AppTheme.textSoft),
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
          ),
        ],
      ),
      child: TextField(
        onChanged: (value) {
          setState(() => searchQuery = value);
        },
        decoration: const InputDecoration(
        hintText: 'Search by Batch Number or Project Name',
        prefixIcon: Icon(Icons.search),
        border: InputBorder.none,
      ),
      ),
    );
  }

  Widget buildRecordCard(Map<String, dynamic> record) {
    final lab = record['labs'];
    final labName = lab == null ? 'Not assigned' : lab['lab_name'].toString();
    final status = record['status']?.toString() ?? '-';
    final createdAt = record['created_at']?.toString() ?? '';

    return NeumoCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ReportPreviewScreen(
                recordId: record['id'].toString(),
                batchNumber: record['batch_number'].toString(),
              ),
            ),
          ).then((_) => loadRecords());
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
                  const SizedBox(height: 4),
                  Text(
                    'Lab: $labName',
                    style: const TextStyle(
                      color: AppTheme.textSoft,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  buildStatusChip(status),
                  if (createdAt.isNotEmpty)
                    buildDeadlineBadge(createdAt, status),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              color: AppTheme.primary,
              size: 18,
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
        onRefresh: loadRecords,
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
                    child: Text('No records yet.', textAlign: TextAlign.center),
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
