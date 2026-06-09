import 'package:flutter/material.dart';
import '../../core/supabase_config.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/neumo_card.dart';
import '../../shared/widgets/loading_skeleton.dart';
import '../../shared/widgets/no_internet_state.dart';
import '../../shared/utils/app_snackbar.dart';
import '../../shared/utils/session_handler.dart';

class SubmittedCocViewScreen extends StatefulWidget {
  final String recordId;
  final String batchNumber;

  const SubmittedCocViewScreen({
    super.key,
    required this.recordId,
    required this.batchNumber,
  });

  @override
  State<SubmittedCocViewScreen> createState() => _SubmittedCocViewScreenState();
}

class _SubmittedCocViewScreenState extends State<SubmittedCocViewScreen> {
  bool loading = true;
  bool noInternet = false;

  Map<String, dynamic>? record;
  Map<String, dynamic>? acknowledgement;

  List<Map<String, dynamic>> samplingTypes = [];
  List<Map<String, dynamic>> selectedParameters = [];
  List<Map<String, dynamic>> insituResults = [];
  List<Map<String, dynamic>> labResults = [];
  List<Map<String, dynamic>> labResultValues = [];
  List<Map<String, dynamic>> attachments = [];

  @override
  void initState() {
    super.initState();
    loadRecord();
  }

