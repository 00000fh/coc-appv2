import 'package:flutter/material.dart';

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

  final Map<String, TextEditingController> resultControllers = {};
  final Map<String, TextEditingController> remarksControllers = {};
  final Map<String, TextEditingController> doeLimitControllers = {};
  final Map<String, TextEditingController> jkrLimitControllers = {};
  final Map<String, TextEditingController> internalLimitControllers = {};
  final Map<String, TextEditingController> baselineLimitControllers = {};
  final Map<String, TextEditingController> analystControllers = {};
  final Map<String, DateTime> analysisDates = {};
  final Map<String, String?> statusValues = {};

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
          .update({
            'status': 'lab_in_progress',
          })
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

      debugPrint('Failed to mark lab analysis as started: $e');
    }
  }

  Future<void> loadParameters() async {
    try {
      final response = await supabase
          .from('selected_parameters')
          .select('sampling_type, parameter_name')
          .eq('coc_record_id', widget.recordId)
          .inFilter('sampling_type', ['Water', 'Silt Trap'])
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

        resultControllers[key] = TextEditingController();
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

      AppSnackBar.error(context, 'Failed to load parameters: ${e.toString().split(':').first}');
    }
  }

  Future<void> loadExistingResults() async {
    try {
      final response = await supabase
          .from('lab_analysis_results')
          .select()
          .eq('coc_record_id', widget.recordId);

      for (final row in response) {
        final samplingType = row['sampling_type'].toString();
        final parameterName = row['parameter_name'].toString();
        final key = keyFor(samplingType, parameterName);

        resultControllers[key]?.text = row['result']?.toString() ?? '';
        remarksControllers[key]?.text = row['remarks']?.toString() ?? '';
        doeLimitControllers[key]?.text = row['doe_limit']?.toString() ?? '';
        jkrLimitControllers[key]?.text = row['jkr_limit']?.toString() ?? '';
        internalLimitControllers[key]?.text = row['internal_limit']?.toString() ?? '';
        baselineLimitControllers[key]?.text = row['baseline_limit']?.toString() ?? '';
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

  bool canCompleteAnalysis() {
    for (final row in selectedParameters) {
      final samplingType = row['sampling_type'].toString();
      final parameterName = row['parameter_name'].toString();
      final key = keyFor(samplingType, parameterName);

      final result = resultControllers[key]?.text.trim() ?? '';
      final analyst = analystControllers[key]?.text.trim() ?? '';
      final status = statusValues[key];
      final remarks = remarksControllers[key]?.text.trim() ?? '';

      if (result.isEmpty ||
          analyst.isEmpty ||
          status == null ||
          remarks.isEmpty) {
        return false;
      }
    }

    return true;
  }

  Future<void> saveAnalysis({
    required bool complete,
  }) async {
    setState(() => saving = true);

    try {
      for (final row in selectedParameters) {
        final samplingType = row['sampling_type'].toString();
        final parameterName = row['parameter_name'].toString();
        final key = keyFor(samplingType, parameterName);

        await supabase.from('lab_analysis_results').upsert({
          'coc_record_id': widget.recordId,
          'sampling_type': samplingType,
          'parameter_name': parameterName,
          'result': resultControllers[key]?.text.trim(),
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
        }, onConflict: 'coc_record_id,sampling_type,parameter_name');
      }

      await supabase
          .from('coc_records')
          .update({
            'status': complete ? 'lab_completed' : 'lab_in_progress',
          })
          .eq('id', widget.recordId);

      if (complete) {
        await NotificationService.notifyRole(
          role: 'admin',
          recordId: widget.recordId,
          title: 'Lab Analysis Completed',
          message: 'Batch ${widget.batchNumber} lab analysis has been completed.',
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

      AppSnackBar.error(context, 'Save failed: ${e.toString().split(':').first}');
    }

    if (mounted) {
      setState(() => saving = false);
    }
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
          ),
          const SizedBox(height: 16),
          TextField(
            controller: resultControllers[key],
            decoration: const InputDecoration(
              hintText: 'Result *',
              prefixIcon: Icon(
                Icons.edit_note,
                color: AppTheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: analystControllers[key],
            decoration: const InputDecoration(
              hintText: 'Analyst Name *',
              prefixIcon: Icon(
                Icons.person,
                color: AppTheme.primary,
              ),
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
                prefixIcon: Icon(
                  Icons.calendar_month,
                  color: AppTheme.primary,
                ),
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
            value: statusValues[key],
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
              prefixIcon: Icon(
                Icons.notes,
                color: AppTheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 6),
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
                TextField(
                  controller: doeLimitControllers[key],
                  decoration: const InputDecoration(
                    hintText: 'DOE Limit',
                    prefixIcon: Icon(
                      Icons.balance,
                      color: AppTheme.primary,
                    ),
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
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
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
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              child: Column(
                children: rows.map(buildParameterCard).toList(),
              ),
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
              color: AppTheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.science,
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

  @override
  void dispose() {
    for (final controller in [
      ...resultControllers.values,
      ...remarksControllers.values,
      ...doeLimitControllers.values,
      ...jkrLimitControllers.values,
      ...internalLimitControllers.values,
      ...baselineLimitControllers.values,
      ...analystControllers.values,
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
            'Lab Analysis',
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
            'Lab Analysis',
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
          'Lab Analysis',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            const Text(
              'Lab Analysis',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            buildBatchCard(),
            const SizedBox(height: 14),
            const SizedBox(height: 20),
            ...groupedParameters.keys.map(buildSamplingSection),
            const SizedBox(height: 20),
            NeumoCard(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: saving
                                ? null
                                : () => saveAnalysis(
                                      complete: false,
                                    ),
                            icon: const Icon(Icons.save),
                            label: Text(
                              saving ? 'Saving...' : 'Save',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed:
                                saving || !canCompleteAnalysis()
                                    ? null
                                    : () => saveAnalysis(
                                          complete: true,
                                        ),
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
                      style: TextStyle(
                        color: AppTheme.textSoft,
                        fontSize: 12,
                      ),
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