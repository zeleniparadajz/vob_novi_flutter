import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../data/demo_repository.dart';
import '../models/vodovod_models.dart';
import 'napomena_screen.dart';

class UnosScreen extends StatefulWidget {
  const UnosScreen({
    super.key,
    required this.repository,
    required this.user,
    required this.ocitavanje,
  });

  final DemoVodovodRepository repository;
  final InkasantiModel user;
  final OcitavanjeModel ocitavanje;

  @override
  State<UnosScreen> createState() => _UnosScreenState();
}

class _UnosScreenState extends State<UnosScreen> {
  late final TextEditingController stanjeController;
  late int selectedIndikatorId;
  bool isSaving = false;

  StanjeBrojilaModel? get selectedIndikator {
    return widget.repository.stanjeBrojilaById(selectedIndikatorId);
  }

  bool get shouldCopyOldState {
    return selectedIndikator?.oznaka.trim().toUpperCase() == 'P';
  }

  bool get hideStateValues => widget.user.vidljivoStanje == 0;

  @override
  void initState() {
    super.initState();
    selectedIndikatorId = widget.ocitavanje.idstanjebrojila == 0
        ? 1
        : widget.ocitavanje.idstanjebrojila;
    stanjeController = TextEditingController(
      text: widget.ocitavanje.novoStanje > 0
          ? widget.ocitavanje.novoStanje.toString()
          : '',
    );
    if (shouldCopyOldState) {
      stanjeController.text = widget.ocitavanje.stanje.toString();
    }
  }

  @override
  void dispose() {
    stanjeController.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (isSaving) return;
    setState(() => isSaving = true);
    try {
      if (shouldCopyOldState) {
        stanjeController.text = widget.ocitavanje.stanje.toString();
      }
      final value = int.tryParse(stanjeController.text.trim());
      if (value == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unesi novo stanje brojila.')),
        );
        return;
      }
      final difference = value - widget.ocitavanje.stanje;
      if (!shouldCopyOldState && value < widget.ocitavanje.stanje) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ne možete unijeti stanje manje od prethodnog.'),
          ),
        );
        return;
      }
      if (!shouldCopyOldState &&
          widget.user.opomenaStanje > 0 &&
          difference >= widget.user.opomenaStanje) {
        final confirmed = await _confirmLargeDifference(difference);
        if (!confirmed) return;
      }
      final position = await _getCurrentPosition();
      if (!mounted || position == null) return;
      await widget.repository.sacuvajOcitavanje(
        widget.ocitavanje.id,
        value,
        selectedIndikatorId,
        position.latitude.toString(),
        position.longitude.toString(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stanje je zapamćeno u telefonu za sinhronizaciju.'),
        ),
      );
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  Future<bool> _confirmLargeDifference(int difference) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Pažnja'),
          content: Text(
            'Novo stanje je veće od starog za $difference m3.\n'
            'Da li želite da sačuvate?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Ne'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Da'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<Position?> _getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Morate uključiti lokaciju da bi nastavili.'),
        ),
      );
      await Geolocator.openLocationSettings();
      return null;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dozvola za lokaciju je potrebna za očitavanje.'),
        ),
      );
      if (permission == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
      }
      return null;
    }

    try {
      final currentPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 3),
        ),
      );
      return currentPosition;
    } catch (_) {
      return await Geolocator.getLastKnownPosition();
    }
  }

  Future<void> chooseIndikator() async {
    final options = widget.repository.stanjaBrojila;
    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nema učitanih indikatora.')),
      );
      return;
    }

    final selected = await showModalBottomSheet<StanjeBrojilaModel>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: options.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final option = options[index];
              final isSelected = option.id == selectedIndikatorId;
              return ListTile(
                leading: CircleAvatar(child: Text(option.id.toString())),
                title: Text(option.opis.isEmpty ? option.label : option.opis),
                subtitle: Text('ID: ${option.id}'),
                trailing: isSelected ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(option),
              );
            },
          ),
        );
      },
    );

    if (selected == null) return;
    setState(() {
      selectedIndikatorId = selected.id;
      if (shouldCopyOldState) {
        stanjeController.text = widget.ocitavanje.stanje.toString();
      } else if (stanjeController.text == widget.ocitavanje.stanje.toString()) {
        stanjeController.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.ocitavanje;
    final theme = Theme.of(context);
    final indikator = selectedIndikator;
    final potrosnja = _calculatePotrosnja();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Unos očitavanja'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: () {
                Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute(
                    builder: (_) => NapomenaScreen(
                      repository: widget.repository,
                      ocitavanje: item,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('Napomena'),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(
                  builder: (_) => NapomenaScreen(
                    repository: widget.repository,
                    ocitavanje: item,
                    quickMode: true,
                    autoOpenCamera: true,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Brzo slikanje'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoIdentityRow(idpot: item.idpot, potrosac: item.potrosac),
                  const SizedBox(height: 8),
                  _InfoRow(icon: Icons.home_outlined, text: item.adr),
                  _InfoRow(icon: Icons.pin_drop_outlined, text: item.lokacija),
                  _InfoRow(
                    icon: Icons.water_drop_outlined,
                    text: item.vodomjer,
                  ),
                  _InfoRow(
                    icon: Icons.account_balance_wallet_outlined,
                    text: 'Dug ${item.saldo}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: hideStateValues
                            ? _MeterBox(
                                label: 'Staro stanje',
                                value: 'Sakriveno',
                              )
                            : _MeterBox(
                                label: 'Staro stanje',
                                value: item.stanje.toString(),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MeterBox(
                          label: 'Indikator',
                          value: selectedIndikatorId.toString(),
                          subtitle: indikator?.opis,
                          icon: Icons.edit_outlined,
                          onTap: chooseIndikator,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (!shouldCopyOldState) ...[
                    TextField(
                      controller: stanjeController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => unawaited(save()),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Novo stanje',
                        prefixIcon: Icon(Icons.edit_outlined),
                      ),
                    ),
                    if (potrosnja != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Potrošnja: $potrosnja m3',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ] else ...[
                    TextField(
                      controller: TextEditingController(
                        text: item.stanje.toString(),
                      ),
                      enabled: false,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Novo stanje',
                        prefixIcon: Icon(Icons.content_copy_outlined),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: isSaving ? null : () => unawaited(save()),
                    icon: isSaving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(isSaving ? 'Čuvanje...' : 'Očitaj'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  int? _calculatePotrosnja() {
    final novoStanje = int.tryParse(stanjeController.text.trim());
    if (novoStanje == null) return null;
    return novoStanje - widget.ocitavanje.stanje;
  }
}

class _InfoIdentityRow extends StatelessWidget {
  const _InfoIdentityRow({required this.idpot, required this.potrosac});

  final String idpot;
  final String potrosac;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelLarge?.copyWith(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w700,
    );
    final potrosacStyle = theme.textTheme.titleSmall?.copyWith(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w800,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(
            Icons.person_outline,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(idpot, style: style),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              potrosac,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: potrosacStyle,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _MeterBox extends StatelessWidget {
  const _MeterBox({
    required this.label,
    required this.value,
    this.subtitle,
    this.icon,
    this.onTap,
  });

  final String label;
  final String value;
  final String? subtitle;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(label, style: theme.textTheme.labelMedium),
                  ),
                  if (icon != null) Icon(icon, size: 16),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
