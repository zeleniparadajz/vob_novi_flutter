import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class LocationGate extends StatefulWidget {
  const LocationGate({super.key, required this.child});

  final Widget child;

  @override
  State<LocationGate> createState() => _LocationGateState();
}

class _LocationGateState extends State<LocationGate>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _isChecking = true;
  bool _serviceEnabled = false;
  LocationPermission _permission = LocationPermission.denied;

  bool get _canUseApp {
    return _serviceEnabled &&
        (_permission == LocationPermission.always ||
            _permission == LocationPermission.whileInUse);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_checkLocation(requestPermission: true));
    _timer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_checkLocation()),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkLocation(requestPermission: true));
    }
  }

  Future<void> _checkLocation({bool requestPermission = false}) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    var permission = await Geolocator.checkPermission();

    if (requestPermission &&
        serviceEnabled &&
        permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (!mounted) return;
    setState(() {
      _serviceEnabled = serviceEnabled;
      _permission = permission;
      _isChecking = false;
    });
  }

  Future<void> _openLocationSettings() async {
    await Geolocator.openLocationSettings();
    if (!mounted) return;
    unawaited(_checkLocation(requestPermission: true));
  }

  Future<void> _requestPermission() async {
    if (_permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
    } else {
      await Geolocator.requestPermission();
    }
    if (!mounted) return;
    unawaited(_checkLocation());
  }

  @override
  Widget build(BuildContext context) {
    if (_canUseApp) return widget.child;

    final theme = Theme.of(context);
    final needsService = !_serviceEnabled;
    final title = needsService
        ? 'Lokacija je isključena'
        : 'Dozvola za lokaciju je potrebna';
    final message = needsService
        ? 'Aplikacija se ne može koristiti dok lokacija nije uključena.'
        : 'Očitavanje mora imati lokaciju, zato dozvoli pristup lokaciji za ovu aplikaciju.';

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
                    Icons.location_off_outlined,
                    size: 64,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _isChecking
                        ? null
                        : needsService
                        ? _openLocationSettings
                        : _requestPermission,
                    icon: _isChecking
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            needsService
                                ? Icons.settings_outlined
                                : Icons.my_location_outlined,
                          ),
                    label: Text(
                      needsService ? 'Uključi lokaciju' : 'Dozvoli lokaciju',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: _isChecking
                        ? null
                        : () => unawaited(
                            _checkLocation(requestPermission: true),
                          ),
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
}
