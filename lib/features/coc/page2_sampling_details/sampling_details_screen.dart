import 'package:flutter/material.dart';

import '../../../core/supabase_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/neumo_card.dart';
import '../../../shared/widgets/loading_skeleton.dart';
import '../../../shared/widgets/no_internet_state.dart';
import '../../../shared/utils/app_snackbar.dart';
import '../../../shared/utils/session_handler.dart';

import '../page3_attachments/attachment_overview_screen.dart';

class SamplingDetailsScreen extends StatefulWidget {
  final String recordId;
  final String batchNumber;

  const SamplingDetailsScreen({
    super.key,
    required this.recordId,
    required this.batchNumber,
  });

  @override
  State<SamplingDetailsScreen> createState() => _SamplingDetailsScreenState();
}

class _SamplingDetailsScreenState extends State<SamplingDetailsScreen> {
  bool loading = false;
  bool isLoading = true; // For initial loading skeleton
  bool noInternet = false;

  final Set<String> selectedTypes = {};
  final Map<String, Set<String>> selectedParameters = {};
  final Map<String, String?> selectedDurations = {};

  final Map<String, TextEditingController> customParameterControllers = {
    'Water': TextEditingController(),
    'Silt Trap': TextEditingController(),
  };

  final Map<String, List<String>> parametersByType = {
    'Water': [
      'pH',
      'Temperature',
      'Dissolved Oxygen (DO)',
      'Turbidity',
      'Total Suspended Solids',
      'BOD',
      'COD',
      'E-Coli',
      'Ammoniacal Nitrogen',
      'Oil and Grease',
      '31 Parameter',
    ],
    'Silt Trap': ['Turbidity', 'Total Suspended Solids'],
    'Ambient Air': ['TSP', 'PM10', 'PM2.5', 'SOx', 'NOx', 'CO', 'O3'],
    'Noise': ['Leq', 'Lmax', 'Lmin', 'L10', 'L90', 'L50'],
    'Vibration': ['PPV (mm/s)'],
  };

  final Map<String, List<String>> durationsByType = {
    'Ambient Air': ['12 hour', '24 hour'],
    'Noise': ['12 hour', '24 hour'],
    'Vibration': ['8 hour', '12 hour', '24 hour'],
  };