  Future<void> loadRecord() async {
    setState(() {
      loading = true;
      noInternet = false;
    });

    try {
      record = await supabase
          .from('coc_records')
          .select('*, labs(lab_name)')
          .eq('id', widget.recordId)
          .single();

      samplingTypes = List<Map<String, dynamic>>.from(
        await supabase
            .from('selected_sampling_types')
            .select()
            .eq('coc_record_id', widget.recordId)
            .order('sampling_type'),
      );

      selectedParameters = List<Map<String, dynamic>>.from(
        await supabase
            .from('selected_parameters')
            .select()
            .eq('coc_record_id', widget.recordId)
            .order('sampling_type'),
      );

      insituResults = List<Map<String, dynamic>>.from(
        await supabase
            .from('insitu_results')
            .select()
            .eq('coc_record_id', widget.recordId)
            .order('parameter_name'),
      );

      acknowledgement = await supabase
          .from('lab_acknowledgements')
          .select('*, labs(lab_name)')
          .eq('coc_record_id', widget.recordId)
          .maybeSingle();

      labResults = List<Map<String, dynamic>>.from(
        await supabase
            .from('lab_analysis_results')
            .select()
            .eq('coc_record_id', widget.recordId)
            .order('sampling_type'),
      );

      labResultValues = List<Map<String, dynamic>>.from(
        await supabase
            .from('lab_analysis_result_values')
            .select(),
      );

      attachments = List<Map<String, dynamic>>.from(
        await supabase
            .from('attachments')
            .select()
            .eq('coc_record_id', widget.recordId)
            .order('sampling_type'),
      );
    } catch (e) {
      if (!mounted) return;

      if (SessionHandler.isSessionError(e)) {
        await SessionHandler.logoutExpired(context);
        return;
      }

      if (e.toString().toLowerCase().contains('failed host lookup') ||
          e.toString().toLowerCase().contains('socketexception') ||
          e.toString().toLowerCase().contains('network')) {
        setState(() => noInternet = true);
        return;
      }

      AppSnackBar.error(
        context,
        'Failed to load record: ${e.toString().split(':').first}',
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

    await Future.delayed(const Duration(milliseconds: 500));
    await loadRecord();
  }

  List<Map<String, dynamic>> parametersForType(String type) {
    return selectedParameters
        .where((p) => p['sampling_type']?.toString() == type)
        .toList();
  }

  List<Map<String, dynamic>> attachmentsForType(String type) {
    return attachments
        .where((a) => a['sampling_type']?.toString() == type)
        .toList();
  }

  List<Map<String, dynamic>> resultValuesForAnalysis(dynamic analysisId) {
    return labResultValues
        .where((r) => r['analysis_result_id'] == analysisId)
        .toList();
  }

  Future<String?> getSignedImageUrl(String path, String bucket) async {
    try {
      final signedUrl = await supabase.storage
          .from(bucket)
          .createSignedUrl(path, 60 * 60);
      return signedUrl;
    } catch (e) {
      debugPrint('Failed to create signed URL: $e');
      return null;
    }
  }

  Widget sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return NeumoCard(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: title == 'Site Information',
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: 12),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 20),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
          children: [child],
        ),
      ),
    );
  }

  Widget infoRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value?.toString() ?? '-')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (noInternet) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: AppTheme.appBarColor,
          foregroundColor: AppTheme.appBarText,
          elevation: 0,
          title: const Text(
            'View Submission',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.4,
            ),
          ),
        ),
        body: NoInternetState(onRetry: retryAfterNoInternet),
      );
    }

    if (loading) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: AppTheme.appBarColor,
          foregroundColor: AppTheme.appBarText,
          elevation: 0,
          title: const Text(
            'View Submission',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.4,
            ),
          ),
        ),
        body: const LoadingSkeleton(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.appBarColor,
        foregroundColor: AppTheme.appBarText,
        elevation: 0,
        title: const Text(
          'View Submission',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.4,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header Card with Status
            NeumoCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Batch Number',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppTheme.textSoft),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.batchNumber,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.green),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle,
                                size: 16, color: Colors.green),
                            const SizedBox(width: 6),
                            Text(
                              record?['status']?.toString() ?? '-',
                              style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  infoRow('Project Name', record?['project_name']),
                  infoRow('Client Name', record?['client_name']),
                  infoRow('Location', record?['location']),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Site Information Section
            sectionCard(
              title: 'Site Information',
              icon: Icons.location_on,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  infoRow('Monitoring Date',
                      record?['monitoring_date']?.toString().split('T')[0]),
                  infoRow('GPS Latitude', record?['latitude']),
                  infoRow('GPS Longitude', record?['longitude']),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Sampling Details Section
            if (samplingTypes.isNotEmpty)
              sectionCard(
                title: 'Sampling Details',
                icon: Icons.water_drop,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...samplingTypes.map((samplingType) {
                      final typeCode = samplingType['sampling_type'];
                      final params = parametersForType(typeCode);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Sampling Type: $typeCode',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (params.isNotEmpty)
                            ...params.map((param) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        param['parameter_name'] ?? '-',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        param['value'] ?? '-',
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList()
                          else
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                'No parameters selected',
                                style: TextStyle(
                                  color: AppTheme.textSoft,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                        ],
                      );
                    }).toList(),
                  ],
                ),
              ),
            const SizedBox(height: 12),

            // Insitu Results Section
            if (insituResults.isNotEmpty)
              sectionCard(
                title: 'Insitu Results',
                icon: Icons.assessment,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Parameter')),
                          DataColumn(label: Text('Result')),
                          DataColumn(label: Text('Unit')),
                          DataColumn(label: Text('Status')),
                          DataColumn(label: Text('Remarks')),
                        ],
                        rows: insituResults
                            .map(
                              (row) => DataRow(
                                cells: [
                                  DataCell(Text(
                                    row['parameter_name']?.toString() ?? '-',
                                  )),
                                  DataCell(Text(
                                    row['result']?.toString() ?? '-',
                                  )),
                                  DataCell(Text(
                                    row['unit']?.toString() ?? '-',
                                  )),
                                  DataCell(Text(
                                    row['status']?.toString() ?? '-',
                                  )),
                                  DataCell(Text(
                                    row['remarks']?.toString() ?? '-',
                                  )),
                                ],
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),

            // Attachments Section
            if (attachments.isNotEmpty)
              sectionCard(
                title: 'Attachments',
                icon: Icons.attachment,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...attachments.map((attachment) {
                      final filePath = attachment['file_path']?.toString();
                      final samplingType =
                          attachment['sampling_type']?.toString() ?? '-';
                      final notes = attachment['notes']?.toString() ?? '-';

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  'Sampling Type: $samplingType',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primary,
                                  ),
                                ),
                                const Spacer(),
                                const Icon(Icons.image, size: 16),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (filePath != null)
                            FutureBuilder<String?>(
                              future: getSignedImageUrl(filePath, 'coc-attachments'),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return Container(
                                    height: 150,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[200],
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Center(
                                      child: SizedBox(
                                        width: 30,
                                        height: 30,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    ),
                                  );
                                }

                                if (snapshot.hasData && snapshot.data != null) {
                                  return ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      snapshot.data!,
                                      height: 150,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                    ),
                                  );
                                }

                                return Container(
                                  height: 150,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[200],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Center(
                                    child: Icon(Icons.image_not_supported),
                                  ),
                                );
                              },
                            ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Text(
                                'Note: ',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Expanded(
                                child: Text(notes),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],
                      );
                    }).toList(),
                  ],
                ),
              ),
            const SizedBox(height: 12),

            // Lab Acknowledgement Section
            if (acknowledgement != null)
              sectionCard(
                title: 'Lab Acknowledgement',
                icon: Icons.verified,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    infoRow('Lab Name',
                        acknowledgement?['labs']?['lab_name'] ?? '-'),
                    infoRow('Acknowledgement Date',
                        acknowledgement?['acknowledgement_date']?.toString().split('T')[0]),
                    infoRow(
                        'Received By', acknowledgement?['received_by'] ?? '-'),
                    infoRow(
                        'Contact Number',
                        acknowledgement?['contact_number'] ?? '-'),
                    const SizedBox(height: 12),
                    if (acknowledgement?['signature_path'] != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Signature:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          FutureBuilder<String?>(
                            future: getSignedImageUrl(
                              acknowledgement?['signature_path'],
                              'signatures',
                            ),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return Container(
                                  height: 100,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[200],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Center(
                                    child: SizedBox(
                                      width: 30,
                                      height: 30,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                );
                              }

                              if (snapshot.hasData && snapshot.data != null) {
                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    snapshot.data!,
                                    height: 100,
                                    fit: BoxFit.contain,
                                  ),
                                );
                              }

                              return Container(
                                height: 100,
                                decoration: BoxDecoration(
                                  color: Colors.grey[200],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Center(
                                  child: Icon(Icons.image_not_supported),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 12),

            // Read-Only Notice
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.blue.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info,
                    color: Colors.blue,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'This is a read-only view of your submitted Chain of Custody record. You cannot make any changes.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSoft,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
