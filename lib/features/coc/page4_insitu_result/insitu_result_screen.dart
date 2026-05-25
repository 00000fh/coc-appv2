import 'package:flutter/material.dart';

import '../../../core/supabase_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/neumo_card.dart';
import '../../../shared/widgets/loading_skeleton.dart';
import '../../../shared/widgets/no_internet_state.dart';
import '../../../shared/utils/app_snackbar.dart';
import '../../../shared/utils/session_handler.dart';

import '../page5_lab_acknowledgement/lab_acknowledgement_screen.dart';

class InsituResultScreen extends StatefulWidget {
  final String recordId;
  final String batchNumber;

  const InsituResultScreen({
    super.key,
    required this.recordId,
    required this.batchNumber,
  });

  @override
  State<InsituResultScreen> createState() => _InsituResultScreenState();
}

class _InsituResultScreenState extends State<InsituResultScreen> {
  bool loading = true;
  bool saving = false;
  bool noInternet = false;
  bool hasWater = false;

  final List<String> defaultParameters = [
    'pH',
    'Temperature',
    'TSS',
    'DO',
    'Turbidity',
  ];

  final Map<String, String> fixedUnits = {
    'pH': '-',
    'Temperature': '°C',
    'TSS': 'mg/L',
    'DO': 'mg/L',
    'Turbidity': 'NTU',
  };

  final Map<String, TextEditingController> resultControllers = {};
  final Map<String, TextEditingController> statusControllers = {};
  final Map<String, TextEditingController> remarksControllers = {};
  final Map<String, TextEditingController> doeLimitControllers = {};
  final Map<String, TextEditingController> jkrLimitControllers = {};
  final Map<String, TextEditingController> internalLimitControllers = {};
  final Map<String, TextEditingController> baselineLimitControllers = {};

  @override
  void initState() {
    super.initState();
    preparePage();
  }

  Future<void> preparePage() async {
    setState(() {
      loading = true;
      noInternet = false;
    });

    await checkWaterSampling();
    await loadExistingResults();

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

    await preparePage();
  }

  Future<void> checkWaterSampling() async {
    try {
      final response = await supabase
          .from('selected_sampling_types')
          .select('sampling_type')
          .eq('coc_record_id', widget.recordId)
          .eq('sampling_type', 'Water');

      hasWater = response.isNotEmpty;
    } catch (e) {
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

      if (mounted) {
        AppSnackBar.error(context, 'Failed to check water sampling: ${e.toString().split(':').first}');
      }
    }
  }

  void createControllersForParameter(String parameter) {
    resultControllers[parameter] ??= TextEditingController();
    statusControllers[parameter] ??= TextEditingController();
    remarksControllers[parameter] ??= TextEditingController();
    doeLimitControllers[parameter] ??= TextEditingController();
    jkrLimitControllers[parameter] ??= TextEditingController();
    internalLimitControllers[parameter] ??= TextEditingController();
    baselineLimitControllers[parameter] ??= TextEditingController();
  }

  Future<void> loadExistingResults() async {
    for (final parameter in defaultParameters) {
      createControllersForParameter(parameter);
    }

    try {
      final response = await supabase
          .from('insitu_results')
          .select()
          .eq('coc_record_id', widget.recordId);

      for (final row in response) {
        final parameter = row['parameter_name'].toString();

        createControllersForParameter(parameter);

        resultControllers[parameter]!.text = row['result']?.toString() ?? '';
        statusControllers[parameter]!.text = row['status']?.toString() ?? '';
        remarksControllers[parameter]!.text = row['remarks']?.toString() ?? '';
        doeLimitControllers[parameter]!.text = row['doe_limit']?.toString() ?? '';
        jkrLimitControllers[parameter]!.text = row['jkr_limit']?.toString() ?? '';
        internalLimitControllers[parameter]!.text = row['internal_limit']?.toString() ?? '';
        baselineLimitControllers[parameter]!.text = row['baseline_limit']?.toString() ?? '';
      }
    } catch (e) {
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

      if (mounted) {
        AppSnackBar.error(context, 'Failed to load existing results: ${e.toString().split(':').first}');
      }
    }
  }

