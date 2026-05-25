import 'package:flutter/material.dart';

import '../../../core/supabase_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/neumo_card.dart';
import '../../../shared/widgets/loading_skeleton.dart';
import '../../../shared/widgets/no_internet_state.dart';
import '../../../shared/utils/app_snackbar.dart';
import '../../../shared/utils/session_handler.dart';

import 'attachment_type_screen.dart';
import '../page4_insitu_result/insitu_result_screen.dart';

class AttachmentOverviewScreen extends StatefulWidget {
  final String recordId;
  final String batchNumber;

  const AttachmentOverviewScreen({
    super.key,
    required this.recordId,
    required this.batchNumber,
  });

  @override
  State<AttachmentOverviewScreen> createState() =>
      _AttachmentOverviewScreenState();
}

class _AttachmentOverviewScreenState extends State<AttachmentOverviewScreen> {
  bool loading = true;
  bool noInternet = false;

  List<String> samplingTypes = [];
  Map<String, int> attachmentCounts = {};

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    setState(() {
      loading = true;
      noInternet = false;
    });

    try {
      final typesResponse = await supabase
          .from('selected_sampling_types')
          .select('sampling_type')
          .eq('coc_record_id', widget.recordId);

      samplingTypes = typesResponse
          .map<String>((row) => row['sampling_type'].toString())
          .toList();

      attachmentCounts = {};

      for (final type in samplingTypes) {
        final files = await supabase
            .from('attachments')
            .select('id')
            .eq('coc_record_id', widget.recordId)
            .eq('sampling_type', type);

        attachmentCounts[type] = files.length;
      }
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

      AppSnackBar.error(context, 'Failed to load attachments: ${e.toString().split(':').first}');
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

    await loadData();
  }

  Future<void> openSamplingType(String type) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AttachmentTypeScreen(
          recordId: widget.recordId,
          batchNumber: widget.batchNumber,
          samplingType: type,
        ),
      ),
    );

    await loadData();
  }

  void nextPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InsituResultScreen(
          recordId: widget.recordId,
          batchNumber: widget.batchNumber,
        ),
      ),
    );
  }

  Color getTypeColor(String type) {
    switch (type) {
      case 'Water':
        return Colors.blue;
      case 'Silt Trap':
        return Colors.brown;
      case 'Ambient Air':
        return Colors.teal;
      case 'Noise':
        return Colors.deepPurple;
      case 'Vibration':
        return Colors.orange;
      default:
        return AppTheme.primary;
    }
  }

  IconData getTypeIcon(String type) {
    switch (type) {
      case 'Water':
        return Icons.water_drop;
      case 'Silt Trap':
        return Icons.landscape;
      case 'Ambient Air':
        return Icons.air;
      case 'Noise':
        return Icons.volume_up;
      case 'Vibration':
        return Icons.graphic_eq;
      default:
        return Icons.image;
    }
  }

  Widget buildBatchCard() {
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
              Icons.qr_code_2,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Batch Number',
                  style: TextStyle(
                    color: AppTheme.textSoft,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.batchNumber,
                  style: const TextStyle(
                    color: AppTheme.textDark,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildAttachmentCard(String type) {
    final count = attachmentCounts[type] ?? 0;
    final color = getTypeColor(type);

    return NeumoCard(
      padding: const EdgeInsets.all(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => openSamplingType(type),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.14),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                getTypeIcon(type),
                color: color,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type,
                    style: const TextStyle(
                      color: AppTheme.textDark,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '$count / 15 images attached',
                    style: const TextStyle(
                      color: AppTheme.textSoft,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: count / 15,
                    minHeight: 5,
                    backgroundColor: color.withOpacity(0.12),
                    color: color,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              count > 0 ? Icons.photo_library : Icons.add_photo_alternate,
              color: count > 0 ? color : AppTheme.textSoft,
              size: 22,
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
            'No sampling types selected.',
            textAlign: TextAlign.center,
          ),
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
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'Attachments',
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

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.appBarColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Attachments',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: loadData,
        child: loading
            ? const LoadingSkeleton()
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  buildBatchCard(),
                  const SizedBox(height: 4),
                  const Text(
                    'Attachment Sections',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Upload photos based on the selected sampling type.',
                    style: TextStyle(
                      color: AppTheme.textSoft,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (samplingTypes.isEmpty) buildEmptyState(),
                  ...samplingTypes.map(buildAttachmentCard),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: nextPage,
                      child: const Text('Next'),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }
}