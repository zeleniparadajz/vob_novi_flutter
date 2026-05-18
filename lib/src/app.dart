import 'dart:async';

import 'package:flutter/material.dart';

import 'data/demo_repository.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/location_gate.dart';
import 'widgets/update_gate.dart';

class VodovodApp extends StatefulWidget {
  const VodovodApp({super.key});

  @override
  State<VodovodApp> createState() => _VodovodAppState();
}

class _VodovodAppState extends State<VodovodApp> with WidgetsBindingObserver {
  final repository = DemoVodovodRepository();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(repository.syncPendingNow(reason: 'app_resumed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VOB Ocitavanje',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: UpdateGate(
        repository: repository,
        child: LocationGate(child: LoginScreen(repository: repository)),
      ),
    );
  }
}