  Future<void> saveAndContinue() async {
    if (!hasWater) {
      // No water sampling, just navigate
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LabAcknowledgementScreen(
            recordId: widget.recordId,
            batchNumber: widget.batchNumber,
          ),
        ),
      );
      return;
    }

    setState(() => saving = true);

    try {
      for (final parameter in defaultParameters) {
        await supabase.from('insitu_results').upsert({
          'coc_record_id': widget.recordId,
          'parameter_name': parameter,
          'result': resultControllers[parameter]?.text.trim(),
          'unit': fixedUnits[parameter],
          'status': statusControllers[parameter]?.text.trim(),
          'remarks': remarksControllers[parameter]?.text.trim(),
          'doe_limit': doeLimitControllers[parameter]?.text.trim(),
          'jkr_limit': jkrLimitControllers[parameter]?.text.trim(),
          'internal_limit': internalLimitControllers[parameter]?.text.trim(),
          'baseline_limit': baselineLimitControllers[parameter]?.text.trim(),
        }, onConflict: 'coc_record_id,parameter_name');
      }

      if (!mounted) return;

      AppSnackBar.success(context, 'Insitu results saved successfully');

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LabAcknowledgementScreen(
            recordId: widget.recordId,
            batchNumber: widget.batchNumber,
          ),
        ),
      );
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

      AppSnackBar.error(context, 'Failed to save insitu result: ${e.toString().split(':').first}');
    }

    if (mounted) {
      setState(() => saving = false);
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
              Icons.water_drop,
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

  Widget buildParameterHeader(String parameter) {
    final unit = fixedUnits[parameter] ?? '-';

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.science,
            color: Colors.blue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            parameter,
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
            color: AppTheme.primary.withOpacity(0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppTheme.primary.withOpacity(0.35),
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
    );
  }

  final List<String> statusOptions = [
    'Comply',
    'Not Comply',
    'Pending Review',
    'Not Applicable',
  ];

  Widget buildInputField({
    required TextEditingController? controller,
    required String hint,
    required IconData icon,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(
            icon,
            color: AppTheme.primary,
          ),
        ),
      ),
    );
  }

  Widget buildResultCard(String parameter) {
    return NeumoCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildParameterHeader(parameter),
          const SizedBox(height: 16),
          buildInputField(
            controller: resultControllers[parameter],
            hint: 'Result',
            icon: Icons.edit_note,
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DropdownButtonFormField<String>(
              value: statusControllers[parameter]!.text.isEmpty
                  ? null
                  : statusControllers[parameter]!.text,
              decoration: const InputDecoration(
                hintText: 'Status',
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
                  statusControllers[parameter]!.text = value ?? '';
                });
              },
            ),
          ),
          buildInputField(
            controller: remarksControllers[parameter],
            hint: 'Remarks',
            icon: Icons.notes,
            maxLines: 2,
          ),
          const SizedBox(height: 4),
          Theme(
            data: Theme.of(context).copyWith(
              dividerColor: Colors.transparent,
            ),
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
                style: TextStyle(
                  color: AppTheme.textSoft,
                  fontSize: 12,
                ),
              ),
              children: [
                buildInputField(
                  controller: doeLimitControllers[parameter],
                  hint: 'DOE Limit',
                  icon: Icons.balance,
                ),
                buildInputField(
                  controller: jkrLimitControllers[parameter],
                  hint: 'JKR Limit',
                  icon: Icons.account_balance,
                ),
                buildInputField(
                  controller: internalLimitControllers[parameter],
                  hint: 'Internal Limit',
                  icon: Icons.business_center,
                ),
                buildInputField(
                  controller: baselineLimitControllers[parameter],
                  hint: 'Baseline Limit',
                  icon: Icons.stacked_line_chart,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildNoWaterCard() {
    return const NeumoCard(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Text(
          'Water sampling was not selected. Insitu result is usually required for Water only. You can proceed to the next page.',
          style: TextStyle(
            color: AppTheme.textSoft,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (final controller in [
      ...resultControllers.values,
      ...statusControllers.values,
      ...remarksControllers.values,
      ...doeLimitControllers.values,
      ...jkrLimitControllers.values,
      ...internalLimitControllers.values,
      ...baselineLimitControllers.values,
    ]) {
      controller.dispose();
    }

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
            'Insitu Result',
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
            'Insitu Result',
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
          'Insitu Result',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          buildBatchCard(),
          const SizedBox(height: 4),
          const Text(
            'Water Insitu Result',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Fill in result, status and remarks. Units are fixed based on parameter.',
            style: TextStyle(
              color: AppTheme.textSoft,
            ),
          ),
          const SizedBox(height: 16),
          if (!hasWater) buildNoWaterCard(),
          if (hasWater) ...defaultParameters.map(buildResultCard),
          const SizedBox(height: 14),
          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: saving ? null : saveAndContinue,
              child: Text(saving ? 'Saving...' : 'Next'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}