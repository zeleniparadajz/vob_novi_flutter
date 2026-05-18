import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/demo_repository.dart';

class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key, required this.repository, required this.child});

  final DemoVodovodRepository repository;
  final Widget child;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> with WidgetsBindingObserver {
  bool _isChecking = true;
  int _currentBuildNumber = 0;
  AppUpdateInfo? _requiredUpdate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_checkForUpdate());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkForUpdate(showChecking: false));
    }
  }

  Future<void> _checkForUpdate({bool showChecking = true}) async {
    if (showChecking && mounted) setState(() => _isChecking = true);
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentBuildNumber =
          int.tryParse(packageInfo.buildNumber.trim()) ?? 0;
      final update = await widget.repository.requiredUpdate(currentBuildNumber);
      if (!mounted) return;
      setState(() {
        _currentBuildNumber = currentBuildNumber;
        _requiredUpdate = update;
        _isChecking = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isChecking = false);
    }
  }

  Future<void> _openUpdate() async {
    final update = _requiredUpdate;
    if (update == null) return;
    final uri = Uri.tryParse(update.apkUrl);
    if (uri == null) return;

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Ne mogu otvoriti update link: ${update.apkUrl}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final update = _requiredUpdate;
    if (!_isChecking && update == null) return widget.child;

    final theme = Theme.of(context);
    final isAndroid = Platform.isAndroid;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    update == null
                        ? Icons.system_update_outlined
                        : Icons.new_releases_outlined,
                    size: 64,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    update == null
                        ? 'Provjera verzije'
                        : 'Dostupna je nova verzija',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    update == null
                        ? 'Provjeravam da li je instalirana najnovija verzija aplikacije.'
                        : _updateMessage(update, isAndroid),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (update == null)
                    const Center(child: CircularProgressIndicator())
                  else ...[
                    FilledButton.icon(
                      onPressed: _openUpdate,
                      icon: const Icon(Icons.download_outlined),
                      label: Text(
                        isAndroid
                            ? 'Preuzmi novu verziju'
                            : 'Otvori update link',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: () => unawaited(_checkForUpdate()),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Provjeri ponovo'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _updateMessage(AppUpdateInfo update, bool isAndroid) {
    final versionText =
        'Trenutna verzija: $_currentBuildNumber, nova verzija: ${update.versionCode}.';
    if (isAndroid) {
      return '$versionText Morate instalirati najnoviju verziju kako biste nastavili očitavanje.';
    }
    return '$versionText Instalacija ove verzije se radi van aplikacije.';
  }
}
