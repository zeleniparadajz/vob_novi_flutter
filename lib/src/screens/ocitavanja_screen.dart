import 'dart:async';

import 'package:flutter/material.dart';

import '../data/demo_repository.dart';
import '../models/vodovod_models.dart';
import 'potrosac_napomene_screen.dart';
import '../widgets/reading_countdown.dart';
import 'unos_screen.dart';

class OcitavanjaScreen extends StatefulWidget {
  const OcitavanjaScreen({
    super.key,
    required this.repository,
    required this.user,
    required this.ruta,
  });

  final DemoVodovodRepository repository;
  final InkasantiModel user;
  final RutaSummary ruta;

  @override
  State<OcitavanjaScreen> createState() => _OcitavanjaScreenState();
}

class _OcitavanjaScreenState extends State<OcitavanjaScreen> {
  String query = '';
  Map<String, BackendNapomenaModel> latestNotes = {};

  @override
  void initState() {
    super.initState();
    unawaited(_loadLatestNoteThumbs());
  }

  Future<void> _loadLatestNoteThumbs() async {
    final items = widget.repository.ocitavanjaZaRutu(
      widget.ruta.id,
      widget.user,
    );
    final hasInternet = await widget.repository.hasNetworkSignal();
    if (!mounted || !hasInternet) return;
    try {
      final notes = await widget.repository.latestNapomeneForIdpots(
        items.map((item) => item.idpot),
      );
      if (!mounted) return;
      setState(() => latestNotes = notes);
    } catch (_) {
      // Thumbnails are online-only. The reading list must stay usable offline.
    }
  }

  @override
  Widget build(BuildContext context) {
    final allItems = widget.repository.ocitavanjaZaRutu(
      widget.ruta.id,
      widget.user,
    );
    final items = _filterItems(allItems);
    return Scaffold(
      appBar: AppBar(title: Text(widget.ruta.naziv)),
      body: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: items.length + 2,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == 0) {
            return ReadingCountdown(
              ocitavanjeGlavno: widget.repository.aktivnoOcitavanje,
              checkNetwork: widget.repository.hasNetworkSignal,
            );
          }
          if (index == 1) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Ime potrošača, šifra ili vodomjer',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => query = value),
              ),
            );
          }
          final item = items[index - 2];
          return _OcitavanjeTile(
            item: item,
            latestNote: latestNotes[item.idpot],
            onNoteTap: () async {
              final hasNetwork = await widget.repository.hasNetworkSignal();
              if (!context.mounted) return;
              if (!hasNetwork) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Nema interneta. Napomene možete otvoriti kada telefon bude online.',
                    ),
                  ),
                );
                return;
              }
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PotrosacNapomeneScreen(
                    repository: widget.repository,
                    idpot: item.idpot,
                    potrosac: item.potrosac,
                  ),
                ),
              );
            },
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
              setState(() {});
            },
          );
        },
      ),
    );
  }

  List<OcitavanjeModel> _filterItems(List<OcitavanjeModel> items) {
    final value = query.trim().toLowerCase();
    if (value.isEmpty) return items;
    return items.where((item) {
      return item.potrosac.toLowerCase().contains(value) ||
          item.idpot.toLowerCase().contains(value) ||
          item.vodomjer.toLowerCase().contains(value);
    }).toList();
  }
}

class _OcitavanjeTile extends StatelessWidget {
  const _OcitavanjeTile({
    required this.item,
    required this.latestNote,
    required this.onNoteTap,
    required this.onTap,
  });

  final OcitavanjeModel item;
  final BackendNapomenaModel? latestNote;
  final VoidCallback onNoteTap;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = item.isOcitano
        ? item.idstanjebrojila > 1
              ? const Color(0xFFB45309)
              : theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    final syncColor = item.isSynced
        ? theme.colorScheme.primary
        : theme.colorScheme.error;
    return Card(
      color: item.isOcitano
          ? item.idstanjebrojila > 1
                ? const Color(0xFFFFF4DE)
                : const Color(0xFFEAF7EF)
          : Colors.white,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        leading: CircleAvatar(
          radius: 22,
          backgroundColor: statusColor.withValues(alpha: 0.12),
          child: Text(
            item.rbr > 0 ? item.rbr.toString() : '-',
            style: TextStyle(color: statusColor, fontWeight: FontWeight.w800),
          ),
        ),
        title: Text(
          item.potrosac,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _MiniTag(text: item.idpot, icon: Icons.person_outline),
                  _MiniTag(
                    text: item.vodomjer,
                    icon: Icons.water_drop_outlined,
                  ),
                  if (item.idstanjebrojila > 0)
                    _MiniTag(
                      text: 'Ind: ${item.idstanjebrojila}',
                      icon: Icons.flag_outlined,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                item.adr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (item.lokacija.trim().isNotEmpty)
                Text(
                  item.lokacija,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
        trailing: _TrailingStatus(
          note: latestNote,
          syncIcon: item.isSynced
              ? Icons.cloud_done_outlined
              : Icons.cloud_off_outlined,
          syncColor: syncColor,
          onNoteTap: onNoteTap,
        ),
        onTap: onTap,
      ),
    );
  }
}

class _TrailingStatus extends StatelessWidget {
  const _TrailingStatus({
    required this.note,
    required this.syncIcon,
    required this.syncColor,
    required this.onNoteTap,
  });

  final BackendNapomenaModel? note;
  final IconData syncIcon;
  final Color syncColor;
  final VoidCallback onNoteTap;

  @override
  Widget build(BuildContext context) {
    final note = this.note;
    final theme = Theme.of(context);
    final hasImage = note != null && note.imageUrl.trim().isNotEmpty;
    return SizedBox(
      width: hasImage ? 96 : 28,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (hasImage) ...[
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onNoteTap,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox.square(
                  dimension: 64,
                  child: Image.network(
                    note.imageUrl,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return ColoredBox(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Center(
                          child: SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    },
                    errorBuilder: (_, _, _) {
                      return ColoredBox(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.image_not_supported_outlined,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Icon(syncIcon, color: syncColor, size: 22),
        ],
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              text,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
