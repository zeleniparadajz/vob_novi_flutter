import 'dart:async';

import 'package:flutter/material.dart';

import '../data/demo_repository.dart';
import '../models/vodovod_models.dart';
import 'unos_screen.dart';

class UnsyncedReadingsScreen extends StatefulWidget {
  const UnsyncedReadingsScreen({
    super.key,
    required this.repository,
    required this.user,
  });

  final DemoVodovodRepository repository;
  final InkasantiModel user;

  @override
  State<UnsyncedReadingsScreen> createState() => _UnsyncedReadingsScreenState();
}

class _UnsyncedReadingsScreenState extends State<UnsyncedReadingsScreen> {
  bool isSyncing = false;

  Future<void> _sync() async {
    if (isSyncing) return;
    setState(() => isSyncing = true);
    try {
      final result = await widget.repository.syncPendingNow(
        reason: 'manual_unsynced_readings_screen',
      );
      await widget.repository.refreshLocalSyncState();
      if (!mounted) return;
      setState(() {});
      final message = result.readings > 0
          ? 'Sinhronizovano očitavanja: ${result.readings}.'
          : result.hadNetwork
          ? 'Nema novih očitavanja za slanje.'
          : 'Nema stabilne veze. Očitavanja ostaju u telefonu.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.repository.nesinhronizovanaOcitavanja(widget.user);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Za sinhronizaciju')),
      body: RefreshIndicator(
        onRefresh: () async {
          await widget.repository.refreshLocalSyncState();
          if (mounted) setState(() {});
        },
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          itemCount: items.isEmpty ? 1 : items.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            if (index == 0) {
              return FilledButton.icon(
                onPressed: isSyncing ? null : _sync,
                icon: isSyncing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_outlined),
                label: Text(isSyncing ? 'Sinhronizacija...' : 'Sinhronizuj'),
              );
            }
            final item = items[index - 1];
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Text(item.rbr > 0 ? item.rbr.toString() : '-'),
                ),
                title: Text(
                  item.potrosac,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${item.idpot} | ${item.vodomjer}\n'
                  'Novo: ${item.novoStanje} | Ind: ${item.idstanjebrojila}',
                ),
                trailing: Icon(
                  Icons.cloud_upload_outlined,
                  color: theme.colorScheme.error,
                ),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => UnosScreen(
                        repository: widget.repository,
                        user: widget.user,
                        ocitavanje: item,
                      ),
                    ),
                  );
                  await widget.repository.refreshLocalSyncState();
                  if (mounted) setState(() {});
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
