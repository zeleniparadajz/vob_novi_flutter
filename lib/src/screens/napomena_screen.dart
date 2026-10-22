import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../data/demo_repository.dart';
import '../core/app_logger.dart';
import '../core/note_photo_processor.dart';
import '../models/vodovod_models.dart';

class NapomenaScreen extends StatefulWidget {
  const NapomenaScreen({
    super.key,
    required this.repository,
    required this.ocitavanje,
    this.quickMode = false,
    this.autoOpenCamera = false,
  });

  final DemoVodovodRepository repository;
  final OcitavanjeModel ocitavanje;
  final bool quickMode;
  final bool autoOpenCamera;

  @override
  State<NapomenaScreen> createState() => _NapomenaScreenState();
}

class _NapomenaScreenState extends State<NapomenaScreen> {
  final noteController = TextEditingController();
  final profilController = TextEditingController();
  final picker = ImagePicker();
  File? selectedImage;
  bool isProcessingImage = false;
  bool isSaving = false;
  bool didAutoOpenCamera = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoOpenCamera) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || didAutoOpenCamera) return;
        didAutoOpenCamera = true;
        pickImage(ImageSource.camera);
      });
    }
  }

  @override
  void dispose() {
    noteController.dispose();
    profilController.dispose();
    super.dispose();
  }

  Future<void> pickImage(ImageSource source) async {
    if (isProcessingImage || isSaving) return;
    setState(() => isProcessingImage = true);
    try {
      final picked = await picker.pickImage(
        source: source,
        maxWidth: notePhotoMaxDimension.toDouble(),
        maxHeight: notePhotoMaxDimension.toDouble(),
        imageQuality: 100,
      );
      if (!mounted) return;
      if (picked == null) {
        if (widget.quickMode && widget.autoOpenCamera) {
          Navigator.of(context).pop();
        }
        return;
      }
      final processed = await _processImage(File(picked.path));
      if (!mounted) return;
      setState(() => selectedImage = processed);
      if (widget.quickMode) {
        await save(isZamjena: false);
      }
    } catch (error, stack) {
      unawaited(
        AppLogger.error(
          'Obrada slike za očitavanje ${widget.ocitavanje.id}',
          error,
          stack,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Greška pri obradi slike: $error')),
      );
    } finally {
      if (mounted) setState(() => isProcessingImage = false);
    }
  }

  Future<File> _processImage(File file) async {
    final currentDate = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
    final text = 'Vodomjer: ${widget.ocitavanje.vodomjer} | $currentDate';
    final dir = await getTemporaryDirectory();
    final safeMeter = widget.ocitavanje.vodomjer.replaceAll('/', '-');
    final safeCustomer = widget.ocitavanje.idpot.replaceAll('/', '-');
    final stopwatch = Stopwatch()..start();
    final path = await prepareNotePhoto(
      sourcePath: file.path,
      outputPath:
          '${dir.path}/slika_IDMM_${safeMeter}_IDPOT_${safeCustomer}_r_${DateTime.now().microsecondsSinceEpoch}.jpg',
      label: text,
    );
    unawaited(
      AppLogger.log(
        'Obrada slike za očitavanje ${widget.ocitavanje.id}: ${stopwatch.elapsedMilliseconds} ms',
      ),
    );
    return File(path);
  }

  Future<void> save({required bool isZamjena}) async {
    if (isSaving) return;
    if (selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dodaj sliku sa kamere ili iz galerije.')),
      );
      return;
    }

    setState(() => isSaving = true);
    try {
      await widget.repository.sacuvajNapomenu(
        NapomenaDraft(
          localId: DateTime.now().microsecondsSinceEpoch,
          vodomjer: widget.ocitavanje.vodomjer,
          idpot: widget.ocitavanje.idpot,
          imepot: widget.ocitavanje.potrosac,
          inkId: widget.ocitavanje.idink,
          napomena: noteController.text.trim().isEmpty
              ? 'nema napomene'
              : noteController.text.trim(),
          isPrijava: isZamjena,
          profil: profilController.text.trim().isEmpty
              ? 'nema_profila'
              : profilController.text.trim(),
          slikaPath: selectedImage!.path,
        ),
      );
    } catch (error, stack) {
      unawaited(
        AppLogger.error(
          'Čuvanje napomene za očitavanje ${widget.ocitavanje.id}',
          error,
          stack,
        ),
      );
      if (mounted) {
        setState(() => isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Napomena nije sačuvana. Pokušajte ponovo.'),
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isZamjena
              ? 'Zamjena je snimljena lokalno za sinhronizaciju.'
              : 'Napomena je snimljena lokalno za sinhronizaciju.',
        ),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.ocitavanje;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.quickMode ? 'Brzo slikanje' : 'Napomena'),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: isProcessingImage || isSaving
                      ? null
                      : () => save(isZamjena: false),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Potvrdi napomenu'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: isProcessingImage || isSaving
                      ? null
                      : () => save(isZamjena: true),
                  icon: const Icon(Icons.swap_horiz_outlined),
                  label: const Text('Potvrdi zamjenu'),
                ),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.potrosac,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _MiniInfo(text: item.idpot, icon: Icons.person_outline),
                      _MiniInfo(
                        text: item.vodomjer,
                        icon: Icons.water_drop_outlined,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _ImagePickerBox(
            image: selectedImage,
            isProcessing: isProcessingImage || isSaving,
            onCamera: () => pickImage(ImageSource.camera),
            onGallery: () => pickImage(ImageSource.gallery),
          ),
          if (!widget.quickMode) ...[
            const SizedBox(height: 16),
            TextField(
              controller: noteController,
              minLines: 5,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Tekst napomene',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: profilController,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Profil',
                prefixIcon: Icon(Icons.edit_note_outlined),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ImagePickerBox extends StatelessWidget {
  const _ImagePickerBox({
    required this.image,
    required this.isProcessing,
    required this.onCamera,
    required this.onGallery,
  });

  final File? image;
  final bool isProcessing;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
              ),
              child: image == null || isProcessing
                  ? Center(
                      child: isProcessing
                          ? const CircularProgressIndicator()
                          : Icon(
                              Icons.add_a_photo_outlined,
                              size: 42,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                    )
                  : ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(8),
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) => Image.file(
                          image!,
                          fit: BoxFit.contain,
                          cacheWidth:
                              (constraints.maxWidth *
                                      MediaQuery.devicePixelRatioOf(context))
                                  .ceil()
                                  .clamp(1, 1280),
                          errorBuilder: (_, error, stack) {
                            AppLogger.imageError(image!.path, error, stack);
                            return const Center(
                              child: Icon(Icons.broken_image_outlined),
                            );
                          },
                        ),
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isProcessing ? null : onCamera,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Kamera'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isProcessing ? null : onGallery,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Galerija'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniInfo extends StatelessWidget {
  const _MiniInfo({required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: 5),
        Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
