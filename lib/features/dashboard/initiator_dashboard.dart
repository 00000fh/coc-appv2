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
import '../coc/page1_site_information/site_information_screen.dart';
import '../notifications/notification_bell.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

class InitiatorDashboard extends StatefulWidget {
  const InitiatorDashboard({super.key});

  @override
  State<InitiatorDashboard> createState() => _InitiatorDashboardState();
}

class _InitiatorDashboardState extends State<InitiatorDashboard> {
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
    loadMyRecords();
    listenToDashboardChanges();
  }

  void listenToDashboardChanges() {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    dashboardChannel = supabase.channel('initiator_dashboard_changes_$userId');

    dashboardChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'coc_records',
          callback: (payload) {
            // Only refresh if the record belongs to this user
            final newRecord = payload.newRecord as Map<String, dynamic>?;
            final oldRecord = payload.oldRecord as Map<String, dynamic>?;

            // Check if the affected record belongs to current user
            if (newRecord != null && newRecord['created_by'] == userId) {
              if (mounted) {
                loadMyRecords();
              }
            } else if (oldRecord != null && oldRecord['created_by'] == userId) {
              if (mounted) {
                loadMyRecords();
              }
            } else if (payload.eventType == PostgresChangeEvent.delete) {
              // For deletes, we need to check if any record belonging to user was deleted
              if (mounted) {
                loadMyRecords();
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

  Future<void> loadMyRecords() async {
    setState(() {
      loading = true;
      noInternet = false;
    });

    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        throw Exception('User not logged in');
      }

      final response = await supabase
          .from('coc_records')
          .select('''
            id,
            batch_number,
            project_name,
            client_name,
            location,
            latitude,
            longitude,
            monitoring_date,
            status,
            created_at
            ''')
          .eq('created_by', user.id)
          .order('created_at', ascending: false);

      records = List<Map<String, dynamic>>.from(response);
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

    await loadMyRecords();
  }

  Future<void> logout() async {
    await supabase.auth.signOut();

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  void openSiteInformation() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SiteInformationScreen()),
    ).then((_) => loadMyRecords());
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
        return 'Lab Completed';
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

  Widget buildOverviewCard() {
    final draftCount = records
        .where((r) => r['status']?.toString() == 'draft')
        .length;

    final submittedCount = records
        .where((r) => r['status']?.toString() == 'submitted_to_lab')
        .length;

    final completedCount = records
        .where((r) => r['status']?.toString() == 'lab_completed')
        .length;

    return NeumoCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Records Overview',
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
              buildOverviewItem('Draft', draftCount.toString(), Colors.grey),
              buildDivider(),
              buildOverviewItem(
                'Submitted',
                submittedCount.toString(),
                Colors.orange,
              ),
              buildDivider(),
              buildOverviewItem(
                'Done',
                completedCount.toString(),
                Colors.green,
              ),
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
              fontSize: 34,
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: 1.4,
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
        keyboardType: TextInputType.text,
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
    final status = record['status']?.toString() ?? '-';
    final isDraft = status == 'draft';

    return NeumoCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: isDraft
            ? () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        SiteInformationScreen(existingRecord: record),
                  ),
                ).then((_) => loadMyRecords());
              }
            : () {
                AppSnackBar.warning(
                  context,
                  'Only draft records can be edited',
                );
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
                  const SizedBox(height: 8),
                  buildStatusChip(status),
                ],
              ),
            ),
            Icon(
              isDraft ? Icons.edit : Icons.lock,
              color: isDraft ? AppTheme.primary : Colors.grey,
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
      floatingActionButton: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: openSiteInformation,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.add, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text(
                  'New COC',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: loadMyRecords,
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
                      'No COC records yet.\nTap New COC to create one.',
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
