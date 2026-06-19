import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/supabase_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/neumo_card.dart';
import '../../../shared/widgets/loading_skeleton.dart';
import '../../../shared/widgets/no_internet_state.dart';
import '../../../shared/utils/app_snackbar.dart';
import '../../../shared/utils/session_handler.dart';

class AttachmentTypeScreen extends StatefulWidget {
  final String recordId;
  final String batchNumber;
  final String samplingType;
  final bool readOnly;

  const AttachmentTypeScreen({
    super.key,
    required this.recordId,
    required this.batchNumber,
    required this.samplingType,
    this.readOnly = false,
  });

  @override
  State<AttachmentTypeScreen> createState() => _AttachmentTypeScreenState();
}

class _AttachmentTypeScreenState extends State<AttachmentTypeScreen> {
  bool loading = true;
  bool uploading = false;
  bool noInternet = false;

  // Failed upload tracking
  File? lastFailedFile;
  String? lastFailedFileName;
  String? lastFailedImageType;

  final ImagePicker imagePicker = ImagePicker();

  List<Map<String, dynamic>> images = [];
  final Map<String, TextEditingController> noteControllers = {};
  final Map<String, Timer> debounceTimers = {};
  final Set<String> savingNotes = {};

  @override
  void initState() {
    super.initState();
    loadImages();
  }

  Future<void> loadImages() async {
    setState(() {
      loading = true;
      noInternet = false;
    });

    try {
      final response = await supabase
          .from('attachments')
          .select()
          .eq('coc_record_id', widget.recordId)
          .eq('sampling_type', widget.samplingType)
          .order('created_at');

      images = List<Map<String, dynamic>>.from(response);

      for (final controller in noteControllers.values) {
        controller.dispose();
      }

      noteControllers.clear();

      for (final image in images) {
        final id = image['id'].toString();

        noteControllers[id] = TextEditingController(
          text: image['notes']?.toString() ?? '',
        );
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

      AppSnackBar.error(
        context,
        'Failed to load images: ${e.toString().split(':').first}',
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

    await loadImages();
  }

  Future<void> chooseImageSource() async {
    if (widget.readOnly) return;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppTheme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: AppTheme.textSoft.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Add Attachment',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.camera_alt,
                    color: AppTheme.primary,
                  ),
                  title: const Text('Take Photo'),
                  subtitle: const Text('Capture one image using camera'),
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.photo_library,
                    color: AppTheme.primary,
                  ),
                  title: const Text('Choose from Gallery'),
                  subtitle: const Text('Select multiple images'),
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (source == null) return;

    if (source == ImageSource.camera) {
      final pickedImage = await imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
      );

      if (pickedImage == null) return;

      await uploadImage(
        imageFile: File(pickedImage.path),
        fileName: pickedImage.name,
        imageType: 'camera_image',
      );

      return;
    }

    final remainingSlots = 15 - images.length;

    if (remainingSlots <= 0) {
      if (!mounted) return;
      AppSnackBar.warning(context, 'Maximum 15 images allowed');
      return;
    }

    final pickedImages = await imagePicker.pickMultiImage(imageQuality: 80);

    if (pickedImages.isEmpty) return;

    final limitedImages = pickedImages.take(remainingSlots).toList();

    if (pickedImages.length > remainingSlots) {
      if (!mounted) return;
      AppSnackBar.warning(
        context,
        'Only $remainingSlots image(s) added because maximum is 15.',
      );
    }

    for (final image in limitedImages) {
      await uploadImage(
        imageFile: File(image.path),
        fileName: image.name,
        imageType: 'gallery_image',
      );
    }
  }

  Future<void> uploadImage({
    required File imageFile,
    required String fileName,
    required String imageType,
  }) async {
    if (widget.readOnly) return;
    
    if (images.length >= 15) {
      AppSnackBar.warning(context, 'Maximum 15 images allowed');
      return;
    }

    setState(() => uploading = true);

    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        throw Exception('User not logged in');
      }

      final safeType = widget.samplingType.replaceAll(' ', '_');
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      final storagePath = '${widget.recordId}/$safeType/${timestamp}_$fileName';

      await supabase.auth.refreshSession();

      await supabase.storage
          .from('coc-attachments')
          .upload(storagePath, imageFile);

      final inserted = await supabase
          .from('attachments')
          .insert({
            'coc_record_id': widget.recordId,
            'sampling_type': widget.samplingType,
            'file_name': fileName,
            'file_path': storagePath,
            'file_type': imageType,
            'notes': '',
            'uploaded_by': user.id,
          })
          .select()
          .single();

      images.add(inserted);

      final id = inserted['id'].toString();
      noteControllers[id] = TextEditingController();

      // Clear failed upload data on success
      lastFailedFile = null;
      lastFailedFileName = null;
      lastFailedImageType = null;

      if (!mounted) return;
      AppSnackBar.success(context, 'Image uploaded successfully');

      setState(() {});
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

      // Store failed upload data
      lastFailedFile = imageFile;
      lastFailedFileName = fileName;
      lastFailedImageType = imageType;