  @override
  void initState() {
    super.initState();

    for (final type in parametersByType.keys) {
      selectedParameters[type] = {};
    }

    // Simulate initial load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() => isLoading = false);
    });
  }

  void toggleParameter(String type, String parameter, bool selected) {
    setState(() {
      selectedParameters[type] ??= {};

      if (selected) {
        selectedParameters[type]!.add(parameter);
      } else {
        selectedParameters[type]!.remove(parameter);
      }
    });
  }

  void addCustomParameter(String type, StateSetter bottomSheetSetState) {
    final controller = customParameterControllers[type];

    if (controller == null) return;

    final customParameter = controller.text.trim();

    if (customParameter.isEmpty) {
      AppSnackBar.warning(context, 'Enter custom parameter name');
      return;
    }

    if (parametersByType[type]!.contains(customParameter)) {
      AppSnackBar.warning(context, 'Parameter already exists');
      return;
    }

    setState(() {
      parametersByType[type]!.add(customParameter);
      selectedParameters[type]!.add(customParameter);
      controller.clear();
    });

    bottomSheetSetState(() {});
    AppSnackBar.success(context, 'Custom parameter added');
  }

  Future<void> openParameterSheet(String type) async {
    if (!selectedTypes.contains(type)) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, bottomSheetSetState) {
            final parameters = parametersByType[type] ?? [];
            final selectedCount = selectedParameters[type]?.length ?? 0;

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.78,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: AppTheme.textSoft.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              type,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textDark,
                              ),
                            ),
                          ),
                          buildSmallCountChip('$selectedCount selected'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (durationsByType.containsKey(type))
                        Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: AppTheme.background,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0xFFC8D0D6),
                                offset: Offset(4, 4),
                                blurRadius: 10,
                              ),
                              BoxShadow(
                                color: Colors.white,
                                offset: Offset(-4, -4),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: DropdownButtonFormField<String>(
                            initialValue: selectedDurations[type],
                            decoration: const InputDecoration(
                              hintText: 'Select Duration',
                              border: InputBorder.none,
                            ),
                            items: durationsByType[type]!.map((duration) {
                              return DropdownMenuItem(
                                value: duration,
                                child: Text(duration),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                selectedDurations[type] = value;
                              });
                              bottomSheetSetState(() {});
                            },
                          ),
                        ),
                      if (type == 'Water' || type == 'Silt Trap')
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: customParameterControllers[type],
                                decoration: const InputDecoration(
                                  hintText: 'Add Custom Parameter',
                                  prefixIcon: Icon(Icons.add),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () =>
                                  addCustomParameter(type, bottomSheetSetState),
                              child: const Text('Add'),
                            ),
                          ],
                        ),
                      if (type == 'Water' || type == 'Silt Trap')
                        const SizedBox(height: 16),
                      const Text(
                        'Parameters',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ListView.builder(
                          itemCount: parameters.length,
                          itemBuilder: (context, index) {
                            final parameter = parameters[index];
                            final selected =
                                selectedParameters[type]?.contains(parameter) ??
                                false;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: selected
                                    ? getTypeColor(type).withValues(alpha: 0.10)
                                    : AppTheme.background,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: selected
                                      ? getTypeColor(type)
                                      : Colors.transparent,
                                ),
                              ),
                              child: CheckboxListTile(
                                dense: true,
                                value: selected,
                                activeColor: getTypeColor(type),
                                title: Text(parameter),
                                onChanged: (value) {
                                  toggleParameter(
                                    type,
                                    parameter,
                                    value ?? false,
                                  );
                                  bottomSheetSetState(() {});
                                },
                              ),
                            );
                          },
                        ),
                      ),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Done'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    setState(() {});
  }

  Future<void> saveAndContinue() async {
    if (selectedTypes.isEmpty) {
      AppSnackBar.warning(context, 'Please select at least one sampling type');
      return;
    }

    for (final type in selectedTypes) {
      if ((selectedParameters[type] ?? {}).isEmpty) {
        AppSnackBar.warning(context, 'Please select parameter for $type');
        return;
      }

      if (durationsByType.containsKey(type) &&
          selectedDurations[type] == null) {
        AppSnackBar.warning(context, 'Please select duration for $type');
        return;
      }
    }

    setState(() => loading = true);

    try {
      await supabase
          .from('selected_sampling_types')
          .delete()
          .eq('coc_record_id', widget.recordId);

      await supabase
          .from('selected_parameters')
          .delete()
          .eq('coc_record_id', widget.recordId);

      final samplingRows = selectedTypes.map((type) {
        return {
          'coc_record_id': widget.recordId,
          'sampling_type': type,
          'duration': selectedDurations[type],
        };
      }).toList();

      await supabase.from('selected_sampling_types').insert(samplingRows);

      final parameterRows = <Map<String, dynamic>>[];

      for (final type in selectedTypes) {
        for (final parameter in selectedParameters[type]!) {
          parameterRows.add({
            'coc_record_id': widget.recordId,
            'sampling_type': type,
            'parameter_name': parameter,
          });
        }
      }

      await supabase.from('selected_parameters').insert(parameterRows);

      if (!mounted) return;

      AppSnackBar.success(context, 'Sampling details saved successfully');

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AttachmentOverviewScreen(
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

      AppSnackBar.error(
        context,
        'Failed to save sampling details: ${e.toString().split(':').first}',
      );
    }

    if (mounted) {
      setState(() => loading = false);
    }
  }

  Future<void> retryAfterNoInternet() async {
    setState(() {
      noInternet = false;
      isLoading = true;
    });

    // Small delay to ensure connection check
    await Future.delayed(const Duration(milliseconds: 500));

    if (mounted) {
      setState(() => isLoading = false);
    }
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
        return Icons.science;
    }
  }

  Widget buildSmallCountChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppTheme.primary,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget buildSamplingTypeCard(String type) {
    final isSelected = selectedTypes.contains(type);
    final selectedCount = selectedParameters[type]?.length ?? 0;
    final duration = selectedDurations[type];
    final color = getTypeColor(type);

    return NeumoCard(
      padding: const EdgeInsets.all(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () async {
          if (!isSelected) {
            setState(() {
              selectedTypes.add(type);
              selectedParameters[type] ??= {};
            });
          }

          await openParameterSheet(type);

          final updatedCount = selectedParameters[type]?.length ?? 0;

          if (updatedCount == 0) {
            setState(() {
              selectedTypes.remove(type);
              selectedDurations.remove(type);
            });
          }
        },
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(getTypeIcon(type), color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    isSelected
                        ? '$selectedCount parameter(s) selected'
                              '${duration != null ? ' â€¢ $duration' : ''}'
                        : 'Tap to configure',
                    style: const TextStyle(
                      color: AppTheme.textSoft,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.arrow_forward_ios : Icons.add_circle_outline,
              color: isSelected ? AppTheme.primary : AppTheme.textSoft,
              size: 20,
            ),
          ],
        ),
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
            child: const Icon(Icons.qr_code_2, color: AppTheme.primary),
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

  @override
  void dispose() {
    for (final controller in customParameterControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final types = parametersByType.keys.toList();

    // Show loading skeleton
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: AppTheme.appBarColor,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'Sampling Details',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        body: const LoadingSkeleton(),
      );
    }

    // Show no internet state
    if (noInternet) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: AppTheme.appBarColor,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'Sampling Details',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        body: NoInternetState(onRetry: retryAfterNoInternet),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.appBarColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Sampling Details',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          buildBatchCard(),
          const SizedBox(height: 4),
          const Text(
            'Select Sampling Type',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tap each sampling type to choose parameters and duration.',
            style: TextStyle(color: AppTheme.textSoft),
          ),
          const SizedBox(height: 16),
          ...types.map(buildSamplingTypeCard),
          const SizedBox(height: 14),
          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: loading ? null : saveAndContinue,
              child: Text(loading ? 'Saving...' : 'Next'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
