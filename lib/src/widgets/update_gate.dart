import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/apk_updater.dart';
import '../core/app_logger.dart';
import '../data/demo_repository.dart';
import '../screens/diagnostics_screen.dart';

class UpdateGate extends StatefulWidget {
  const UpdateGate({
    super.key,
    required this.repository,
    required this.child,
    this.alwaysShow = false,
    this.updater,
  });

  final DemoVodovodRepository repository;
  final Widget child;
  final bool alwaysShow;
  final ApkUpdater? updater;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> with WidgetsBindingObserver {
  bool _isChecking = true;
  int _currentBuildNumber = 0;
  String _currentVersion = '';
  AppUpdateInfo? _requiredUpdate;
  late final ApkUpdater _updater;
  bool _checking = false;
  bool _busy = false;
  bool _waitingForPermission = false;
  bool _returningFromInstaller = false;
  bool _resumingPermission = false;
  File? _apk;
  int _received = 0;
  int? _total;
  String? _error;
  String? _status;

  @override
  void initState() {
    super.initState();
    _updater = widget.updater ?? ApkUpdater();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_checkForUpdate());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _updater.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_waitingForPermission && !_busy) {
        unawaited(_install(resumingPermission: true));
        return;
      }
      if (_returningFromInstaller) {
        _returningFromInstaller = false;
        // Opening the installer is not proof that the user installed the APK.
        if (mounted) {
          setState(
            () => _status =
                'Ako instalacija nije završena, možete pokušati ponovo.',
          );
        }
        return;
      }
      if (_busy || _apk != null) return;
      unawaited(_checkForUpdate(showChecking: false));
    }
  }

  Future<void> _checkForUpdate({bool showChecking = true}) async {
    if (_checking || _busy) return;
    _checking = true;
    if (showChecking && mounted) setState(() => _isChecking = true);
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentBuildNumber =
          int.tryParse(packageInfo.buildNumber.trim()) ?? 0;
      if (mounted) {
        setState(() {
          _currentVersion = packageInfo.version;
          _currentBuildNumber = currentBuildNumber;
        });
      }
      final update = await widget.repository.requiredUpdate(currentBuildNumber);
      if (!mounted) return;
      setState(() {
        if (update?.versionCode != _requiredUpdate?.versionCode ||
            update?.apkUrl != _requiredUpdate?.apkUrl) {
          _apk = null;
        }
        _requiredUpdate = update;
        _isChecking = false;
        _error = null;
        _status = null;
      });
    } catch (error, stack) {
      unawaited(AppLogger.error('Provjera nove verzije', error, stack));
      if (!mounted) return;
      setState(() {
        _isChecking = false;
        _error =
            'Provjera verzije nije uspjela. Provjerite internet i pokušajte ponovo.';
      });
    } finally {
      _checking = false;
    }
  }

  Future<void> _openUpdate() async {
    final update = _requiredUpdate;
    if (update == null || _busy) return;
    if (defaultTargetPlatform != TargetPlatform.android) {
      try {
        final opened = await launchUrl(
          Uri.parse(update.apkUrl),
          mode: LaunchMode.externalApplication,
        );
        if (!opened) throw StateError('Link nije moguće otvoriti.');
      } catch (error, stack) {
        unawaited(AppLogger.error('Otvaranje update linka', error, stack));
        if (mounted) {
          setState(() => _error = 'Link za novu verziju nije moguće otvoriti.');
        }
      }
      return;
    }
    if (_apk != null) return _install();
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Preuzimanje nove verzije...';
      _received = 0;
      _total = null;
    });
    try {
      final file = await _updater.download(
        url: update.apkUrl,
        versionCode: update.versionCode,
        onProgress: (received, total) {
          if (mounted) {
            setState(() {
              _received = received;
              _total = total;
            });
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _apk = file;
        _busy = false;
      });
      unawaited(
        AppLogger.log('APK preuzet i provjeren: ${update.versionCode}'),
      );
      await _install();
    } on UpdateCancelled {
      if (mounted) setState(() => _status = 'Preuzimanje je prekinuto.');
    } catch (error, stack) {
      unawaited(AppLogger.error('Preuzimanje APK-a', error, stack));
      if (mounted) {
        setState(() {
          _error = error is PlatformException
              ? error.message
              : 'Preuzimanje nije uspjelo. Pokušajte ponovo.';
          _status = null;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _install({bool resumingPermission = false}) async {
    if (_busy ||
        _apk == null ||
        _requiredUpdate == null ||
        _resumingPermission) {
      return;
    }
    _resumingPermission = resumingPermission;
    _waitingForPermission = false;
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Priprema instalacije...';
    });
    try {
      // A denied permission must not reopen Settings in a loop on every resume.
      if (resumingPermission && !await ApkUpdater.canInstall()) {
        if (mounted) {
          setState(
            () => _status =
                'Instalacija nije dozvoljena. Dodirnite Instaliraj za ponovni pokušaj.',
          );
        }
        return;
      }
      final result = await _updater.install(
        _apk!,
        _requiredUpdate!.versionCode,
      );
      if (!mounted) return;
      _waitingForPermission = result == 'permission_required';
      _returningFromInstaller = !_waitingForPermission;
      setState(
        () => _status = _waitingForPermission
            ? 'Dozvolite instalaciju iz ove aplikacije, pa se vratite.'
            : 'Potvrdite ažuriranje u Android prozoru za instalaciju.',
      );
      unawaited(AppLogger.log('Instalacija APK-a: $result'));
    } catch (error, stack) {
      unawaited(AppLogger.error('Instalacija APK-a', error, stack));
      if (mounted) {
        setState(() {
          if (error is PlatformException && error.code == 'invalid_apk') {
            _apk = null;
          }
          _error = error is PlatformException
              ? error.message
              : 'Instalaciju nije moguće pokrenuti.';
          _status = null;
        });
      }
    } finally {
      _resumingPermission = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final update = _requiredUpdate;
    if (!widget.alwaysShow && !_isChecking && update == null) {
      return widget.child;
    }

    final theme = Theme.of(context);
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ažuriranje aplikacije'),
        actions: [
          IconButton(
            tooltip: 'Greške i dijagnostika',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DiagnosticsScreen()),
            ),
            icon: const Icon(Icons.bug_report_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
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
                        ? _isChecking
                              ? 'Provjera verzije'
                              : 'Verzija aplikacije'
                        : 'Dostupna je nova verzija',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    update == null
                        ? _isChecking
                              ? 'Provjeravam da li je instalirana najnovija verzija aplikacije.'
                              : 'Instalirana verzija: $_currentVersion ($_currentBuildNumber)${_error == null ? "\nInstalirana je najnovija verzija." : ""}'
                        : _updateMessage(update, isAndroid),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_status != null) ...[
                    Text(_status!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                  ],
                  if (_busy) ...[
                    LinearProgressIndicator(
                      value: _apk == null && _total != null
                          ? _received / _total!
                          : null,
                    ),
                    const SizedBox(height: 8),
                    if (_apk == null)
                      Text(
                        _total == null
                            ? '${(_received / 1048576).toStringAsFixed(1)} MB'
                            : '${(_received * 100 / _total!).toStringAsFixed(0)}% · ${(_received / 1048576).toStringAsFixed(1)} / ${(_total! / 1048576).toStringAsFixed(1)} MB',
                        textAlign: TextAlign.center,
                      ),
                    if (_apk == null)
                      TextButton(
                        onPressed: _updater.cancel,
                        child: const Text('Prekini preuzimanje'),
                      ),
                    const SizedBox(height: 12),
                  ],
                  if (_isChecking)
                    const Center(child: CircularProgressIndicator())
                  else if (update != null) ...[
                    FilledButton.icon(
                      onPressed: _busy ? null : _openUpdate,
                      icon: Icon(
                        _apk == null
                            ? Icons.download_outlined
                            : Icons.install_mobile_outlined,
                      ),
                      label: Text(
                        isAndroid
                            ? _apk == null
                                  ? 'Preuzmi i instaliraj'
                                  : 'Instaliraj'
                            : 'Otvori update link',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => unawaited(_checkForUpdate()),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Provjeri ponovo'),
                    ),
                  ],
                  if (!_isChecking && update == null)
                    TextButton.icon(
                      onPressed: () => unawaited(_checkForUpdate()),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Provjeri ponovo'),
                    ),
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
        'Trenutna verzija: $_currentVersion ($_currentBuildNumber). Nova verzija: ${update.versionName ?? update.versionCode}.';
    if (isAndroid) {
      return widget.alwaysShow
          ? '$versionText Preuzmite novu verziju i potvrdite instalaciju.'
          : '$versionText Morate instalirati najnoviju verziju kako biste nastavili očitavanje.';
    }
    return '$versionText Instalacija ove verzije se radi van aplikacije.';
  }
}