      if (mounted) {
        AppSnackBar.error(context, 'Upload failed. You can retry.');
      }
    }

    if (mounted) {
      setState(() => uploading = false);
    }
  }

  void scheduleNoteAutoSave(String imageId) {
    if (widget.readOnly) return;
    
    debounceTimers[imageId]?.cancel();

    debounceTimers[imageId] = Timer(
      const Duration(milliseconds: 800),
      () => autoSaveNote(imageId),
    );
  }

  Future<void> autoSaveNote(String imageId) async {
    if (widget.readOnly) return;
    
    final controller = noteControllers[imageId];

    if (controller == null) return;

    savingNotes.add(imageId);

    if (mounted) {
      setState(() {});
    }

    try {
      await supabase
          .from('attachments')
          .update({'notes': controller.text.trim()})
          .eq('id', imageId);
    } catch (e) {
      debugPrint('Auto save failed: $e');
    }

    savingNotes.remove(imageId);

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> deleteImage(Map<String, dynamic> image) async {
    if (widget.readOnly) return;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Attachment?'),
          content: const Text(
            'This image and its note will be removed permanently.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    final imageId = image['id'].toString();
    final filePath = image['file_path'].toString();

    try {
      await supabase.storage.from('coc-attachments').remove([filePath]);

      await supabase.from('attachments').delete().eq('id', imageId);

      images.removeWhere((item) => item['id'].toString() == imageId);

      debounceTimers[imageId]?.cancel();
      debounceTimers.remove(imageId);

      noteControllers[imageId]?.dispose();
      noteControllers.remove(imageId);

      if (!mounted) return;
      AppSnackBar.success(context, 'Image deleted successfully');

      setState(() {});
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

      if (!mounted) return;
      AppSnackBar.error(
        context,
        'Delete failed: ${e.toString().split(':').first}',
      );
    }
  }

  Color getSamplingColor() {
    switch (widget.samplingType) {
      case 'Water Quality':
        return Colors.blue;
      case 'Silt Trap':
        return Colors.brown;
      case 'Ambient Air':
        return Colors.teal;
      case 'Boundary Noise':
        return Colors.deepPurple;
      case 'Vibration':
        return Colors.orange;
      default:
        return AppTheme.primary;
    }
  }

  IconData getSamplingIcon() {
    switch (widget.samplingType) {
      case 'Water Quality':
        return Icons.water_drop;
      case 'Silt Trap':
        return Icons.landscape;
      case 'Ambient Air':
        return Icons.air;
      case 'Boundary Noise':
        return Icons.volume_up;
      case 'Vibration':
        return Icons.graphic_eq;
      default:
        return Icons.image;
    }
  }

  Widget buildReadOnlyBanner() {
    if (!widget.readOnly) return const SizedBox.shrink();
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: const Row(
        children: [
          Icon(Icons.visibility, color: Colors.blue),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'This record has been submitted. Attachments can be viewed but not modified.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildHeaderCard() {
    final color = getSamplingColor();

    return NeumoCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(getSamplingIcon(), color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.samplingType,
                  style: const TextStyle(
                    color: AppTheme.textDark,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.batchNumber,
                  style: const TextStyle(
                    color: AppTheme.textSoft,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: 0.55)),
            ),
            child: Text(
              '${images.length}/15',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildUploadButton() {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: uploading ? null : chooseImageSource,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
              decoration: BoxDecoration(
                color: const Color(0xFF314A5A),
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0xFFD5DDE3),
                    offset: Offset(5, 5),
                    blurRadius: 12,
                  ),
                  BoxShadow(
                    color: Colors.white,
                    offset: Offset(-5, -5),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    uploading ? Icons.sync : Icons.add_photo_alternate,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    uploading ? 'Uploading...' : 'Add Attachment',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Retry button - shown when there's a failed upload
        if (!widget.readOnly && lastFailedFile != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: OutlinedButton.icon(
              onPressed: uploading
                  ? null
                  : () {
                      uploadImage(
                        imageFile: lastFailedFile!,
                        fileName: lastFailedFileName!,
                        imageType: lastFailedImageType!,
                      );
                    },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry Last Upload'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange,
                side: const BorderSide(color: Colors.orange),
              ),
            ),
          ),
      ],
    );
  }

  Widget buildImageCard(Map<String, dynamic> image) {
    final imageId = image['id'].toString();
    final controller = noteControllers[imageId];
    final isSaving = savingNotes.contains(imageId);

    return NeumoCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: getSamplingColor().withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  image['file_type'] == 'camera_image'
                      ? Icons.camera_alt
                      : Icons.photo,
                  color: getSamplingColor(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      image['file_name'].toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textDark,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      image['file_type'].toString(),
                      style: const TextStyle(
                        color: AppTheme.textSoft,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (!widget.readOnly)
                IconButton(
                  onPressed: () => deleteImage(image),
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            maxLines: 2,
            readOnly: widget.readOnly,
            onChanged: widget.readOnly
                ? null
                : (_) => scheduleNoteAutoSave(imageId),
            decoration: InputDecoration(
              hintText: 'Note for this image',
              suffixIcon: isSaving && !widget.readOnly
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildEmptyState() {
    return NeumoCard(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            widget.readOnly
                ? 'No images attached.'
                : 'No images attached yet.\nTap Add Attachment to begin.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textSoft),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (final timer in debounceTimers.values) {
      timer.cancel();
    }

    for (final controller in noteControllers.values) {
      controller.dispose();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = getSamplingColor();

    // Show no internet state
    if (noInternet) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: AppTheme.appBarColor,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(
            widget.samplingType,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
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
        title: Text(
          widget.samplingType,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: loadImages,
        child: loading
            ? const LoadingSkeleton()
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  buildReadOnlyBanner(),
                  buildHeaderCard(),
                  LinearProgressIndicator(
                    value: images.length / 15,
                    minHeight: 5,
                    backgroundColor: color.withValues(alpha: 0.12),
                    color: color,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  const SizedBox(height: 18),
                  if (!widget.readOnly) buildUploadButton(),
                  const SizedBox(height: 18),
                  if (images.isEmpty) buildEmptyState(),
                  ...images.map(buildImageCard),
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }
}