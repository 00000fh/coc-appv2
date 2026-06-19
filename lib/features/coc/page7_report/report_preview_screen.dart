import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:http/http.dart' as http;
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/neumo_card.dart';
import '../../../shared/widgets/loading_skeleton.dart';
import '../../../shared/widgets/no_internet_state.dart';
import '../../../shared/utils/app_snackbar.dart';
import '../../../shared/utils/session_handler.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../core/supabase_config.dart';

class ReportPreviewScreen extends StatefulWidget {
  final String recordId;
  final String batchNumber;

  const ReportPreviewScreen({
    super.key,
    required this.recordId,
    required this.batchNumber,
  });

  @override
  State<ReportPreviewScreen> createState() => _ReportPreviewScreenState();
}

class _ReportPreviewScreenState extends State<ReportPreviewScreen> {
  bool loading = true;
  bool noInternet = false;
  bool generatingPdf = false;

  Map<String, dynamic>? record;
  Map<String, dynamic>? acknowledgement;
  List<Map<String, dynamic>> labAnalysisAttachments = [];
  String userRole = '';

  List<Map<String, dynamic>> samplingTypes = [];
  List<Map<String, dynamic>> selectedParameters = [];
  List<Map<String, dynamic>> insituResults = [];
  List<Map<String, dynamic>> labResults = [];
  List<Map<String, dynamic>> labResultValues = [];
  List<Map<String, dynamic>> insituResultValues = [];
  List<Map<String, dynamic>> attachments = [];

  @override
  void initState() {
    super.initState();
    loadReport();
  }

