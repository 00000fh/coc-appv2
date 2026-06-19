import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/neumo_card.dart';
import '../../../shared/widgets/loading_skeleton.dart';
import '../../../shared/widgets/no_internet_state.dart';
import '../../../shared/utils/app_snackbar.dart';
import '../../../shared/utils/session_handler.dart';
import '../../../core/supabase_config.dart';

import '../../notifications/notification_service.dart';

class LabAnalysisScreen extends StatefulWidget {
  final String recordId;
  final String batchNumber;

  const LabAnalysisScreen({
    super.key,
    required this.recordId,
    required this.batchNumber,
  });

  @override
  State<LabAnalysisScreen> createState() => _LabAnalysisScreenState();
}

class _LabAnalysisScreenState extends State<LabAnalysisScreen> {
  bool loading = true;
  bool saving = false;
  bool noInternet = false;

  final List<String> statusOptions = [
    'Comply',
    'Not Comply',
    'Pending Review',
    'Not Applicable',
  ];

  List<Map<String, dynamic>> selectedParameters = [];

  final Map<String, List<Map<String, dynamic>>> groupedParameters = {};

  final Map<String, String> fixedUnits = {
    'pH': '-',
    'Turbidity': 'NTU',
    'E-Coli': 'CFU',
    'Temperature': '°C',
  };

  final Map<String, bool> expandedSections = {};

  final Map<String, List<Map<String, TextEditingController>>> resultRows = {};
  final Map<String, TextEditingController> remarksControllers = {};
  final Map<String, TextEditingController> doeLimitControllers = {};
  final Map<String, TextEditingController> jkrLimitControllers = {};
  final Map<String, TextEditingController> internalLimitControllers = {};
  final Map<String, TextEditingController> baselineLimitControllers = {};
  final Map<String, TextEditingController> analystControllers = {};
  final Map<String, DateTime> analysisDates = {};
  final Map<String, String?> statusValues = {};

  // Certificate attachments - supporting multiple files
  List<Attachment> attachments = [];
  bool _isLoadingAttachments = false;

  @override
  void initState() {
    super.initState();
    loadAllData();
  }

  Future<void> loadAllData() async {
    setState(() {
      loading = true;
      noInternet = false;
    });

    await markAsStartedIfNeeded();
    await loadParameters();
    await loadExistingAttachments();

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
    await loadAllData();
  }

  String keyFor(String samplingType, String parameterName) {
    return '$samplingType::$parameterName';
  }

  String getFixedUnit(String parameterName) {
    if (fixedUnits.containsKey(parameterName)) {
      return fixedUnits[parameterName] ?? '-';
    }
    return 'mg/L';
  }

  Future<void> markAsStartedIfNeeded() async {
    try {
      final record = await supabase
          .from('coc_records')
          .select('status, created_by')
          .eq('id', widget.recordId)
          .single();

      final status = record['status']?.toString() ?? '';
      final initiatorId = record['created_by']?.toString();

      if (status != 'submitted_to_lab') {
        return;
      }

      await supabase
          .from('coc_records')
          .update({'status': 'lab_in_progress'})
          .eq('id', widget.recordId);

      if (initiatorId == null) {
        return;
      }

      await supabase.from('app_notifications').insert({
        'user_id': initiatorId,
        'role': 'initiator',
        'coc_record_id': widget.recordId,
        'title': 'Lab Analysis Started',
        'message': 'Lab has started working on Batch ${widget.batchNumber}.',
        'type': 'lab_in_progress',
        'is_read': false,
      });
    } catch (e) {
      if (SessionHandler.isSessionError(e)) {
        if (!mounted) return;
        await SessionHandler.logoutExpired(context);
        return;
      }

      if (e.toString().toLowerCase().contains('failed host lookup') ||
          e.toString().toLowerCase().contains('socketexception') ||
          e.toString().toLowerCase().contains('network')) {
        setState(() => noInternet = true);
        return;
      }

      debugPrint('Failed to mark lab analysis as started: $e');
    }
  }

