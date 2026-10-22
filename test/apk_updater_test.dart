import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vodovod_bd_flutter/src/core/apk_updater.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late HttpServer server;
  late ApkUpdater updater;
  late List<MethodCall> calls;
  late HttpOverrides? originalHttpOverrides;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() async {
    originalHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    directory = await Directory.systemTemp.createTemp('vob-apk-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    updater = ApkUpdater(directory: () async => directory);
    calls = [];
    messenger.setMockMethodCallHandler(ApkUpdater.channel, (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() async {
    updater.cancel();
    await server.close(force: true);
    await directory.delete(recursive: true);
    messenger.setMockMethodCallHandler(ApkUpdater.channel, null);
    HttpOverrides.global = originalHttpOverrides;
  });

  Future<File> download({void Function(int, int?)? onProgress}) =>
      updater.download(
        url: 'http://127.0.0.1:${server.port}/app.apk',
        versionCode: 101,
        onProgress: onProgress ?? (_, _) {},
      );

  test(
    'streams, validates and reuses a complete APK without redownloading',
    () async {
      var requests = 0;
      server.listen((request) async {
        requests++;
        request.response.contentLength = 4;
        request.response.add([80, 75, 3, 4]);
        await request.response.close();
      });
      var received = 0;
      final file = await download(onProgress: (count, _) => received = count);
      expect(await file.readAsBytes(), [80, 75, 3, 4]);
      expect(received, 4);
      expect(calls.single.method, 'validateApk');
      expect(calls.single.arguments['versionCode'], 101);
      expect(await File('${file.path}.part').exists(), false);
      expect((await download()).path, file.path);
      expect(requests, 1);
    },
  );

  test('a server error cannot become an installable file', () async {
    server.listen((request) async {
      request.response.statusCode = 500;
      request.response.write('server error');
      await request.response.close();
    });
    await expectLater(download(), throwsA(isA<HttpException>()));
    expect(
      await Directory('${directory.path}/updates').list().toList(),
      isEmpty,
    );
    expect(calls, isEmpty);
  });

  test('invalid APK/package/signature removes partial data', () async {
    server.listen((request) async {
      request.response.write('<html>not an APK</html>');
      await request.response.close();
    });
    messenger.setMockMethodCallHandler(ApkUpdater.channel, (_) async {
      throw PlatformException(code: 'invalid_apk');
    });
    await expectLater(download(), throwsA(isA<PlatformException>()));
    expect(
      await Directory('${directory.path}/updates').list().toList(),
      isEmpty,
    );
  });

  test('truncated HTTP response is never offered for installation', () async {
    server.listen((request) async {
      final socket = await request.response.detachSocket(writeHeaders: false);
      socket.write(
        'HTTP/1.1 200 OK\r\nContent-Length: 100\r\nConnection: close\r\n\r\nPK',
      );
      await socket.flush();
      socket.destroy();
    });
    await expectLater(download(), throwsA(anything));
    expect(calls, isEmpty);
    expect(
      await Directory('${directory.path}/updates').list().toList(),
      isEmpty,
    );
  });

  test('cancel removes partial file and allows a later retry', () async {
    server.listen((request) async {
      request.response.add([80, 75, 3, 4]);
      await request.response.close();
    });
    await expectLater(
      download(onProgress: (_, _) => updater.cancel()),
      throwsA(isA<UpdateCancelled>()),
    );
    expect(
      await Directory('${directory.path}/updates').list().toList(),
      isEmpty,
    );
    expect(await (await download()).exists(), true);
  });
}
