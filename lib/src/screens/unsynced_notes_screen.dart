import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';

import '../data/demo_repository.dart';

class UnsyncedNotesScreen extends StatefulWidget {
  const UnsyncedNotesScreen({super.key, required this.repository});

  final DemoVodovodRepository repository;

  @override
  State<UnsyncedNotesScreen> createState() => _UnsyncedNotesScreenState();
}

class _UnsyncedNotesScreenState extends State<UnsyncedNotesScreen> {
  bool isSyncing = false;
  bool isRefreshing = false;
  Timer? refreshTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshNotes());
    _startRefreshTimer();
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _syncNotes() async {
    if (isSyncing) return;
    await _refreshNotes();
    final before = widget.repository.nesinhronizovaneNapomene().length;
    setState(() => isSyncing = true);
    _startRefreshTimer();
    try {
      final result = await widget.repository.syncPendingNow(
        reason: 'manual_notes_button',
      );
      if (!mounted) return;
      await _refreshNotes();
      if (!mounted) return;
      final after = widget.repository.nesinhronizovaneNapomene().length;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _syncMessage(result.notes, before, after, result.hadNetwork),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => isSyncing = false);
        _startRefreshTimer();
      }
    }
  }

  void _startRefreshTimer() {
    refreshTimer?.cancel();
    refreshTimer = Timer.periodic(
      Duration(seconds: isSyncing ? 1 : 10),
      (_) => unawaited(_refreshNotes()),
    );
  }

  Future<void> _refreshNotes() async {
    if (isRefreshing) return;
    isRefreshing = true;
    try {
      await widget.repository.refreshLocalSyncState();
      if (mounted) setState(() {});
    } finally {
      isRefreshing = false;
    }
  }

  String _syncMessage(int synced, int before, int after, bool hadNetwork) {
    if (synced > 0) return 'Sinhronizovano napomena: $synced.';
    if (!hadNetwork && after > 0) {
      return 'Nema stabilne veze. Napomene ostaju u telefonu.';
    }
    if (before > 0 && after == 0) return 'Napomene su već sinhronizovane.';
    if (after > 0) {
      final error = widget.repository.lastNotesSyncError;
      if (error != null && error.isNotEmpty) {
        return 'Napomene nisu poslate. $error';
      }
      return 'Napomene nisu prošle. Ostaju u telefonu za sljedeći pokušaj.';
    }
    return 'Nema napomena za sinhronizaciju.';
  }

  @override
  Widget build(BuildContext context) {
    final notes = widget.repository.nesinhronizovaneNapomene();
    if (notes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _NotesSyncButton(isSyncing: isSyncing, onSync: _syncNotes),
            const Expanded(
              child: Center(child: Text('Nema nesinhronizovanih napomena.')),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: notes.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _NotesSyncButton(isSyncing: isSyncing, onSync: _syncNotes);
        }
        final note = notes[index - 1];
        final imageFile = File(note.slikaPath);
        return Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox.square(
                dimension: 56,
                child: imageFile.existsSync()
                    ? Image.file(imageFile, fit: BoxFit.cover)
                    : ColoredBox(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        child: Icon(
                          note.isPrijava
                              ? Icons.swap_horiz_outlined
                              : Icons.note_alt_outlined,
                        ),
                      ),
              ),
            ),
            title: Text(
              note.imepot,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              '${note.idpot}  |  ${note.vodomjer}\n'
              '${note.isPrijava ? 'Zamjena' : 'Napomena'}  |  ${note.profil}\n'
              '${note.napomena}',
            ),
            trailing: const Icon(Icons.cloud_off_outlined),
          ),
        );
      },
    );
  }
}

class _NotesSyncButton extends StatelessWidget {
  const _NotesSyncButton({required this.isSyncing, required this.onSync});

  final bool isSyncing;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    const syncColor = Color(0xFF2E7D32);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: syncColor.withValues(alpha: 0.12),
            foregroundColor: syncColor,
            disabledBackgroundColor: syncColor.withValues(alpha: 0.10),
            disabledForegroundColor: syncColor.withValues(alpha: 0.78),
          ),
          onPressed: isSyncing ? null : onSync,
          icon: isSyncing
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: syncColor,
                  ),
                )
              : const Icon(Icons.sync_outlined),
          label: Text(
            isSyncing ? 'Sinhronizacija napomena...' : 'Sinhronizuj napomene',
          ),
        ),
        if (isSyncing) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: const LinearProgressIndicator(
              minHeight: 3,
              color: syncColor,
            ),
          ),
        ],
      ],
    );
  }
}