  Future<void> loadParameters() async {
    try {
      final response = await supabase
          .from('selected_parameters')
          .select('sampling_type, parameter_name')
          .eq('coc_record_id', widget.recordId)
          .inFilter('sampling_type', ['Water Quality', 'Silt Trap'])
          .order('sampling_type');

      selectedParameters = List<Map<String, dynamic>>.from(response);

      groupedParameters.clear();

      for (final row in selectedParameters) {
        final samplingType = row['sampling_type'].toString();
        groupedParameters[samplingType] ??= [];
        groupedParameters[samplingType]!.add(row);
        expandedSections[samplingType] ??= true;

        final parameterName = row['parameter_name'].toString();
        final key = keyFor(samplingType, parameterName);

        resultRows[key] = [
          {'label': TextEditingController(), 'value': TextEditingController()},
        ];
        remarksControllers[key] = TextEditingController();
        doeLimitControllers[key] = TextEditingController();
        jkrLimitControllers[key] = TextEditingController();
        internalLimitControllers[key] = TextEditingController();
        baselineLimitControllers[key] = TextEditingController();
        analystControllers[key] = TextEditingController();
        analysisDates[key] = DateTime.now();
        statusValues[key] = null;
      }

      await loadExistingResults();
    } catch (e) {
      if (!mounted) return;

      if (SessionHandler.isSessionError(e)) {
        if (!mounted) return;
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
        'Failed to load parameters: ${e.toString().split(':').first}',
      );
    }
  }

  Future<void> loadExistingResults() async {
    try {
      final response = await supabase
          .from('lab_analysis_results')
          .select()
          .eq('coc_record_id', widget.recordId);

      final resultValues = await supabase
          .from('lab_analysis_result_values')
          .select();

      for (final row in response) {
        final samplingType = row['sampling_type'].toString();
        final parameterName = row['parameter_name'].toString();
        final key = keyFor(samplingType, parameterName);
        final analysisId = row['id'];

        final valuesForThisParameter = resultValues
            .where((valueRow) => valueRow['analysis_result_id'] == analysisId)
            .toList();

        if (valuesForThisParameter.isNotEmpty) {
          resultRows[key] = [];

          for (final valueRow in valuesForThisParameter) {
            resultRows[key]!.add({
              'label': TextEditingController(
                text: valueRow['result_label']?.toString() ?? '',
              ),
              'value': TextEditingController(
                text: valueRow['result_value']?.toString() ?? '',
              ),
            });
          }
        }

        remarksControllers[key]?.text = row['remarks']?.toString() ?? '';
        doeLimitControllers[key]?.text = row['doe_limit']?.toString() ?? '';
        jkrLimitControllers[key]?.text = row['jkr_limit']?.toString() ?? '';
        internalLimitControllers[key]?.text =
            row['internal_limit']?.toString() ?? '';
        baselineLimitControllers[key]?.text =
            row['baseline_limit']?.toString() ?? '';
        analystControllers[key]?.text = row['analyst_name']?.toString() ?? '';

        statusValues[key] = row['status']?.toString().isEmpty == true
            ? null
            : row['status']?.toString();

        final dateText = row['analysis_date']?.toString();
        if (dateText != null && dateText.isNotEmpty) {
          analysisDates[key] = DateTime.tryParse(dateText) ?? DateTime.now();
        }
      }
    } catch (e) {
      if (SessionHandler.isSessionError(e)) {
        if (!mounted) return;
        await SessionHandler.logoutExpired(context);
        return;
      }

      if (e.toString().toLowerCase().contains('failed host lookup') ||
          e.toString().toLowerCase().contains('socketexception') ||
          e.toString().toLowerCase().contains('network')) {
        setState(() => noInternet = true);
        return;
      }

      if (mounted) {
        AppSnackBar.error(
          context,
          'Failed to load existing results: ${e.toString().split(':').first}',
        );
      }
    }
  }

