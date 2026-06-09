import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

import '../../../core/supabase_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/neumo_card.dart';
import '../../../shared/widgets/loading_skeleton.dart';
import '../../../shared/widgets/no_internet_state.dart';
import '../../../shared/utils/app_snackbar.dart';
import '../../../shared/utils/session_handler.dart';

import '../../notifications/notification_service.dart';

class LabAcknowledgementScreen extends StatefulWidget {
  final String recordId;
  final String batchNumber;

  const LabAcknowledgementScreen({
    super.key,
    required this.recordId,
    required this.batchNumber,
  });

  @override
  State<LabAcknowledgementScreen> createState() =>
      _LabAcknowledgementScreenState();
}

class _LabAcknowledgementScreenState extends State<LabAcknowledgementScreen> {
  bool loading = true;
  bool submitting = false;
  bool noInternet = false;

  final clientNameController = TextEditingController();
  final labPicController = TextEditingController();
  final typedNameController = TextEditingController();

  final SignatureController signatureController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  List<Map<String, dynamic>> labs = [];
  String? selectedLabId;

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
      final record = await supabase
          .from('coc_records')
          .select('client_name')
          .eq('id', widget.recordId)
          .single();

      clientNameController.text = record['client_name']?.toString() ?? '';

      final labResponse = await supabase
          .from('labs')
          .select('id, lab_name, pic_name');

      labs = List<Map<String, dynamic>>.from(labResponse);
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
        'Failed to load page: ${e.toString().split(':').first}',
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

    await loadData();
  }

  Future<String?> uploadSignature() async {
    if (signatureController.isEmpty) return null;

    final Uint8List? signatureBytes = await signatureController.toPngBytes();

    if (signatureBytes == null) return null;

    final filePath =
        '${widget.recordId}/signature_${DateTime.now().millisecondsSinceEpoch}.png';

    await supabase.auth.refreshSession();

    await supabase.storage
        .from('signatures')
        .uploadBinary(filePath, signatureBytes);

    return filePath;
  }

  Future<void> submitToLab() async {
    if (selectedLabId == null ||
        labPicController.text.trim().isEmpty ||
        typedNameController.text.trim().isEmpty ||
        signatureController.isEmpty) {
      AppSnackBar.warning(
        context,
        'Please complete all required fields including signature',
      );
      return;
    }

    setState(() => submitting = true);

    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        throw Exception('User not logged in');
      }

      final signaturePath = await uploadSignature();

      await supabase.from('lab_acknowledgements').upsert({
        'coc_record_id': widget.recordId,
        'client_name': clientNameController.text.trim(),
        'lab_id': selectedLabId,
        'lab_pic': labPicController.text.trim(),
        'acknowledged_by': user.id,
        'typed_name': typedNameController.text.trim(),
        'signature_path': signaturePath,
      }, onConflict: 'coc_record_id');

      await supabase
          .from('coc_records')
          .update({
            'assigned_lab_id': selectedLabId,
            'status': 'submitted_to_lab',
          })
          .eq('id', widget.recordId);

      await NotificationService.notifyLab(
        labId: selectedLabId!,
        recordId: widget.recordId,
        title: 'New COC Assigned',
        message:
            'Batch ${widget.batchNumber} has been submitted for lab analysis.',
        type: 'new_assignment',
      );

      await NotificationService.notifyRole(
        role: 'admin',
        recordId: widget.recordId,
        title: 'COC Submitted to Lab',
        message: 'Batch ${widget.batchNumber} has been submitted to lab.',
        type: 'submitted_to_lab',
      );

      if (!mounted) return;

      AppSnackBar.success(context, 'Submitted to lab successfully');

      Navigator.popUntil(context, (route) => route.isFirst);
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
        'Submit failed: ${e.toString().split(':').first}',
      );
    }

    if (mounted) {
      setState(() => submitting = false);
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
              color: AppTheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.verified_user, color: AppTheme.primary),
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

  Widget buildInputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool readOnly = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, color: AppTheme.primary),
        ),
      ),
    );
  }

  Widget buildLabDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String>(
        initialValue: selectedLabId,
        decoration: const InputDecoration(
          hintText: 'Select Lab',
          prefixIcon: Icon(Icons.science, color: AppTheme.primary),
        ),
        items: labs.map((lab) {
          return DropdownMenuItem<String>(
            value: lab['id'].toString(),
            child: Text(lab['lab_name'].toString()),
          );
        }).toList(),
        onChanged: (value) {
          setState(() {
            selectedLabId = value;

            final selectedLab = labs.firstWhere(
              (lab) => lab['id'].toString() == value,
            );

            labPicController.text = selectedLab['pic_name']?.toString() ?? '';
          });
        },
      ),
    );
  }

  Widget buildSignaturePad() {
    return NeumoCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Digital Signature',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Draw signature inside the box below.',
            style: TextStyle(color: AppTheme.textSoft, fontSize: 12),
          ),
          const SizedBox(height: 14),
          Container(
            height: 190,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppTheme.primary.withValues(alpha: 0.25),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Signature(
                controller: signatureController,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: submitting
                  ? null
                  : () {
                      signatureController.clear();
                    },
              icon: const Icon(Icons.clear),
              label: const Text('Clear Signature'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    clientNameController.dispose();
    labPicController.dispose();
    typedNameController.dispose();
    signatureController.dispose();
    super.dispose();
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
            'Lab Acknowledgement',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        body: NoInternetState(onRetry: retryAfterNoInternet),
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
            'Lab Acknowledgement',
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
          'Lab Acknowledgement',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          buildBatchCard(),
          const SizedBox(height: 4),
          const Text(
            'Lab Acknowledgement',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Assign the selected record to a lab and confirm acknowledgement.',
            style: TextStyle(color: AppTheme.textSoft),
          ),
          const SizedBox(height: 16),
          NeumoCard(
            child: Column(
              children: [
                buildInputField(
                  controller: clientNameController,
                  hint: 'Client Name',
                  icon: Icons.business,
                  readOnly: true,
                ),
                buildLabDropdown(),
                buildInputField(
                  controller: labPicController,
                  hint: 'Lab PIC',
                  icon: Icons.person,
                ),
                buildInputField(
                  controller: typedNameController,
                  hint: 'Typed Name',
                  icon: Icons.edit,
                ),
              ],
            ),
          ),
          buildSignaturePad(),
          const SizedBox(height: 14),
          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: submitting ? null : submitToLab,
              child: Text(submitting ? 'Submitting...' : 'Submit to Lab'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
