import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:vodovod_bd_flutter/src/core/app_logger.dart';
import 'package:vodovod_bd_flutter/src/core/diagnostics_delivery.dart';
import 'package:vodovod_bd_flutter/src/screens/diagnostics_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'logger queues scrubbed errors, imports old versions once, and shows upload status',
    (tester) async {
      final root = await tester.runAsync(
        () => Directory.systemTemp.createTemp('vob-logger-integration-'),
      );
      addTearDown(() => root!.delete(recursive: true));
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(paths, (_) async => root!.path);
      addTearDown(() => messenger.setMockMethodCallHandler(paths, null));
      PackageInfo.setMockInitialValues(
        appName: 'VOB',
        packageName: 'com.test.vob',
        version: '1.9.10',
        buildNumber: '100',
        buildSignature: '',
      );
      await tester.runAsync(() async {
        final outbox = DiagnosticOutbox(
          () async => Directory('${root!.path}/diagnostics/delivery'),
        );
        final oldLog = DiagnosticLogStore(
          () async => Directory('${root!.path}/diagnostics'),
        );
        await oldLog.append(
          DiagnosticEntry(
            time: DateTime.utc(2026, 9, 1),
            level: 'error',
            message: 'Ranija greska',
            version: '1.9.8+98 (android)',
            userId: '12',
          ),
        );
        AppLogger.userId = '37';
        final saving = AppLogger.error(
          'Nova greska',
          'password=secret {"potrosac":"PRIVATE"}',
          StackTrace.current,
        );
        AppLogger.userId = '88';
        await saving;
        await AppLogger.log('Rutinski dogadjaj');
        await AppLogger.sendPending();
        final events = await outbox.batch();
        expect(events.length, 2);
        final recent = events.singleWhere((e) => e['message'] == 'Nova greska');
        expect(recent['inkasantId'], '37');
        expect(recent['appVersion'], '1.9.10');
        expect(recent['buildNumber'], 100);
        expect(recent['stackTrace'], isNot(contains('secret')));
        expect(recent['stackTrace'], isNot(contains('PRIVATE')));
        final old = events.singleWhere((e) => e['message'] == 'Ranija greska');
        expect(old['appVersion'], '1.9.8');
        expect(old['buildNumber'], 98);
        expect(old['inkasantId'], '12');
        final originalIds = events.map((e) => e['eventId']).toSet();
        await AppLogger.sendPending(force: true);
        expect(
          (await outbox.batch()).map((e) => e['eventId']).toSet(),
          originalIds,
        );
      });

      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.2)),
            child: child!,
          ),
          home: const DiagnosticsScreen(),
        ),
      );
      for (
        var attempt = 0;
        attempt < 100 && find.text('Nova greska').evaluate().isEmpty;
        attempt++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.text('Nova greska'), findsOneWidget);
      expect(find.text('Greške za slanje: 2'), findsOneWidget);
      expect(find.textContaining('nije podešeno'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
