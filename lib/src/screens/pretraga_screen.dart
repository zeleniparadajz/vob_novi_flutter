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
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: const Icon(Icons.article_outlined),
        title: Text(
          item.potrosac,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${item.idpot}  |  ${item.vodomjer}\n${item.nazivReona} / ${item.nazivRute}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