  // Helper to get all unique result labels
  List<String> getAllResultLabels() {
    final labels = labResultValues
        .map((e) => e['result_label']?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    labels.sort();

    return labels;
  }

  // Helper to get all unique insitu result labels
  List<String> getAllInsituResultLabels() {
    final labels = insituResultValues
        .map((e) => e['result_label']?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    labels.sort();

    return labels;
  }

  // Helper to get value by label for a specific analysis
  String getResultValue(
    dynamic analysisId,
    String label,
  ) {
    final row = labResultValues.firstWhere(
      (e) =>
          e['analysis_result_id'] == analysisId &&
          e['result_label'] == label,
      orElse: () => {},
    );

    return row['result_value']?.toString() ?? '-';
  }

  // Helper to get insitu value by label for a specific result
  String getInsituResultValue(
    dynamic insituId,
    String label,
  ) {
    final row = insituResultValues.firstWhere(
      (e) =>
          e['insitu_result_id'] == insituId &&
          e['result_label'] == label,
      orElse: () => {},
    );

    return row['result_value']?.toString() ?? '-';
  }

  // Helper to build result text for PDF (single column with all labels and values)
  String buildResultText(dynamic analysisId) {
    final values = resultValuesForAnalysis(analysisId);

    if (values.isEmpty) return '-';

    return values
        .map((v) => '${v['result_label']}: ${v['result_value']}')
        .join('\n');
  }

  // Helper methods to check if limit columns have any data
  bool hasDoeValues() {
    return insituResults.any(
          (e) => (e['doe_limit']?.toString().trim().isNotEmpty ?? false),
        ) ||
        labResults.any(
          (e) => (e['doe_limit']?.toString().trim().isNotEmpty ?? false),
        );
  }

  bool hasJkrValues() {
    return insituResults.any(
          (e) => (e['jkr_limit']?.toString().trim().isNotEmpty ?? false),
        ) ||
        labResults.any(
          (e) => (e['jkr_limit']?.toString().trim().isNotEmpty ?? false),
        );
  }

  bool hasInternalValues() {
    return insituResults.any(
          (e) => (e['internal_limit']?.toString().trim().isNotEmpty ?? false),
        ) ||
        labResults.any(
          (e) => (e['internal_limit']?.toString().trim().isNotEmpty ?? false),
        );
  }

  bool hasBaselineValues() {
    return insituResults.any(
          (e) => (e['baseline_limit']?.toString().trim().isNotEmpty ?? false),
        ) ||
        labResults.any(
          (e) => (e['baseline_limit']?.toString().trim().isNotEmpty ?? false),
        );
  }

  // Enhanced download function for storage files
  Future<Uint8List?> downloadStorageFileBytes(
    String path,
    String bucket,
  ) async {
    if (path.isEmpty) return null;

    debugPrint('🔍 Attempting to download file: $path');
    debugPrint('📦 Bucket: $bucket');
    
    Uint8List? downloadedBytes;

    // METHOD 1: Direct download using the full path from database
    try {
      debugPrint('📥 Method 1: Direct download with full path');
      downloadedBytes = await supabase.storage.from(bucket).download(path);
      debugPrint('✅ Downloaded via direct path!');
      return downloadedBytes;
    } catch (e) {
      debugPrint('Method 1 failed: ${e.toString().substring(0, e.toString().length > 100 ? 100 : e.toString().length)}');
    }

    // METHOD 2: Try signed URL (bypasses RLS for downloads)
    if (downloadedBytes == null) {
      try {
        debugPrint('📥 Method 2: Signed URL');
        final signedUrl = await supabase.storage
            .from(bucket)
            .createSignedUrl(path, 300);
        
        final response = await http.get(Uri.parse(signedUrl));
        
        if (response.statusCode == 200) {
          downloadedBytes = response.bodyBytes;
          debugPrint('✅ Downloaded via signed URL!');
          return downloadedBytes;
        } else {
          debugPrint('Signed URL returned status: ${response.statusCode}');
        }
      } catch (e) {
        debugPrint('Method 2 failed: ${e.toString().substring(0, e.toString().length > 100 ? 100 : e.toString().length)}');
      }
    }

    // METHOD 3: Try public URL (if bucket is public)
    if (downloadedBytes == null) {
      try {
        debugPrint('📥 Method 3: Public URL');
        final publicUrl = supabase.storage.from(bucket).getPublicUrl(path);
        
        final response = await http.get(Uri.parse(publicUrl));
        
        if (response.statusCode == 200) {
          downloadedBytes = response.bodyBytes;
          debugPrint('✅ Downloaded via public URL!');
          return downloadedBytes;
        } else {
          debugPrint('Public URL returned status: ${response.statusCode}');
        }
      } catch (e) {
        debugPrint('Method 3 failed: ${e.toString().substring(0, e.toString().length > 100 ? 100 : e.toString().length)}');
      }
    }

    // METHOD 4: Try with just the filename (if file is in root)
    if (downloadedBytes == null) {
      try {
        final fileNameOnly = path.split('/').last;
        debugPrint('📥 Method 4: Download by filename only: $fileNameOnly');
        downloadedBytes = await supabase.storage.from(bucket).download(fileNameOnly);
        debugPrint('✅ Downloaded via filename only!');
        return downloadedBytes;
      } catch (e) {
        debugPrint('Method 4 failed: ${e.toString().substring(0, e.toString().length > 100 ? 100 : e.toString().length)}');
      }
    }

    debugPrint('❌ All download methods failed for: $path');
    return null;
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

  Future<void> loadReport() async {
    setState(() {
      loading = true;
      noInternet = false;
    });

    try {
      // Fetch user role
      final user = supabase.auth.currentUser;
      if (user != null) {
        final profile = await supabase
            .from('profiles')
            .select('role')
            .eq('id', user.id)
            .single();
        userRole = profile['role'] ?? 'initiator';
      }

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

      insituResultValues = List<Map<String, dynamic>>.from(
        await supabase
            .from('insitu_result_values')
            .select(),
      );

      attachments = List<Map<String, dynamic>>.from(
        await supabase
            .from('attachments')
            .select()
            .eq('coc_record_id', widget.recordId)
            .order('sampling_type'),
      );

      // Load lab analysis attachments (multiple)
      final attachmentResponse = await supabase
          .from('lab_analysis_attachments')
          .select()
          .eq('coc_record_id', widget.recordId)
          .order('created_at', ascending: true);

      labAnalysisAttachments = List<Map<String, dynamic>>.from(attachmentResponse);
      
      debugPrint('Loaded ${labAnalysisAttachments.length} lab analysis attachments');
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
        'Failed to load report: ${e.toString().split(':').first}',
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

    await loadReport();
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

  List<Map<String, dynamic>> resultValuesForAnalysis(
    dynamic analysisId,
  ) {
    return labResultValues
        .where(
          (r) => r['analysis_result_id'] == analysisId,
        )
        .toList();
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

  Widget simpleTable({
    required List<String> headers,
    required List<List<String>> rows,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: headers.map((h) => DataColumn(label: Text(h))).toList(),
        rows: rows.map((row) {
          return DataRow(
            cells: row.map((cell) => DataCell(Text(cell))).toList(),
          );
        }).toList(),
      ),
    );
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  Future<void> downloadLabAttachment(String filePath, String fileName) async {
    if (filePath.isEmpty) {
      AppSnackBar.error(context, 'File path not found');
      return;
    }

    try {
      final snackBar = ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 12),
              Text('Downloading...'),
            ],
          ),
          duration: Duration(days: 1),
        ),
      );

      debugPrint('📥 Attempting to download file: $filePath');
      debugPrint('📄 File name: $fileName');
      
      final bucketName = 'lab-analysis-certificates';

      final downloadedBytes = await downloadStorageFileBytes(
        filePath,
        bucketName,
      );

      snackBar.close();

      if (downloadedBytes == null) {
        if (!mounted) return;
        
        AppSnackBar.error(
          context,
          'File not found. The attachment may have been moved or deleted.',
        );
        
        debugPrint('❌ FAILED to download file with path: $filePath');
        debugPrint('Record ID: ${widget.recordId}');
        
        return;
      }

      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$fileName');
      await file.writeAsBytes(downloadedBytes);

      if (!mounted) return;

      AppSnackBar.success(context, 'File downloaded successfully!');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Downloaded: $fileName'),
          action: SnackBarAction(
            label: 'OPEN',
            onPressed: () async {
              await OpenFilex.open(file.path);
            },
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).clearSnackBars();
      
      AppSnackBar.error(
        context,
        'Failed to download: ${e.toString().split(':').first}',
      );
    }
  }

  Widget buildLabAnalysisAttachmentsSection() {
    if (labAnalysisAttachments.isEmpty) {
      return const SizedBox();
    }

    return NeumoCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.attach_file,
                    color: AppTheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Lab Analysis Attachments',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppTheme.textDark,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${labAnalysisAttachments.length} file${labAnalysisAttachments.length > 1 ? 's' : ''}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...List.generate(labAnalysisAttachments.length, (index) {
              final attachment = labAnalysisAttachments[index];
              final fileName = attachment['file_name']?.toString() ?? 'Unknown';
              final fileType = attachment['file_type']?.toString() ?? 'pdf';
              final createdAt = attachment['created_at']?.toString() ?? '';
              final filePath = attachment['file_path']?.toString() ?? '';

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.grey.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.picture_as_pdf,
                        color: Colors.red,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fileName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.textDark,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  fileType.toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (createdAt.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Text(
                                  _formatDate(createdAt),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textSoft,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => downloadLabAttachment(filePath, fileName),
                      icon: const Icon(
                        Icons.download,
                        color: AppTheme.primary,
                      ),
                      tooltip: 'Download',
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> generatePdf() async {
    setState(() => generatingPdf = true);

    final pdf = pw.Document();

    final now = DateTime.now();
    final generatedDate = '${now.day}/${now.month}/${now.year}';

    final logoData = await rootBundle.load(
      'assets/images/sfelogo.png',
    );

    final logoImage = pw.MemoryImage(
      logoData.buffer.asUint8List(),
    );

    final titleStyle = pw.TextStyle(
      fontSize: 18,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.blueGrey900,
    );

    final sectionStyle = pw.TextStyle(
      fontSize: 12,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.blueGrey900,
    );

    final headerStyle = pw.TextStyle(
      fontSize: 9,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.white,
    );

    final bodyStyle = const pw.TextStyle(fontSize: 8.5, color: PdfColors.black);

    final smallStyle = const pw.TextStyle(
      fontSize: 7.5,
      color: PdfColors.grey700,
    );

    final showDoe = hasDoeValues();
    final showJkr = hasJkrValues();
    final showInternal = hasInternalValues();
    final showBaseline = hasBaselineValues();

    pw.Widget sectionHeader(String title) {
      return pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: const pw.BoxDecoration(
          color: PdfColors.blueGrey100,
          border: pw.Border(
            left: pw.BorderSide(color: PdfColors.blueGrey800, width: 3),
          ),
        ),
        child: pw.Text(title, style: sectionStyle),
      );
    }

    pw.Widget formalTable({
      required List<String> headers,
      required List<List<String>> data,
      Map<int, pw.TableColumnWidth>? columnWidths,
    }) {
      return pw.TableHelper.fromTextArray(
        headers: headers,
        data: data.isEmpty ? [headers.map((_) => '-').toList()] : data,
        border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.35),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
        oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
        headerStyle: headerStyle,
        cellStyle: bodyStyle,
        cellAlignment: pw.Alignment.centerLeft,
        headerAlignment: pw.Alignment.centerLeft,
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
        columnWidths: columnWidths,
      );
    }

    // Process attachments in parallel for better performance
    final attachmentWidgets = <pw.Widget>[];
    
    if (attachments.isNotEmpty) {
      // Download all images in parallel
      final downloadTasks = attachments.map((row) async {
        final path = row['file_path']?.toString();
        if (path == null) return null;
        
        final imageBytes = await downloadStorageFileBytes(
          path,
          'coc-attachments',
        );
        
        if (imageBytes == null) return null;
        
        return {
          'samplingType': row['sampling_type']?.toString() ?? '-',
          'notes': row['notes']?.toString() ?? '-',
          'imageBytes': imageBytes,
        };
      }).toList();
      
      // Wait for all downloads to complete
      final results = await Future.wait(downloadTasks);
      
      // Build widgets from downloaded images
      for (final result in results) {
        if (result == null) continue;
        
        attachmentWidgets.add(
          pw.Container(
            width: 250,
            margin: const pw.EdgeInsets.only(right: 12, bottom: 12),
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey500, width: 0.4),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  result['samplingType'] as String,
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Container(
                  height: 120,
                  width: double.infinity,
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300, width: 0.3),
                  ),
                  child: pw.Image(
                    pw.MemoryImage(result['imageBytes'] as Uint8List),
                    fit: pw.BoxFit.contain,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'Note: ${result['notes'] as String}',
                  style: smallStyle,
                  maxLines: 3,
                ),
              ],
            ),
          ),
        );
      }
    }

    pw.Widget? signatureWidget;

    final signaturePath = acknowledgement?['signature_path']?.toString();

    if (signaturePath != null) {
      final signatureBytes = await downloadStorageFileBytes(
        signaturePath,
        'signatures',
      );

      if (signatureBytes != null) {
        signatureWidget = pw.Container(
          height: 70,
          width: 180,
          padding: const pw.EdgeInsets.all(6),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey600, width: 0.4),
          ),
          child: pw.Image(
            pw.MemoryImage(signatureBytes),
            fit: pw.BoxFit.contain,
          ),
        );
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.fromLTRB(26, 24, 26, 24),
        ),
        header: (context) {
          return pw.Column(
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Image(
                    logoImage,
                    width: 120,
                    height: 45,
                    fit: pw.BoxFit.contain,
                  ),
                  pw.SizedBox(width: 15),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'SFE CONSULTANT',
                          style: pw.TextStyle(
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blueGrey900,
                          ),
                        ),
                        pw.Text(
                          'Chain of Custody Report',
                          style: smallStyle,
                        ),
                      ],
                    ),
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Document No.: ${widget.batchNumber}',
                        style: smallStyle,
                      ),
                      pw.Text(
                        'Generated: $generatedDate',
                        style: smallStyle,
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Divider(color: PdfColors.blueGrey700, thickness: 1),
            ],
          );
        },
        footer: (context) {
          return pw.Column(
            children: [
              pw.Divider(color: PdfColors.grey500, thickness: 0.4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Confidential - For internal monitoring and reporting use only',
                    style: smallStyle,
                  ),
                  pw.Text(
                    'Page ${context.pageNumber} of ${context.pagesCount}',
                    style: smallStyle,
                  ),
                ],
              ),
            ],
          );
        },
        build: (context) {
          final lab = record?['labs'];
          final labName = lab == null
              ? '-'
              : lab['lab_name']?.toString() ?? '-';

          final insituHeaders = [
            'Parameter',
            'Result',
            'Unit',
            'Status',
            'Remarks',
            if (showDoe) 'DOE',
            if (showJkr) 'JKR',
            if (showInternal) 'Internal',
            if (showBaseline) 'Baseline',
          ];

          final insituRows = insituResults.map((row) {
            return [
              row['parameter_name']?.toString() ?? '-',
              row['result']?.toString() ?? '-',
              row['unit']?.toString() ?? '-',
              row['status']?.toString() ?? '-',
              row['remarks']?.toString() ?? '-',
              if (showDoe) row['doe_limit']?.toString() ?? '-',
              if (showJkr) row['jkr_limit']?.toString() ?? '-',
              if (showInternal) row['internal_limit']?.toString() ?? '-',
              if (showBaseline) row['baseline_limit']?.toString() ?? '-',
            ];
          }).toList();

          final labHeaders = [
            'Sampling Type',
            'Parameter',
            'Results',
            'Unit',
            'Status',
            'Analyst',
            'Date',
            'Remarks',
            if (showDoe) 'DOE',
            if (showJkr) 'JKR',
            if (showInternal) 'Internal',
            if (showBaseline) 'Baseline',
          ];

          final labRows = labResults.map((row) {
            final resultText = buildResultText(row['id']);
            
            return [
              row['sampling_type']?.toString() ?? '-',
              row['parameter_name']?.toString() ?? '-',
              resultText,
              row['unit']?.toString() ?? '-',
              row['status']?.toString() ?? '-',
              row['analyst_name']?.toString() ?? '-',
              row['analysis_date']?.toString() ?? '-',
              row['remarks']?.toString() ?? '-',
              if (showDoe) row['doe_limit']?.toString() ?? '-',
              if (showJkr) row['jkr_limit']?.toString() ?? '-',
              if (showInternal) row['internal_limit']?.toString() ?? '-',
              if (showBaseline) row['baseline_limit']?.toString() ?? '-',
            ];
          }).toList();

          return [
            pw.Center(
              child: pw.Text(
                'CHAIN OF CUSTODY FIELD MONITORING REPORT',
                style: titleStyle,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Center(
              child: pw.Text(
                'Batch Number: ${widget.batchNumber}',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blueGrey700,
                ),
              ),
            ),
            pw.SizedBox(height: 16),
            sectionHeader('1. SITE INFORMATION'),
            pw.SizedBox(height: 6),
            formalTable(
              headers: ['Item', 'Details'],
              columnWidths: {
                0: const pw.FlexColumnWidth(2),
                1: const pw.FlexColumnWidth(6),
              },
              data: [
                ['Project Name', record?['project_name']?.toString() ?? '-'],
                ['Client Name', record?['client_name']?.toString() ?? '-'],
                [
                  'Monitoring Date',
                  record?['monitoring_date']?.toString() ?? '-',
                ],
                ['Location', record?['location']?.toString() ?? '-'],
                [
                  'Coordinate',
                  '${record?['latitude'] ?? '-'}, ${record?['longitude'] ?? '-'}',
                ],
                ['Assigned Lab', labName],
                ['Record Status', record?['status']?.toString() ?? '-'],
              ],
            ),
            pw.SizedBox(height: 14),
            sectionHeader('2. SAMPLING DETAILS'),
            pw.SizedBox(height: 6),
            formalTable(
              headers: ['Sampling Type', 'Duration', 'Selected Parameters'],
              columnWidths: {
                0: const pw.FlexColumnWidth(2),
                1: const pw.FlexColumnWidth(1.5),
                2: const pw.FlexColumnWidth(6),
              },
              data: samplingTypes.map((row) {
                final type = row['sampling_type'].toString();
                final params = parametersForType(
                  type,
                ).map((p) => p['parameter_name'].toString()).join(', ');

                return [
                  type,
                  row['duration']?.toString() ?? '-',
                  params.isEmpty ? '-' : params,
                ];
              }).toList(),
            ),
            pw.SizedBox(height: 14),
            sectionHeader('3. INSITU RESULT'),
            pw.SizedBox(height: 6),
            formalTable(
              headers: insituHeaders,
              columnWidths: {
                0: const pw.FlexColumnWidth(2),
                1: const pw.FlexColumnWidth(1),
                2: const pw.FlexColumnWidth(1),
                3: const pw.FlexColumnWidth(1.2),
                4: const pw.FlexColumnWidth(2.2),
                if (showDoe) 5: const pw.FlexColumnWidth(1),
                if (showJkr && !showDoe) 5: const pw.FlexColumnWidth(1),
                if (showJkr && showDoe) 6: const pw.FlexColumnWidth(1),
                if (showInternal && !showJkr && !showDoe) 5: const pw.FlexColumnWidth(1),
                if (showInternal && (showJkr || showDoe)) 6: const pw.FlexColumnWidth(1),
                if (showInternal && showJkr && showDoe) 7: const pw.FlexColumnWidth(1),
                if (showBaseline) 8: const pw.FlexColumnWidth(1),
              },
              data: insituRows,
            ),
            pw.SizedBox(height: 14),
            sectionHeader('4. LAB ANALYSIS RESULT'),
            pw.SizedBox(height: 6),
            formalTable(
              headers: labHeaders,
              columnWidths: {
                0: const pw.FlexColumnWidth(1.6),
                1: const pw.FlexColumnWidth(1.8),
                2: const pw.FlexColumnWidth(2.5),
                3: const pw.FlexColumnWidth(0.8),
                4: const pw.FlexColumnWidth(1.4),
                5: const pw.FlexColumnWidth(1.2),
                6: const pw.FlexColumnWidth(1.3),
                7: const pw.FlexColumnWidth(1.4),
                if (showDoe) 8: const pw.FlexColumnWidth(0.9),
                if (showJkr && !showDoe) 8: const pw.FlexColumnWidth(0.9),
                if (showJkr && showDoe) 9: const pw.FlexColumnWidth(0.9),
                if (showInternal && !showJkr && !showDoe) 8: const pw.FlexColumnWidth(0.9),
                if (showInternal && (showJkr || showDoe)) 9: const pw.FlexColumnWidth(0.9),
                if (showInternal && showJkr && showDoe) 10: const pw.FlexColumnWidth(0.9),
                if (showBaseline) 11: const pw.FlexColumnWidth(0.9),
              },
              data: labRows,
            ),
            pw.SizedBox(height: 14),
            sectionHeader('5. LAB ACKNOWLEDGEMENT'),
            pw.SizedBox(height: 6),
            formalTable(
              headers: ['Item', 'Details'],
              columnWidths: {
                0: const pw.FlexColumnWidth(2),
                1: const pw.FlexColumnWidth(6),
              },
              data: [
                [
                  'Lab',
                  acknowledgement?['labs']?['lab_name']?.toString() ?? '-',
                ],
                ['Lab PIC', acknowledgement?['lab_pic']?.toString() ?? '-'],
                [
                  'Typed Name',
                  acknowledgement?['typed_name']?.toString() ?? '-',
                ],
                [
                  'Acknowledged At',
                  acknowledgement?['acknowledged_at']?.toString() ?? '-',
                ],
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Digital Signature',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 6),
                      signatureWidget ??
                          pw.Container(
                            height: 70,
                            width: 180,
                            alignment: pw.Alignment.center,
                            decoration: pw.BoxDecoration(
                              border: pw.Border.all(
                                color: PdfColors.grey600,
                                width: 0.4,
                              ),
                            ),
                            child: pw.Text(
                              'No signature available',
                              style: smallStyle,
                            ),
                          ),
                    ],
                  ),
                ),
                pw.Container(
                  width: 220,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Divider(color: PdfColors.black),
                      pw.Text(
                        'Authorized Lab Representative',
                        style: smallStyle,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (attachmentWidgets.isNotEmpty) ...[
              pw.NewPage(),
              sectionHeader('6. ATTACHMENT EVIDENCE'),
              pw.SizedBox(height: 10),
              pw.Wrap(spacing: 10, runSpacing: 10, children: attachmentWidgets),
            ],
          ];
        },
      ),
    );

    final bytes = await pdf.save();

    final directory = await getApplicationDocumentsDirectory();
    final fileName = '${widget.batchNumber.replaceAll('/', '-')}_report.pdf';
    final file = File('${directory.path}/$fileName');

    await file.writeAsBytes(bytes);

    if (!mounted) {
      setState(() => generatingPdf = false);
      return;
    }

    setState(() => generatingPdf = false);

    AppSnackBar.success(context, 'PDF generated successfully!');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('PDF saved to:\n${file.path}'),
        action: SnackBarAction(
          label: 'OPEN',
          onPressed: () async {
            await OpenFilex.open(file.path);
          },
        ),
      ),
    );
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
            'Report Preview',
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
            'Report Preview',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        body: const LoadingSkeleton(),
      );
    }

    final lab = record?['labs'];
    final labName = lab == null ? '-' : lab['lab_name']?.toString() ?? '-';
    
    final resultLabels = getAllResultLabels();
    final insituResultLabels = getAllInsituResultLabels();
    
    final showDoe = hasDoeValues();
    final showJkr = hasJkrValues();
    final showInternal = hasInternalValues();
    final showBaseline = hasBaselineValues();

    final isAdmin = userRole == 'admin';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.appBarColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Report Preview',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: loadReport,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            NeumoCard(
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.description,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.batchNumber,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: AppTheme.textDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          record?['project_name']?.toString() ?? '-',
                          style: const TextStyle(color: AppTheme.textSoft),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Client: ${record?['client_name'] ?? '-'}',
                          style: const TextStyle(
                            color: AppTheme.textSoft,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            sectionCard(
              title: 'Site Information',
              icon: Icons.location_on,
              child: Column(
                children: [
                  infoRow('Project Name', record?['project_name']),
                  infoRow('Client Name', record?['client_name']),
                  infoRow('Date', record?['monitoring_date']),
                  infoRow('Location', record?['location']),
                  infoRow(
                    'Coordinate',
                    '${record?['latitude'] ?? '-'}, ${record?['longitude'] ?? '-'}',
                  ),
                  infoRow('Assigned Lab', labName),
                  infoRow('Status', record?['status']),
                ],
              ),
            ),
            sectionCard(
              title: 'Sampling Details',
              icon: Icons.checklist,
              child: samplingTypes.isEmpty
                  ? const Text('No sampling details found.')
                  : Column(
                      children: samplingTypes.map((row) {
                        final type = row['sampling_type'].toString();
                        final params = parametersForType(
                          type,
                        ).map((p) => p['parameter_name'].toString()).join(', ');

                        return ListTile(
                          title: Text(type),
                          subtitle: Text(
                            'Duration: ${row['duration'] ?? '-'}\n'
                            'Parameters: ${params.isEmpty ? '-' : params}',
                          ),
                        );
                      }).toList(),
                    ),
            ),
            sectionCard(
              title: 'Attachments Summary',
              icon: Icons.image,
              child: attachments.isEmpty
                  ? const Text('No attachments found.')
                  : Column(
                      children: samplingTypes.map((typeRow) {
                        final type = typeRow['sampling_type'].toString();
                        final typeAttachments = attachmentsForType(type);

                        if (typeAttachments.isEmpty) {
                          return const SizedBox();
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              type,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 240,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: typeAttachments.length,
                                itemBuilder: (context, index) {
                                  final row = typeAttachments[index];
                                  final imagePath = row['file_path']
                                      ?.toString();

                                  return Container(
                                    width: 220,
                                    margin: const EdgeInsets.only(right: 12),
                                    child: Card(
                                      child: Padding(
                                        padding: const EdgeInsets.all(10),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: imagePath == null
                                                  ? Container(
                                                      alignment:
                                                          Alignment.center,
                                                      child: const Text(
                                                        'No image',
                                                      ),
                                                    )
                                                  : FutureBuilder<String?>(
                                                      future: getSignedImageUrl(
                                                        imagePath,
                                                        'coc-attachments',
                                                      ),
                                                      builder: (context, snapshot) {
                                                        if (snapshot
                                                                .connectionState ==
                                                            ConnectionState
                                                                .waiting) {
                                                          return const Center(
                                                            child:
                                                                CircularProgressIndicator(),
                                                          );
                                                        }
                                                        if (!snapshot.hasData ||
                                                            snapshot.data ==
                                                                null) {
                                                          return const Center(
                                                            child: Text(
                                                              'Failed to load image',
                                                            ),
                                                          );
                                                        }
                                                        final signedUrl =
                                                            snapshot.data!;
                                                        return GestureDetector(
                                                          onTap: () {
                                                            showDialog(
                                                              context: context,
                                                              builder: (_) {
                                                                return Dialog(
                                                                  child: InteractiveViewer(
                                                                    child: Image.network(
                                                                      signedUrl,
                                                                      fit: BoxFit
                                                                          .contain,
                                                                    ),
                                                                  ),
                                                                );
                                                              },
                                                            );
                                                          },
                                                          child: ClipRRect(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                            child:
                                                                Image.network(
                                                                  signedUrl,
                                                                  fit: BoxFit
                                                                      .cover,
                                                                  width: double
                                                                      .infinity,
                                                                ),
                                                          ),
                                                        );
                                                      },
                                                    ),
                                            ),
                                            const SizedBox(height: 10),
                                            Text(
                                              row['notes']?.toString() ?? '-',
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                        );
                      }).toList(),
                    ),
            ),
            sectionCard(
              title: 'Insitu Result',
              icon: Icons.water_drop,
              child: insituResults.isEmpty
                  ? const Text('No insitu result found.')
                  : simpleTable(
                      headers: [
                        'Parameter',
                        ...insituResultLabels,
                        'Unit',
                        'Status',
                        'Remarks',
                        if (showDoe) 'DOE',
                        if (showJkr) 'JKR',
                        if (showInternal) 'Internal',
                        if (showBaseline) 'Baseline',
                      ],
                      rows: insituResults.map((row) {
                        final resultColumns = insituResultLabels.map(
                          (label) => getInsituResultValue(row['id'], label),
                        ).toList();

                        return [
                          row['parameter_name']?.toString() ?? '-',
                          ...resultColumns,
                          row['unit']?.toString() ?? '-',
                          row['status']?.toString() ?? '-',
                          row['remarks']?.toString() ?? '-',
                          if (showDoe) row['doe_limit']?.toString() ?? '-',
                          if (showJkr) row['jkr_limit']?.toString() ?? '-',
                          if (showInternal) row['internal_limit']?.toString() ?? '-',
                          if (showBaseline) row['baseline_limit']?.toString() ?? '-',
                        ];
                      }).toList(),
                    ),
            ),
            sectionCard(
              title: 'Lab Acknowledgement',
              icon: Icons.assignment_turned_in,
              child: acknowledgement == null
                  ? const Text('No lab acknowledgement found.')
                  : Column(
                      children: [
                        infoRow('Lab', acknowledgement?['labs']?['lab_name']),
                        infoRow('Lab PIC', acknowledgement?['lab_pic']),
                        infoRow('Typed Name', acknowledgement?['typed_name']),
                        infoRow(
                          'Acknowledged At',
                          acknowledgement?['acknowledged_at'],
                        ),
                        const SizedBox(height: 12),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Signature',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (acknowledgement?['signature_path'] != null)
                          FutureBuilder<String?>(
                            future: getSignedImageUrl(
                              acknowledgement!['signature_path'].toString(),
                              'signatures',
                            ),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const SizedBox(
                                  height: 120,
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }
                              if (!snapshot.hasData || snapshot.data == null) {
                                return const Text('Failed to load signature');
                              }
                              return Container(
                                height: 120,
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Image.network(
                                  snapshot.data!,
                                  fit: BoxFit.contain,
                                ),
                              );
                            },
                          )
                        else
                          const Text('No signature uploaded.'),
                      ],
                    ),
            ),
            if (isAdmin)
              sectionCard(
                title: 'Lab Analysis',
                icon: Icons.science,
                child: labResults.isEmpty
                    ? const Text('No lab analysis result found.')
                    : simpleTable(
                        headers: [
                          'Type',
                          'Parameter',
                          ...resultLabels,
                          'Unit',
                          'Status',
                          'Analyst',
                          'Date',
                          'Remarks',
                          if (showDoe) 'DOE',
                          if (showJkr) 'JKR',
                          if (showInternal) 'Internal',
                          if (showBaseline) 'Baseline',
                        ],
                        rows: labResults.map((row) {
                          final resultColumns = resultLabels.map(
                            (label) => getResultValue(row['id'], label),
                          ).toList();

                          return [
                            row['sampling_type']?.toString() ?? '-',
                            row['parameter_name']?.toString() ?? '-',
                            ...resultColumns,
                            row['unit']?.toString() ?? '-',
                            row['status']?.toString() ?? '-',
                            row['analyst_name']?.toString() ?? '-',
                            row['analysis_date']?.toString() ?? '-',
                            row['remarks']?.toString() ?? '-',
                            if (showDoe) row['doe_limit']?.toString() ?? '-',
                            if (showJkr) row['jkr_limit']?.toString() ?? '-',
                            if (showInternal) row['internal_limit']?.toString() ?? '-',
                            if (showBaseline) row['baseline_limit']?.toString() ?? '-',
                          ];
                        }).toList(),
                      ),
              ),
            if (isAdmin && labAnalysisAttachments.isNotEmpty) ...[
              const SizedBox(height: 20),
              buildLabAnalysisAttachmentsSection(),
            ],
            const SizedBox(height: 20),
            if (isAdmin)
              ElevatedButton.icon(
                onPressed: generatingPdf ? null : generatePdf,
                icon: generatingPdf
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.picture_as_pdf),
                label: Text(generatingPdf ? 'Generating PDF...' : 'Generate PDF'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
          ],
        ),
      ),
    );
  }
}