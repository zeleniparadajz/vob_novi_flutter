import 'package:flutter/material.dart';

import '../data/demo_repository.dart';
import '../models/vodovod_models.dart';
import 'unos_screen.dart';

class PretragaScreen extends StatefulWidget {
  const PretragaScreen({super.key, required this.repository});

  final DemoVodovodRepository repository;

  @override
  State<PretragaScreen> createState() => _PretragaScreenState();
}

class _PretragaScreenState extends State<PretragaScreen> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final results = widget.repository.pretraga(query);
    return Scaffold(
      appBar: AppBar(title: const Text('Pretraga')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Ime potrošača, šifra ili vodomjer',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => query = value),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: results.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                return _SearchTile(
                  item: results[index],
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => UnosScreen(
                          repository: widget.repository,
                          user: widget.repository.currentUser,
                          ocitavanje: results[index],
                        ),
                      ),
                    );
                    setState(() {});
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchTile extends StatelessWidget {
  const _SearchTile({required this.item, required this.onTap});

  final OcitavanjeModel item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = item.isOcitano
        ? item.idstanjebrojila > 1
              ? const Color(0xFFB45309)
              : theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    final syncIcon = item.isOcitano && item.isSynced
        ? Icons.cloud_done_outlined
        : Icons.cloud_off_outlined;
    final syncColor = item.isOcitano && item.isSynced
        ? theme.colorScheme.primary
        : theme.colorScheme.error;
    return Card(
      color: item.isOcitano
          ? item.idstanjebrojila > 1
                ? const Color(0xFFFFF4DE)
                : const Color.fromARGB(255, 181, 255, 202)
          : Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: statusColor.withValues(alpha: 0.12),
                child: Text(
                  item.rbr > 0 ? item.rbr.toString() : '-',
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.potrosac,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _SearchTag(
                          text: item.idpot,
                          icon: Icons.person_outline,
                        ),
                        _SearchTag(
                          text: item.vodomjer,
                          icon: Icons.water_drop_outlined,
                        ),
                        if (item.idstanjebrojila > 0)
                          _SearchTag(
                            text: 'Ind: ${item.idstanjebrojila}',
                            icon: Icons.flag_outlined,
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${item.nazivReona} / ${item.nazivRute}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(syncIcon, color: syncColor, size: 22),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchTag extends StatelessWidget {
  const _SearchTag({required this.text, required this.icon});

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
