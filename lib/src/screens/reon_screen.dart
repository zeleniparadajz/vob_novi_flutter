import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../data/demo_repository.dart';
import '../models/vodovod_models.dart';
import '../widgets/reading_countdown.dart';
import 'login_screen.dart';
import 'pretraga_screen.dart';
import 'ruta_screen.dart';
import 'unsynced_notes_screen.dart';
import 'unsynced_readings_screen.dart';

class ReonScreen extends StatefulWidget {
  const ReonScreen({super.key, required this.repository, required this.user});

  final DemoVodovodRepository repository;
  final InkasantiModel user;

  @override
  State<ReonScreen> createState() => _ReonScreenState();
}

class _ReonScreenState extends State<ReonScreen> {
  int selectedTab = 0;
  final reoniNavigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
        body: IndexedStack(
          index: selectedTab,
          children: [
            Navigator(
              key: reoniNavigatorKey,
              onGenerateRoute: (_) {
                return MaterialPageRoute(
                  builder: (_) => _ReoniHomeScreen(
                    repository: widget.repository,
                    user: widget.user,
                    onSearch: _openGlobalSearch,
                    onLogout: _logout,
                  ),
                );
              },
            ),
            Scaffold(
              appBar: AppBar(title: const Text('Nesinhronizovane napomene')),
              body: UnsyncedNotesScreen(repository: widget.repository),
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: selectedTab,
          onDestinationSelected: _selectTab,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map),
              label: 'Očitavanja',
            ),
            NavigationDestination(
              icon: Icon(Icons.note_alt_outlined),
              selectedIcon: Icon(Icons.note_alt),
              label: 'Napomene',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleBack() async {
    final nested = reoniNavigatorKey.currentState;
    if (selectedTab == 0 && nested != null && nested.canPop()) {
      nested.pop();
      return;
    }
    if (selectedTab != 0) {
      setState(() => selectedTab = 0);
      return;
    }

    final readings = widget.repository.nesinhronizovanaOcitavanjaCount(
      widget.user,
    );
    final notes = widget.repository.nesinhronizovaneNapomene().length;
    if (readings == 0 && notes == 0) {
      await SystemNavigator.pop();
      return;
    }
    if (!mounted) return;
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Neposlati podaci'),
          content: Text(
            'Imate $readings očitavanja i $notes napomena koje nisu poslate. '
            'Ne brišu se iz telefona, ali preporučujemo sinhronizaciju prije izlaska.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Ostani'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Izađi'),
            ),
          ],
        );
      },
    );
    if (shouldExit == true) await SystemNavigator.pop();
  }

  void _selectTab(int index) {
    if (index == 0 && selectedTab == 0) {
      reoniNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    }
    setState(() => selectedTab = index);
  }

  void _openGlobalSearch() {
    final navigator = reoniNavigatorKey.currentState ?? Navigator.of(context);
    navigator.push(
      MaterialPageRoute(
        builder: (_) => PretragaScreen(repository: widget.repository),
      ),
    );
  }

  Future<void> _logout() async {
    await widget.repository.clearSavedLogin();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => LoginScreen(repository: widget.repository),
      ),
      (_) => false,
    );
  }
}

class _ReoniHomeScreen extends StatefulWidget {
  const _ReoniHomeScreen({
    required this.repository,
    required this.user,
    required this.onSearch,
    required this.onLogout,
  });

  final DemoVodovodRepository repository;
  final InkasantiModel user;
  final VoidCallback onSearch;
  final VoidCallback onLogout;

  @override
  State<_ReoniHomeScreen> createState() => _ReoniHomeScreenState();
}

