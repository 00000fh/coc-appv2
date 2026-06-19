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
  final bool readOnly;

  const InsituResultScreen({
    super.key,
    required this.recordId,
    required this.batchNumber,
    this.readOnly = false,
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

  // New structure: Each parameter can have multiple result rows
  final Map<String, List<Map<String, TextEditingController>>> resultRows = {};
  
  // Single value controllers per parameter
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
    initializeControllers();
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
          .eq('sampling_type', 'Water Quality');

      hasWater = response.isNotEmpty;
    } catch (e) {
      // Check for session errors
      if (SessionHandler.isSessionError(e)) {
        if (!mounted) return;
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
        AppSnackBar.error(
          context,
          'Failed to check water sampling: ${e.toString().split(':').first}',
        );
      }
    }
  }

  void initializeControllers() {
    for (final parameter in defaultParameters) {
      // Initialize result rows with one empty row
      resultRows[parameter] = [
        {
          'label': TextEditingController(),
          'value': TextEditingController(),
        },
      ];
      
      // Initialize other controllers
      statusControllers[parameter] ??= TextEditingController();
      remarksControllers[parameter] ??= TextEditingController();
      doeLimitControllers[parameter] ??= TextEditingController();
      jkrLimitControllers[parameter] ??= TextEditingController();
      internalLimitControllers[parameter] ??= TextEditingController();
      baselineLimitControllers[parameter] ??= TextEditingController();
    }
  }

  Future<void> loadExistingResults() async {
    try {
      final response = await supabase
          .from('insitu_results')
          .select()
          .eq('coc_record_id', widget.recordId);

      // First, get all result values
      final resultValues = await supabase
          .from('insitu_result_values')
          .select();

      for (final row in response) {
        final parameter = row['parameter_name'].toString();

        // Get values for this parameter
        final valuesForThisParameter = resultValues
            .where((valueRow) => valueRow['insitu_result_id'] == row['id'])
            .toList();

        // Clear existing rows and add from database
        resultRows[parameter] = [];
        
        if (valuesForThisParameter.isNotEmpty) {
          for (final valueRow in valuesForThisParameter) {
            resultRows[parameter]!.add({
              'label': TextEditingController(
                text: valueRow['result_label']?.toString() ?? '',
              ),
              'value': TextEditingController(
                text: valueRow['result_value']?.toString() ?? '',
              ),
            });
          }
        } else {
          // If no values, add one empty row
          resultRows[parameter] = [
            {
              'label': TextEditingController(),
              'value': TextEditingController(),
            },
          ];
        }

        // Load single value fields
        statusControllers[parameter]!.text = row['status']?.toString() ?? '';
        remarksControllers[parameter]!.text = row['remarks']?.toString() ?? '';
        doeLimitControllers[parameter]!.text =
            row['doe_limit']?.toString() ?? '';
        jkrLimitControllers[parameter]!.text =
            row['jkr_limit']?.toString() ?? '';
        internalLimitControllers[parameter]!.text =
            row['internal_limit']?.toString() ?? '';
        baselineLimitControllers[parameter]!.text =
            row['baseline_limit']?.toString() ?? '';
      }
    } catch (e) {
      // Check for session errors
      if (SessionHandler.isSessionError(e)) {
        if (!mounted) return;
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
        AppSnackBar.error(
          context,
          'Failed to load existing results: ${e.toString().split(':').first}',
        );
      }
    }
  }

  Future<void> saveAndContinue() async {
    if (widget.readOnly) return;
    
    if (!hasWater) {
      // No water sampling, just navigate
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LabAcknowledgementScreen(
            recordId: widget.recordId,
            batchNumber: widget.batchNumber,
            readOnly: widget.readOnly,
          ),
        ),
      );
      return;
    }

    setState(() => saving = true);

    try {
      for (final parameter in defaultParameters) {
        // First, upsert the main insitu result record
        final insituResult = await supabase
            .from('insitu_results')
            .upsert({
              'coc_record_id': widget.recordId,
              'parameter_name': parameter,
              'unit': fixedUnits[parameter],
              'status': statusControllers[parameter]?.text.trim(),
              'remarks': remarksControllers[parameter]?.text.trim(),
              'doe_limit': doeLimitControllers[parameter]?.text.trim(),
              'jkr_limit': jkrLimitControllers[parameter]?.text.trim(),
              'internal_limit': internalLimitControllers[parameter]?.text.trim(),
              'baseline_limit': baselineLimitControllers[parameter]?.text.trim(),
            }, onConflict: 'coc_record_id,parameter_name')
            .select()
            .single();

        final insituResultId = insituResult['id'];

        // Delete existing result values for this parameter
        await supabase
            .from('insitu_result_values')
            .delete()
            .eq('insitu_result_id', insituResultId);

        // Insert new result values
        final rows = resultRows[parameter] ?? [];
        
        for (final row in rows) {
          final label = (row['label'] as TextEditingController).text.trim();
          final value = (row['value'] as TextEditingController).text.trim();

          if (label.isEmpty || value.isEmpty) {
            continue;
          }

          await supabase.from('insitu_result_values').insert({
            'insitu_result_id': insituResultId,
            'result_label': label,
            'result_value': value,
          });
        }
      }

      if (!mounted) return;

      AppSnackBar.success(context, 'Insitu results saved successfully');

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LabAcknowledgementScreen(
            recordId: widget.recordId,
            batchNumber: widget.batchNumber,
            readOnly: widget.readOnly,
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

      AppSnackBar.error(
        context,
        'Failed to save insitu result: ${e.toString().split(':').first}',
      );
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
              color: AppTheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.water_drop, color: AppTheme.primary),
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

  Widget buildParameterHeader(String parameter) {
    final unit = fixedUnits[parameter] ?? '-';

    return Row(
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
            parameter,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.35)),
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

  Widget buildResultsSection(String parameter) {
    final rows = resultRows[parameter] ?? [];

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
                    readOnly: widget.readOnly,
                    decoration: const InputDecoration(
                      hintText: 'Label',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: row['value'],
                    readOnly: widget.readOnly,
                    decoration: const InputDecoration(
                      hintText: 'Value',
                    ),
                  ),
                ),
                if (!widget.readOnly)
                  IconButton(
                    onPressed: rows.length == 1
                        ? null
                        : () {
                            setState(() {
                              // Dispose controllers before removing
                              row['label']?.dispose();
                              row['value']?.dispose();
                              rows.removeAt(index);
                            });
                          },
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
          );
        }),

        if (!widget.readOnly)
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

  Widget buildResultCard(String parameter) {
    return NeumoCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildParameterHeader(parameter),
          const SizedBox(height: 16),
          
          // Multiple results section
          buildResultsSection(parameter),
          
          const SizedBox(height: 16),
          
          // Single value fields
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DropdownButtonFormField<String>(
              initialValue: statusControllers[parameter]!.text.isEmpty
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
              onChanged: widget.readOnly
                  ? null
                  : (value) {
                      setState(() {
                        statusControllers[parameter]!.text = value ?? '';
                      });
                    },
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: remarksControllers[parameter],
              readOnly: widget.readOnly,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'Remarks',
                prefixIcon: Icon(Icons.notes, color: AppTheme.primary),
              ),
            ),
          ),
          
          const SizedBox(height: 4),
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
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: doeLimitControllers[parameter],
                    readOnly: widget.readOnly,
                    decoration: const InputDecoration(
                      hintText: 'DOE Limit',
                      prefixIcon: Icon(Icons.balance, color: AppTheme.primary),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: jkrLimitControllers[parameter],
                    readOnly: widget.readOnly,
                    decoration: const InputDecoration(
                      hintText: 'JKR Limit',
                      prefixIcon: Icon(
                        Icons.account_balance,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: internalLimitControllers[parameter],
                    readOnly: widget.readOnly,
                    decoration: const InputDecoration(
                      hintText: 'Internal Limit',
                      prefixIcon: Icon(
                        Icons.business_center,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: baselineLimitControllers[parameter],
                    readOnly: widget.readOnly,
                    decoration: const InputDecoration(
                      hintText: 'Baseline Limit',
                      prefixIcon: Icon(
                        Icons.stacked_line_chart,
                        color: AppTheme.primary,
                      ),
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

  Widget buildNoWaterCard() {
    return const NeumoCard(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Text(
          'Water sampling was not selected. Insitu result is usually required for Water only. You can proceed to the next page.',
          style: TextStyle(color: AppTheme.textSoft),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Dispose all controllers
    for (final parameter in defaultParameters) {
      // Dispose result rows
      final rows = resultRows[parameter] ?? [];
      for (final row in rows) {
        row['label']?.dispose();
        row['value']?.dispose();
      }
      
      // Dispose single value controllers
      statusControllers[parameter]?.dispose();
      remarksControllers[parameter]?.dispose();
      doeLimitControllers[parameter]?.dispose();
      jkrLimitControllers[parameter]?.dispose();
      internalLimitControllers[parameter]?.dispose();
      baselineLimitControllers[parameter]?.dispose();
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
            'Insitu Result',
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
          'Insitu Result',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          buildBatchCard(),
          const SizedBox(height: 16),
          if (!hasWater) buildNoWaterCard(),
          if (hasWater) ...defaultParameters.map(buildResultCard),
          const SizedBox(height: 14),
          if (!widget.readOnly)
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