  Future<void> loadExistingAttachments() async {
    setState(() => _isLoadingAttachments = true);
    
    try {
      final response = await supabase
          .from('lab_analysis_attachments')
          .select('id, file_name, file_path, file_type, created_at')
          .eq('coc_record_id', widget.recordId)
          .order('created_at', ascending: true);

      attachments = List<Attachment>.from(
        response.map((item) => Attachment(
              id: item['id']?.toString() ?? '',
              fileName: item['file_name']?.toString() ?? '',
              filePath: item['file_path']?.toString() ?? '',
              fileType: item['file_type']?.toString() ?? '',
              createdAt: item['created_at'] != null
                  ? DateTime.parse(item['created_at'].toString())
                  : DateTime.now(),
            ))
      );
      
      debugPrint('Loaded ${attachments.length} attachments from database');
    } catch (e) {
      if (!mounted) return;
      
      if (SessionHandler.isSessionError(e)) {
        await SessionHandler.logoutExpired(context);
        return;
      }

      debugPrint('Failed to load attachments: $e');
    }

    if (mounted) {
      setState(() => _isLoadingAttachments = false);
    }
  }

  bool canCompleteAnalysis() {
    for (final row in selectedParameters) {
      final samplingType = row['sampling_type'].toString();
      final parameterName = row['parameter_name'].toString();
      final key = keyFor(samplingType, parameterName);

      final rows = resultRows[key] ?? [];

      final hasResult = rows.any(
        (r) =>
            r['label']!.text.trim().isNotEmpty &&
            r['value']!.text.trim().isNotEmpty,
      );
      final analyst = analystControllers[key]?.text.trim() ?? '';
      final status = statusValues[key];
      final remarks = remarksControllers[key]?.text.trim() ?? '';

      if (!hasResult || analyst.isEmpty || status == null || remarks.isEmpty) {
        return false;
      }
    }

    return true;
  }

