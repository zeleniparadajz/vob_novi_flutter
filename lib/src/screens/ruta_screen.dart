import 'package:flutter/material.dart';

import '../data/demo_repository.dart';
import '../models/vodovod_models.dart';
import '../widgets/reading_countdown.dart';
import 'ocitavanja_screen.dart';

class RutaScreen extends StatelessWidget {
  const RutaScreen({
    super.key,
    required this.repository,
    required this.user,
    required this.reon,
  });

  final DemoVodovodRepository repository;
  final InkasantiModel user;
  final ReonSummary reon;

  @override
  Widget build(BuildContext context) {
    final rute = repository.ruteZaReon(reon.id, user);
    return Scaffold(
      appBar: AppBar(title: Text(reon.naziv)),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          ReadingCountdown(
            ocitavanjeGlavno: repository.aktivnoOcitavanje,
            checkNetwork: repository.hasNetworkSignal,
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                for (final ruta in rute) ...[
                  Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: const Icon(Icons.route_outlined),
                      title: Text(
                        ruta.naziv,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text('${ruta.ocitano}/${ruta.ukupno} očitano'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => OcitavanjaScreen(
                              repository: repository,
                              user: user,
                              ruta: ruta,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