class _ReoniHomeScreenState extends State<_ReoniHomeScreen> {
  bool isSyncing = false;
  bool isRefreshingSyncState = false;
  Timer? refreshTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshSyncState());
    _startRefreshTimer();
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _manualSync() async {
    if (isSyncing) return;
    await _refreshSyncState();
    final beforeReadings = widget.repository.nesinhronizovanaOcitavanjaCount(
      widget.user,
    );
    final beforeNotes = widget.repository.nesinhronizovaneNapomene().length;
    setState(() => isSyncing = true);
    _startRefreshTimer();
    try {
      final result = await widget.repository.syncPendingNow(
        reason: 'manual_readings_button',
      );
      if (!mounted) return;
      await _refreshSyncState();
      if (!mounted) return;
      final afterReadings = widget.repository.nesinhronizovanaOcitavanjaCount(
        widget.user,
      );
      final afterNotes = widget.repository.nesinhronizovaneNapomene().length;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _syncMessage(
              result.readings,
              result.notes,
              beforeReadings,
              beforeNotes,
              afterReadings,
              afterNotes,
              result.hadNetwork,
            ),
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
      (_) => unawaited(_refreshSyncState()),
    );
  }

  Future<void> _refreshSyncState() async {
    if (isRefreshingSyncState) return;
    isRefreshingSyncState = true;
    try {
      await widget.repository.refreshLocalSyncState();
      if (mounted) setState(() {});
    } finally {
      isRefreshingSyncState = false;
    }
  }

  String _syncMessage(
    int readings,
    int notes,
    int beforeReadings,
    int beforeNotes,
    int afterReadings,
    int afterNotes,
    bool hadNetwork,
  ) {
    if (readings > 0 || notes > 0) {
      return 'Sinhronizovano: $readings očitavanja, $notes napomena.';
    }
    if (!hadNetwork && (afterReadings > 0 || afterNotes > 0)) {
      return 'Nema stabilne veze. Podaci ostaju u telefonu i poslati će se automatski.';
    }
    if ((beforeReadings > 0 || beforeNotes > 0) &&
        afterReadings == 0 &&
        afterNotes == 0) {
      return 'Podaci su već sinhronizovani.';
    }
    if (afterReadings > 0 || afterNotes > 0) {
      final candidates = widget.repository.lastReadingsSyncCandidates;
      final error = widget.repository.lastReadingsSyncError;
      if (beforeReadings > 0 && candidates == 0) {
        return 'Za sync je $beforeReadings, ali lokalna lista za slanje je prazna. Restartuj app pa probaj opet.';
      }
      if (error != null && error.isNotEmpty) {
        return 'Očitavanja nisu poslata. $error';
      }
      return 'Sinhronizacija je već u toku ili veza nije dobra. Ostaje za sljedeći pokušaj.';
    }
    return 'Nema novih podataka za sinhronizaciju.';
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    final user = widget.user;
    final reoni = repository.reoni(user);
    final total = reoni.fold(0, (sum, reon) => sum + reon.ukupno);
    final ocitano = reoni.fold(0, (sum, reon) => sum + reon.ocitano);
    final zaSinhronizaciju = repository.nesinhronizovanaOcitavanjaCount(user);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            ReadingCountdown(
              ocitavanjeGlavno: repository.aktivnoOcitavanje,
              checkNetwork: repository.hasNetworkSignal,
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _GlobalSearchButton(onTap: widget.onSearch),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _StatusHeader(
                user: user,
                total: total,
                ocitano: ocitano,
                zaSinhronizaciju: zaSinhronizaciju,
                lastSuccessfulSyncAt: repository.lastSuccessfulSyncAt,
                isSyncing: isSyncing,
                onSync: _manualSync,
                onLogout: widget.onLogout,
                onPendingTap: _openUnsyncedReadings,
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reoni',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final reon in reoni) ...[
                    _ReonCard(
                      reon: reon,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => RutaScreen(
                              repository: repository,
                              user: user,
                              reon: reon,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openUnsyncedReadings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UnsyncedReadingsScreen(
          repository: widget.repository,
          user: widget.user,
        ),
      ),
    );
    await _refreshSyncState();
  }
}

class _GlobalSearchButton extends StatelessWidget {
  const _GlobalSearchButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.search),
      label: const Text('Globalna pretraga'),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({
    required this.user,
    required this.total,
    required this.ocitano,
    required this.zaSinhronizaciju,
    required this.lastSuccessfulSyncAt,
    required this.isSyncing,
    required this.onSync,
    required this.onLogout,
    required this.onPendingTap,
  });

  final InkasantiModel user;
  final int total;
  final int ocitano;
  final int zaSinhronizaciju;
  final DateTime? lastSuccessfulSyncAt;
  final bool isSyncing;
  final VoidCallback onSync;
  final VoidCallback onLogout;
  final VoidCallback onPendingTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final neocitano = total - ocitano;
    const syncColor = Color(0xFF2E7D32);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(
                Icons.badge_outlined,
                size: 25,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          user.ime,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Odjavi se',
                        onPressed: onLogout,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.logout_outlined, size: 20),
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                  Text(
                    'ID: ${user.idZaOcitavanja}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _StatChip(label: 'Ukupno', value: total),
                      _StatChip(label: 'Očitano', value: ocitano),
                      _StatChip(label: 'Neočitano', value: neocitano),
                      _SyncStatButton(
                        label: 'Za sync',
                        value: zaSinhronizaciju,
                        onTap: onPendingTap,
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    _lastSyncText(lastSuccessfulSyncAt),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 9),
                  SizedBox(
                    height: isSyncing ? 42 : 34,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: syncColor.withValues(alpha: 0.12),
                        foregroundColor: syncColor,
                        disabledBackgroundColor: syncColor.withValues(
                          alpha: 0.10,
                        ),
                        disabledForegroundColor: syncColor.withValues(
                          alpha: 0.78,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: isSyncing ? null : onSync,
                      icon: isSyncing
                          ? const SizedBox.square(
                              dimension: 15,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: syncColor,
                              ),
                            )
                          : const Icon(Icons.sync_outlined, size: 18),
                      label: Text(
                        isSyncing ? 'Sinhronizacija...' : 'Sinhronizuj',
                      ),
                    ),
                  ),
                  if (isSyncing) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: const LinearProgressIndicator(
                        minHeight: 3,
                        color: syncColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _lastSyncText(DateTime? value) {
    if (value == null) return 'Poslednja sinhronizacija: nema';
    return 'Poslednja sinhronizacija: ${DateFormat('dd.MM.yyyy HH:mm').format(value)}';
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label: $value',
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SyncStatButton extends StatelessWidget {
  const _SyncStatButton({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final int value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.primary,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_upload_outlined, size: 15),
              const SizedBox(width: 5),
              Text(
                '$label: $value',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 3),
              const Icon(Icons.chevron_right, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReonCard extends StatelessWidget {
  const _ReonCard({required this.reon, required this.onTap});

  final ReonSummary reon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progress = reon.ukupno == 0 ? 0.0 : reon.ocitano / reon.ukupno;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      reon.naziv,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 8),
              Text('${reon.ocitano}/${reon.ukupno} očitano'),
            ],
          ),
        ),
      ),
    );
  }
}