  Future<void> pickCertificate() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );

    if (result == null) return;

    final file = result.files.single;
    
    final extension = file.name.split('.').last.toLowerCase();
    if (extension != 'pdf') {
      if (mounted) {
        AppSnackBar.error(
          context,
          'Only PDF files are allowed. Please select a PDF file.',
        );
      }
      return;
    }

    Uint8List? fileBytes = file.bytes;
    if (fileBytes == null && file.path != null) {
      try {
        final File fileObj = File(file.path!);
        if (await fileObj.exists()) {
          fileBytes = await fileObj.readAsBytes();
        }
      } catch (e) {
        debugPrint('Failed to read file from path: $e');
      }
    }

    if (fileBytes == null) {
      if (mounted) {
        AppSnackBar.error(
          context,
          'Failed to read file. Please try again.',
        );
      }
      return;
    }

    setState(() {
      attachments.add(Attachment(
        id: '',
        fileName: file.name,
        filePath: '',
        fileType: 'pdf',
        createdAt: DateTime.now(),
        bytes: fileBytes,
        isNew: true,
      ));
    });
  }

  void removeAttachment(int index) {
    setState(() {
      final attachment = attachments[index];
      if (!attachment.isNew && attachment.id.isNotEmpty) {
        attachments[index] = attachment.copyWith(markForDeletion: true);
        debugPrint('Marked attachment for deletion: ${attachment.fileName} (${attachment.id})');
      } else {
        attachments.removeAt(index);
        debugPrint('Removed new attachment from list');
      }
    });
  }

  void undoRemoveAttachment(int index) {
    setState(() {
      final attachment = attachments[index];
      if (attachment.markForDeletion) {
        attachments[index] = attachment.copyWith(markForDeletion: false);
        debugPrint('Undo deletion for attachment: ${attachment.fileName}');
      }
    });
  }

  Future<void> deleteAttachmentFromDatabase(String attachmentId) async {
    try {
      // Try direct delete first - most reliable approach
      debugPrint('Attempting direct delete for attachment: $attachmentId');
      
      final result = await supabase
          .from('lab_analysis_attachments')
          .delete()
          .eq('id', attachmentId)
          .select();
      
      debugPrint('Direct delete result: $result');
      
      // Verify deletion
      final verifyDeletion = await supabase
          .from('lab_analysis_attachments')
          .select('id')
          .eq('id', attachmentId);
      
      if (verifyDeletion.isEmpty) {
        debugPrint('✅ Attachment successfully deleted via direct delete!');
        return;
      }
      
      debugPrint('Direct delete failed, trying RPC...');
      
      // Try RPC as fallback
      try {
        final rpcResult = await supabase
            .rpc('delete_attachment', params: {
              'attachment_id': attachmentId,
            });
        
        debugPrint('RPC delete response: $rpcResult');
        
        // Verify again
        final verifyAgain = await supabase
            .from('lab_analysis_attachments')
            .select('id')
            .eq('id', attachmentId);
        
        if (verifyAgain.isEmpty) {
          debugPrint('✅ Attachment deleted via RPC!');
          return;
        }
      } catch (rpcError) {
        debugPrint('RPC delete failed: $rpcError');
      }
      
      // Last resort: Try delete with both conditions
      debugPrint('Trying final fallback delete...');
      await supabase
          .from('lab_analysis_attachments')
          .delete()
          .eq('id', attachmentId)
          .eq('coc_record_id', widget.recordId);
      
      // Final verification
      final finalVerify = await supabase
          .from('lab_analysis_attachments')
          .select('id')
          .eq('id', attachmentId);
      
      if (finalVerify.isEmpty) {
        debugPrint('✅ Attachment deleted via fallback!');
      } else {
        debugPrint('❌ FAILED: Attachment still exists after all delete attempts!');
        // Force delete using raw query
        try {
          await supabase.rpc('delete_attachment_force', params: {
            'attachment_id': attachmentId,
          });
          debugPrint('Force delete attempted');
        } catch (e) {
          debugPrint('Force delete failed: $e');
        }
      }
    } catch (e) {
      debugPrint('Failed to delete attachment $attachmentId: $e');
      rethrow;
    }
  }

  Future<void> saveAnalysis({required bool complete}) async {
    setState(() => saving = true);

    try {
      // Save all analysis results
      for (final row in selectedParameters) {
        final samplingType = row['sampling_type'].toString();
        final parameterName = row['parameter_name'].toString();
        final key = keyFor(samplingType, parameterName);

        final analysisRow = await supabase
            .from('lab_analysis_results')
            .upsert({
              'coc_record_id': widget.recordId,
              'sampling_type': samplingType,
              'parameter_name': parameterName,
              'unit': getFixedUnit(parameterName),
              'analyst_name': analystControllers[key]?.text.trim(),
              'analysis_date': (analysisDates[key] ?? DateTime.now())
                  .toIso8601String()
                  .split('T')
                  .first,
              'remarks': remarksControllers[key]?.text.trim(),
              'doe_limit': doeLimitControllers[key]?.text.trim(),
              'jkr_limit': jkrLimitControllers[key]?.text.trim(),
              'internal_limit': internalLimitControllers[key]?.text.trim(),
              'baseline_limit': baselineLimitControllers[key]?.text.trim(),
              'status': statusValues[key],
            }, onConflict: 'coc_record_id,sampling_type,parameter_name')
            .select()
            .single();

        final analysisId = analysisRow['id'];

        await supabase
            .from('lab_analysis_result_values')
            .delete()
            .eq('analysis_result_id', analysisId);

        final results = resultRows[key] ?? [];

        for (final result in results) {
          final label = (result['label'] as TextEditingController).text.trim();
          final value = (result['value'] as TextEditingController).text.trim();

          if (label.isEmpty || value.isEmpty) {
            continue;
          }

          await supabase.from('lab_analysis_result_values').insert({
            'analysis_result_id': analysisId,
            'result_label': label,
            'result_value': value,
          });
        }
      }

      // Handle attachments - DELETE FIRST
      final attachmentsToDelete = attachments.where((a) => 
        !a.isNew && a.markForDeletion && a.id.isNotEmpty
      ).toList();

      debugPrint('Attachments to delete: ${attachmentsToDelete.length}');

      // Delete marked attachments from storage and database
      for (final attachment in attachmentsToDelete) {
        try {
          debugPrint('Deleting attachment: ${attachment.fileName} (${attachment.id})');
          
          // Delete from storage
          if (attachment.filePath.isNotEmpty) {
            await supabase.storage
                .from('lab-analysis-certificates')
                .remove([attachment.filePath]);
            debugPrint('Deleted from storage: ${attachment.filePath}');
          }
          
          // Delete from database using the dedicated method
          await deleteAttachmentFromDatabase(attachment.id);
        } catch (e) {
          debugPrint('Failed to delete attachment ${attachment.id}: $e');
        }
      }

      // Upload new attachments
      final newAttachments = attachments.where((a) => 
        a.isNew && !a.markForDeletion
      ).toList();

      debugPrint('New attachments to upload: ${newAttachments.length}');

      for (final attachment in newAttachments) {
        if (attachment.bytes == null) continue;

        final storagePath =
            '${widget.recordId}/${DateTime.now().millisecondsSinceEpoch}_${attachment.fileName}';

        try {
          debugPrint('Uploading attachment: ${attachment.fileName}');
          
          await supabase.storage
              .from('lab-analysis-certificates')
              .uploadBinary(storagePath, attachment.bytes!);

          await supabase.from('lab_analysis_attachments').insert({
            'coc_record_id': widget.recordId,
            'file_name': attachment.fileName,
            'file_path': storagePath,
            'file_type': 'pdf',
          });
          
          debugPrint('Uploaded and saved: ${attachment.fileName}');
        } catch (e) {
          debugPrint('Failed to upload attachment ${attachment.fileName}: $e');
          rethrow;
        }
      }

      // Update record status
      await supabase
          .from('coc_records')
          .update({'status': complete ? 'lab_completed' : 'lab_in_progress'})
          .eq('id', widget.recordId);

      if (complete) {
        await NotificationService.notifyRole(
          role: 'admin',
          recordId: widget.recordId,
          title: 'Lab Analysis Completed',
          message:
              'Batch ${widget.batchNumber} lab analysis has been completed.',
          type: 'lab_completed',
        );
      }

      if (!mounted) return;

      AppSnackBar.success(
        context,
        complete ? 'Lab analysis completed' : 'Progress saved',
      );

      if (complete) {
        Navigator.pop(context);
      } else {
        // Clear and reload attachments
        setState(() {
          attachments.clear();
        });
        await loadExistingAttachments();
        setState(() {});
      }
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

      debugPrint('FULL ERROR => $e');

      AppSnackBar.error(
        context,
        'Save failed: ${e.toString().split(':').first}',
      );
    }

    if (mounted) {
      setState(() => saving = false);
    }
  }

  Widget buildResultsSection(String key) {
    final rows = resultRows[key] ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Results', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),

        ...List.generate(rows.length, (index) {
          final row = rows[index];

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: row['label'],
                    decoration: const InputDecoration(hintText: 'Label'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: row['value'],
                    decoration: const InputDecoration(hintText: 'Value'),
                  ),
                ),
                IconButton(
                  onPressed: rows.length == 1
                      ? null
                      : () {
                          setState(() {
                            rows.removeAt(index);
                          });
                        },
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          );
        }),

        OutlinedButton.icon(
          onPressed: () {
            setState(() {
              rows.add({
                'label': TextEditingController(),
                'value': TextEditingController(),
              });
            });
          },
          icon: const Icon(Icons.add),
          label: const Text('Add Result'),
        ),
      ],
    );
  }

  Widget buildParameterCard(Map<String, dynamic> row) {
    final samplingType = row['sampling_type'].toString();
    final parameterName = row['parameter_name'].toString();
    final key = keyFor(samplingType, parameterName);
    final unit = getFixedUnit(parameterName);

    return NeumoCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.science, color: Colors.blue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  parameterName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  unit == '-' ? 'No unit' : unit,
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          buildResultsSection(key),

          const SizedBox(height: 12),
          TextField(
            controller: analystControllers[key],
            decoration: const InputDecoration(
              hintText: 'Analyst Name *',
              prefixIcon: Icon(Icons.person, color: AppTheme.primary),
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () async {
              final pickedDate = await showDatePicker(
                context: context,
                initialDate: analysisDates[key] ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (pickedDate != null) {
                setState(() {
                  analysisDates[key] = pickedDate;
                });
              }
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                hintText: 'Analysis Date',
                prefixIcon: Icon(Icons.calendar_month, color: AppTheme.primary),
              ),
              child: Text(
                '${(analysisDates[key] ?? DateTime.now()).day}/'
                '${(analysisDates[key] ?? DateTime.now()).month}/'
                '${(analysisDates[key] ?? DateTime.now()).year}',
              ),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: statusValues[key],
            decoration: const InputDecoration(
              hintText: 'Status *',
              prefixIcon: Icon(
                Icons.verified_outlined,
                color: AppTheme.primary,
              ),
            ),
            items: statusOptions.map((status) {
              return DropdownMenuItem<String>(
                value: status,
                child: Text(status),
              );
            }).toList(),
            onChanged: (value) {
              setState(() {
                statusValues[key] = value;
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: remarksControllers[key],
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'Remarks *',
              prefixIcon: Icon(Icons.notes, color: AppTheme.primary),
            ),
          ),
          const SizedBox(height: 6),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: const Text(
                'Optional Limit Columns',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              subtitle: const Text(
                'DOE, JKR, internal and baseline limits',
                style: TextStyle(color: AppTheme.textSoft, fontSize: 12),
              ),
              children: [
                TextField(
                  controller: doeLimitControllers[key],
                  decoration: const InputDecoration(
                    hintText: 'DOE Limit',
                    prefixIcon: Icon(Icons.balance, color: AppTheme.primary),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: jkrLimitControllers[key],
                  decoration: const InputDecoration(
                    hintText: 'JKR Limit',
                    prefixIcon: Icon(
                      Icons.account_balance,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: internalLimitControllers[key],
                  decoration: const InputDecoration(
                    hintText: 'Internal Limit',
                    prefixIcon: Icon(
                      Icons.business_center,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: baselineLimitControllers[key],
                  decoration: const InputDecoration(
                    hintText: 'Baseline Limit',
                    prefixIcon: Icon(
                      Icons.stacked_line_chart,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildSamplingSection(String samplingType) {
    final rows = groupedParameters[samplingType] ?? [];
    final expanded = expandedSections[samplingType] ?? true;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(
        children: [
          ListTile(
            title: Text(
              samplingType,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            subtitle: Text('${rows.length} parameter(s)'),
            trailing: Icon(
              expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            ),
            onTap: () {
              setState(() {
                expandedSections[samplingType] = !expanded;
              });
            },
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(children: rows.map(buildParameterCard).toList()),
            ),
        ],
      ),
    );
  }

  Widget buildBatchCard() {
    return NeumoCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.science, color: AppTheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Batch Number',
                  style: TextStyle(color: AppTheme.textSoft, fontSize: 12),
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

  Widget buildAttachmentsSection() {
    final visibleAttachments = attachments.where((a) => !a.markForDeletion).toList();
    final hasAttachments = visibleAttachments.isNotEmpty;
    final hasMarkedForDeletion = attachments.any((a) => a.markForDeletion);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.attach_file, size: 20, color: AppTheme.primary),
            const SizedBox(width: 8),
            const Text(
              'Attachments (PDF only)',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '(${visibleAttachments.length} file${visibleAttachments.length != 1 ? 's' : ''})',
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSoft,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (_isLoadingAttachments)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),

        if (hasAttachments) ...[
          ...List.generate(visibleAttachments.length, (index) {
            final attachment = visibleAttachments[index];
            final originalIndex = attachments.indexOf(attachment);
            
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.green.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.picture_as_pdf,
                    color: Colors.red,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          attachment.fileName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'PDF • ${attachment.isNew ? 'New' : 'Saved'}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => removeAttachment(originalIndex),
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: Colors.red,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            );
          }),
        ],

        OutlinedButton.icon(
          onPressed: pickCertificate,
          icon: const Icon(Icons.add),
          label: const Text('Add PDF Attachment'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),

        if (hasMarkedForDeletion) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.red.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Attachments marked for deletion:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 8),
                ...List.generate(attachments.length, (index) {
                  final attachment = attachments[index];
                  if (!attachment.markForDeletion) return const SizedBox.shrink();
                  
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.delete,
                          size: 16,
                          color: Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            attachment.fileName,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.red,
                              decoration: TextDecoration.lineThrough,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton(
                          onPressed: () => undoRemoveAttachment(index),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Undo'),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ],
    );
  }

  @override
  void dispose() {
    for (final controller in [
      ...remarksControllers.values,
      ...doeLimitControllers.values,
      ...jkrLimitControllers.values,
      ...internalLimitControllers.values,
      ...baselineLimitControllers.values,
      ...analystControllers.values,
    ]) {
      controller.dispose();
    }
    for (final rows in resultRows.values) {
      for (final row in rows) {
        (row['label'] as TextEditingController).dispose();
        (row['value'] as TextEditingController).dispose();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (noInternet) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: AppTheme.appBarColor,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'Lab Analysis',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        body: NoInternetState(onRetry: retryAfterNoInternet),
      );
    }

    if (loading) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: AppTheme.appBarColor,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'Lab Analysis',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
          'Lab Analysis',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            buildBatchCard(),
            const SizedBox(height: 14),
            ...groupedParameters.keys.map(buildSamplingSection),
            const SizedBox(height: 20),
            NeumoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildAttachmentsSection(),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: saving
                                ? null
                                : () => saveAnalysis(complete: false),
                            icon: const Icon(Icons.save),
                            label: Text(saving ? 'Saving...' : 'Save'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: saving || !canCompleteAnalysis()
                                ? null
                                : () => saveAnalysis(complete: true),
                            icon: const Icon(Icons.check_circle),
                            label: const Text('Complete'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!canCompleteAnalysis()) ...[
                    const SizedBox(height: 10),
                    const Text(
                      'Complete all required fields to enable final submission.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textSoft, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class Attachment {
  final String id;
  final String fileName;
  final String filePath;
  final String fileType;
  final DateTime createdAt;
  final Uint8List? bytes;
  final bool isNew;
  final bool markForDeletion;

  Attachment({
    required this.id,
    required this.fileName,
    required this.filePath,
    required this.fileType,
    required this.createdAt,
    this.bytes,
    this.isNew = false,
    this.markForDeletion = false,
  });

  Attachment copyWith({
    String? id,
    String? fileName,
    String? filePath,
    String? fileType,
    DateTime? createdAt,
    Uint8List? bytes,
    bool? isNew,
    bool? markForDeletion,
  }) {
    return Attachment(
      id: id ?? this.id,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      fileType: fileType ?? this.fileType,
      createdAt: createdAt ?? this.createdAt,
      bytes: bytes ?? this.bytes,
      isNew: isNew ?? this.isNew,
      markForDeletion: markForDeletion ?? this.markForDeletion,
    );
  }
}