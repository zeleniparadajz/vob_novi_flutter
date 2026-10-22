import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/demo_repository.dart';
import '../core/app_logger.dart';
import '../models/vodovod_models.dart';

class PotrosacNapomeneScreen extends StatefulWidget {
  const PotrosacNapomeneScreen({
    super.key,
    required this.repository,
    required this.idpot,
    required this.potrosac,
  });

  final DemoVodovodRepository repository;
  final String idpot;
  final String potrosac;

  @override
  State<PotrosacNapomeneScreen> createState() => _PotrosacNapomeneScreenState();
}

class _PotrosacNapomeneScreenState extends State<PotrosacNapomeneScreen> {
  late final Future<List<BackendNapomenaModel>> notesFuture;

  @override
  void initState() {
    super.initState();
    notesFuture = _loadNotes();
  }

  Future<List<BackendNapomenaModel>> _loadNotes() async {
    try {
      return await widget.repository.napomeneZaPotrosaca(widget.idpot);
    } catch (error, stack) {
      unawaited(
        AppLogger.error(
          'Pregled napomena za potrošača ${widget.idpot}',
          error,
          stack,
        ),
      );
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Napomene')),
      body: FutureBuilder<List<BackendNapomenaModel>>(
        future: notesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          final notes = snapshot.data ?? [];
          if (notes.isEmpty) {
            return const Center(child: Text('Nema napomena za potrošača.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: notes.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              if (index == 0) {
                return _Header(idpot: widget.idpot, potrosac: widget.potrosac);
              }
              return _BackendNoteCard(note: notes[index - 1]);
            },
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.idpot, required this.potrosac});

  final String idpot;
  final String potrosac;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.person_outline, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$potrosac\n$idpot',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackendNoteCard extends StatelessWidget {
  const _BackendNoteCard({required this.note});

  final BackendNapomenaModel note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateText = note.datum == null
        ? 'Datum nije upisan'
        : DateFormat('dd.MM.yyyy HH:mm').format(note.datum!.toLocal());
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (note.imageUrl.trim().isNotEmpty)
            InkWell(
              onTap: () => _openImage(context, note.imageUrl),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(note.imageUrl, fit: BoxFit.contain),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        note.isPrijava ? 'Zamjena' : 'Napomena',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: note.isPrijava
                            ? theme.colorScheme.errorContainer
                            : theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Text(
                          note.isPrijava ? 'Zamjena' : 'Napomena',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: note.isPrijava
                                ? theme.colorScheme.onErrorContainer
                                : theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  dateText,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text('${note.idpot}  |  ${note.vodomjer}'),
                if (note.profil.trim().isNotEmpty) Text(note.profil),
                const SizedBox(height: 8),
                Text(
                  note.napomena.trim().isEmpty
                      ? 'Nema teksta napomene.'
                      : note.napomena,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openImage(BuildContext context, String imageUrl) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (context) {
        return Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Image.network(imageUrl, fit: BoxFit.contain),
                ),
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: IconButton.filled(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
