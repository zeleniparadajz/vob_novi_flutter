import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/app_logger.dart';
import '../core/diagnostics_delivery.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});
  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  late Future<List<DiagnosticEntry>> _entries;
  bool _errorsOnly = true;

  @override
  void initState() {
    super.initState();
    _entries = AppLogger.read();
    unawaited(AppLogger.sendPending());
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Izvještaj je kopiran.')));
  }

  void _showEntry(DiagnosticEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: Column(
            children: [
              ListTile(
                title: const Text('Detalji događaja'),
                trailing: IconButton(
                  tooltip: 'Kopiraj detalje',
                  onPressed: () => _copy(entry.report),
                  icon: const Icon(Icons.copy_outlined),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(entry.report),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Greške i dijagnostika'),
      actions: [
        IconButton(
          tooltip: 'Osvježi dnevnik',
          onPressed: () => setState(() => _entries = AppLogger.read()),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<List<DiagnosticEntry>>(
      future: _entries,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(child: Text('Dnevnik trenutno nije dostupan.'));
        }
        final entries = (snapshot.data ?? [])
            .where((entry) => !_errorsOnly || entry.level != 'info')
            .toList();
        return Column(
          children: [
            ValueListenableBuilder<DiagnosticDeliveryStatus>(
              valueListenable: AppLogger.delivery,
              builder: (context, status, _) => ListTile(
                leading: status.sending
                    ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload_outlined),
                title: Text('Greške za slanje: ${status.pending}'),
                subtitle: Text(
                  !AppLogger.uploadConfigured
                      ? 'Online slanje nije podešeno u ovoj verziji aplikacije.'
                      : status.error ??
                            (status.lastSent == null
                                ? 'Posljednje slanje: nema'
                                : 'Posljednje slanje: ${DateFormat('dd.MM.yyyy HH:mm:ss').format(status.lastSent!.toLocal())}'),
                ),
                trailing: IconButton(
                  tooltip: 'Pošalji greške',
                  icon: const Icon(Icons.sync),
                  onPressed: !AppLogger.uploadConfigured || status.sending
                      ? null
                      : () async {
                          await AppLogger.sendPending(force: true);
                          if (mounted) {
                            setState(() => _entries = AppLogger.read());
                          }
                        },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('Greške')),
                        ButtonSegment(value: false, label: Text('Sve')),
                      ],
                      selected: {_errorsOnly},
                      onSelectionChanged: (selection) =>
                          setState(() => _errorsOnly = selection.single),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Kopiraj izvještaj',
                    onPressed: entries.isEmpty
                        ? null
                        : () => _copy(
                            entries.map((entry) => entry.report).join('\n\n'),
                          ),
                    icon: const Icon(Icons.copy_all_outlined),
                  ),
                ],
              ),
            ),
            if (AppLogger.writeFailure != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(AppLogger.writeFailure!),
              ),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Text(
                        _errorsOnly
                            ? 'Nema zabilježenih grešaka.'
                            : 'Dnevnik je prazan.',
                      ),
                    )
                  : ListView.separated(
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return ListTile(
                          leading: Icon(
                            entry.level != 'info'
                                ? Icons.error_outline
                                : Icons.info_outline,
                            color: entry.level != 'info'
                                ? Theme.of(context).colorScheme.error
                                : null,
                          ),
                          title: Text(
                            entry.message,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${DateFormat('dd.MM.yyyy HH:mm:ss').format(entry.time)}'
                            '${entry.userId == null ? "" : " · ID: ${entry.userId}"}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _showEntry(entry),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    ),
  );
}
