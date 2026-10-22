import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/core/app_logger.dart';
export 'src/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(
      AppLogger.error('Flutter greška', details.exception, details.stack),
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(AppLogger.error('Neočekivana greška', error, stack));
    return true;
  };
  unawaited(AppLogger.log('Pokretanje aplikacije'));
  AppLogger.start();
  runApp(const VodovodApp());
}
