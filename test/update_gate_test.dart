import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:vodovod_bd_flutter/src/core/apk_updater.dart';
import 'package:vodovod_bd_flutter/src/data/demo_repository.dart';
import 'package:vodovod_bd_flutter/src/widgets/update_gate.dart';

class UpdateRepository extends DemoVodovodRepository {
  bool offline = false;
  @override
  Future<AppUpdateInfo?> requiredUpdate(int currentBuildNumber) async {
    if (offline) throw const SocketException('offline');
    return const AppUpdateInfo(
      versionCode: 101,
      versionName: '1.9.11',
      apkUrl: 'https://example.test/app.apk',
    );
  }
}

class FakeUpdater extends ApkUpdater {
  int downloads = 0;
  int installs = 0;
  String result = 'permission_required';
  Completer<File>? pending;

  @override
  Future<File> download({
    required String url,
    required int versionCode,
    required void Function(int, int?) onProgress,
  }) async {
    downloads++;
    onProgress(5, 10);
    return pending == null ? File('/tmp/update.apk') : await pending!.future;
  }

  @override
  Future<String> install(File file, int versionCode) async {
    installs++;
    return result;
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late UpdateRepository repository;
  late FakeUpdater updater;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'VOB',
      packageName: 'com.vodovodbd.vodovod_bd_flutter',
      version: '1.9.10',
      buildNumber: '100',
      buildSignature: '',
    );
    repository = UpdateRepository();
    updater = FakeUpdater();
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(ApkUpdater.channel, null);
  });

  Future<void> show(WidgetTester tester, {bool alwaysShow = true}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UpdateGate(
          repository: repository,
          updater: updater,
          alwaysShow: alwaysShow,
          child: const Text('Očitavanja'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> resume(WidgetTester tester) async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  }

  testWidgets('permission grant opens installer without downloading twice', (
    tester,
  ) async {
    messenger.setMockMethodCallHandler(ApkUpdater.channel, (_) async => true);
    await show(tester);
    await tester.tap(find.text('Preuzmi i instaliraj'));
    await tester.pumpAndSettle();
    expect(updater.downloads, 1);
    expect(updater.installs, 1);
    updater.result = 'installer_opened';
    await resume(tester);
    expect(updater.downloads, 1);
    expect(updater.installs, 2);
    await resume(tester);
    expect(updater.installs, 2);
    expect(find.text('Instaliraj'), findsOneWidget);
  });

  testWidgets('denied permission does not loop back into settings', (
    tester,
  ) async {
    messenger.setMockMethodCallHandler(ApkUpdater.channel, (_) async => false);
    await show(tester);
    await tester.tap(find.text('Preuzmi i instaliraj'));
    await tester.pumpAndSettle();
    await resume(tester);
    await resume(tester);
    expect(updater.installs, 1);
    expect(find.textContaining('Instalacija nije dozvoljena'), findsOneWidget);
  });

  testWidgets('offline check still permits startup field work', (tester) async {
    repository.offline = true;
    await show(tester, alwaysShow: false);
    expect(find.text('Očitavanja'), findsOneWidget);
  });

  testWidgets(
    'download progress fits a narrow Android viewport with larger text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      updater.pending = Completer<File>();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: UpdateGate(
            repository: repository,
            updater: updater,
            alwaysShow: true,
            child: const SizedBox(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Preuzmi i instaliraj'));
      await tester.tap(find.text('Preuzmi i instaliraj'));
      await tester.pump();
      expect(find.textContaining('50%'), findsOneWidget);
      expect(tester.takeException(), isNull);
      updater.pending!.complete(File('/tmp/update.apk'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
