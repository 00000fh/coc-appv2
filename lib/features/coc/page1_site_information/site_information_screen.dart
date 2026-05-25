import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/supabase_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/neumo_card.dart';
import '../../../shared/widgets/loading_skeleton.dart';
import '../../../shared/widgets/no_internet_state.dart';
import '../../../shared/utils/app_snackbar.dart';
import '../../../shared/utils/session_handler.dart';
import '../page2_sampling_details/sampling_details_screen.dart';

class SiteInformationScreen extends StatefulWidget {
  final Map<String, dynamic>? existingRecord;

  const SiteInformationScreen({
    super.key,
    this.existingRecord,
  });

  @override
  State<SiteInformationScreen> createState() =>
      _SiteInformationScreenState();
}

class _SiteInformationScreenState extends State<SiteInformationScreen> {
  final projectNameController = TextEditingController();
  final clientNameController = TextEditingController();
  final locationController = TextEditingController();

  DateTime selectedDate = DateTime.now();

  String? recordId;
  String? batchNumber;
  String? previewBatchNumber;

  double? latitude;
  double? longitude;

  bool loading = false;
  bool gettingGps = false;
  bool noInternet = false;
  bool isLoading = true; // For initial loading skeleton

  @override
  void initState() {
    super.initState();
    generatePreviewBatchNumber();
    
    // Simulate initial load or load existing record
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.existingRecord != null) {
        loadExistingRecord();
      }
      setState(() => isLoading = false);
    });
  }

  void loadExistingRecord() {
    final record = widget.existingRecord!;

    recordId = record['id']?.toString();
    batchNumber = record['batch_number']?.toString();

    projectNameController.text = record['project_name'] ?? '';
    clientNameController.text = record['client_name'] ?? '';
    locationController.text = record['location'] ?? '';

    latitude = record['latitude'];
    longitude = record['longitude'];

    final monitoringDate = record['monitoring_date'];
    if (monitoringDate != null) {
      selectedDate = DateTime.parse(monitoringDate);
    }
  }

  void generatePreviewBatchNumber() {
    final now = DateTime.now();
    final monthNames = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'
    ];
    final month = monthNames[now.month - 1];
    previewBatchNumber = 'ELTS/MON/$month/XXXX';
  }

  Future<void> getGpsLocation() async {
    setState(() => gettingGps = true);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location service is disabled');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Location permission denied');
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        latitude = position.latitude;
        longitude = position.longitude;
      });
      
      AppSnackBar.success(context, 'GPS coordinates captured successfully');
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
      
      AppSnackBar.error(context, 'GPS failed: ${e.toString().split(':').first}');
    }

    if (mounted) {
      setState(() => gettingGps = false);
    }
  }

  Future<void> retryAfterNoInternet() async {
    setState(() {
      noInternet = false;
      isLoading = true;
    });
    
    // Small delay to ensure connection check
    await Future.delayed(const Duration(milliseconds: 500));
    
    if (widget.existingRecord != null) {
      loadExistingRecord();
    }
    
    if (mounted) {
      setState(() => isLoading = false);
    }
  }

  Future<void> nextPage() async {
    if (projectNameController.text.trim().isEmpty ||
        clientNameController.text.trim().isEmpty ||
        locationController.text.trim().isEmpty) {
      AppSnackBar.warning(context, 'Please fill in all required fields');
      return;
    }

    setState(() => loading = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        throw Exception('User not logged in');
      }

      if (recordId == null) {
        final newBatchNumber = await supabase.rpc('generate_batch_number');
        final inserted = await supabase
            .from('coc_records')
            .insert({
              'batch_number': newBatchNumber.toString(),
              'project_name': projectNameController.text.trim(),
              'client_name': clientNameController.text.trim(),
              'monitoring_date': selectedDate.toIso8601String().split('T').first,
              'location': locationController.text.trim(),
              'latitude': latitude,
              'longitude': longitude,
              'created_by': user.id,
              'status': 'draft',
            })
            .select('id, batch_number')
            .single();

        recordId = inserted['id'].toString();
        batchNumber = inserted['batch_number'].toString();
      } else {
        await supabase.from('coc_records').update({
          'project_name': projectNameController.text.trim(),
          'client_name': clientNameController.text.trim(),
          'monitoring_date': selectedDate.toIso8601String().split('T').first,
          'location': locationController.text.trim(),
          'latitude': latitude,
          'longitude': longitude,
        }).eq('id', recordId!);
      }

      if (!mounted) return;
      
      AppSnackBar.success(context, 'Site information saved successfully');

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SamplingDetailsScreen(
            recordId: recordId!,
            batchNumber: batchNumber!,
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
      
      AppSnackBar.error(context, 'Failed to continue: ${e.toString().split(':').first}');
    }

    if (mounted) {
      setState(() => loading = false);
    }
  }

  Future<void> pickDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (pickedDate != null) {
      setState(() {
        selectedDate = pickedDate;
      });
    }
  }

  Widget buildInputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, color: AppTheme.primary),
        ),
      ),
    );
  }

  Widget buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppTheme.textDark,
        ),
      ),
    );
  }

  @override
  void dispose() {
    projectNameController.dispose();
    clientNameController.dispose();
    locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Show loading skeleton
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: AppTheme.appBarColor,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'Site Information',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
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
            'Site Information',
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

    final formattedDate =
        '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}';
    final coordinateText = latitude == null || longitude == null
        ? 'No coordinate captured'
        : '$latitude, $longitude';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.appBarColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Site Information',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          NeumoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3EBF0),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.white,
                        offset: Offset(-4, -4),
                        blurRadius: 8,
                      ),
                      BoxShadow(
                        color: Color(0xFFC3CED6),
                        offset: Offset(4, 4),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'BATCH NUMBER',
                        style: TextStyle(
                          fontSize: 12,
                          letterSpacing: 1.2,
                          color: AppTheme.textSoft,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        batchNumber ?? previewBatchNumber ?? 'PREPARING...',
                        style: GoogleFonts.audiowide(
                          fontSize: 22,
                          color: AppTheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          NeumoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                buildSectionTitle('Project Details'),
                buildInputField(
                  controller: projectNameController,
                  hint: 'Project Name',
                  icon: Icons.business,
                ),
                buildInputField(
                  controller: clientNameController,
                  hint: 'Client Name',
                  icon: Icons.person,
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: pickDate,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      hintText: 'Monitoring Date',
                      prefixIcon: const Icon(
                        Icons.calendar_month,
                        color: AppTheme.primary,
                      ),
                    ),
                    child: Text(formattedDate),
                  ),
                ),
                const SizedBox(height: 16),
                buildInputField(
                  controller: locationController,
                  hint: 'Location',
                  icon: Icons.location_on,
                ),
              ],
            ),
          ),
          NeumoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                buildSectionTitle('GPS Coordinate'),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3EBF0),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.white,
                        offset: Offset(-4, -4),
                        blurRadius: 8,
                      ),
                      BoxShadow(
                        color: Color(0xFFC3CED6),
                        offset: Offset(4, 4),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          coordinateText,
                          style: const TextStyle(
                            color: AppTheme.textDark,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: gettingGps ? null : getGpsLocation,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.primary,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              gettingGps ? Icons.sync : Icons.gps_fixed,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: loading ? null : nextPage,
              child: Text(loading ? 'Saving...' : 'Next'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}