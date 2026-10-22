import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vodovod_bd_flutter/src/core/app_logger.dart';
import 'package:vodovod_bd_flutter/src/core/diagnostics_delivery.dart';

void main() {
  late Directory directory;
  late DiagnosticOutbox outbox;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vob-outbox-');
    outbox = DiagnosticOutbox(() async => directory);
  });
  tearDown(() => directory.delete(recursive: true));

  Future<Map<String, Object?>> event([
    String message = 'Greška očitavanja',
  ]) async => {
    'eventId': diagnosticUuid(),
    'installationId': await outbox.installationId(),
    'occurredAtUtc': '2026-10-22T10:00:00.000Z',
    'inkasantId': '37',
    'appVersion': '1.9.10',
    'buildNumber': 100,
    'platform': 'android',
    'osVersion': 'Android 14',
    'level': 'error',
    'operation': 'Čuvanje',
    'message': message,
    'stackTrace': 'at test',
  };
  Set<String> ids(List<Map<String, Object?>> events) =>
      events.map((e) => e['eventId'] as String).toSet();

  test(
    'queue and installation survive restart and duplicate enqueue does not overwrite',
    () async {
      final first = await event();
      await outbox.enqueue(first);
      await outbox.enqueue({...first, 'message': 'Must not replace'});
      await Future.wait(
        List.generate(30, (i) async => outbox.enqueue(await event('Error $i'))),
      );
      final restarted = DiagnosticOutbox(() async => directory);
      expect(await restarted.count(), 31);
      expect(await restarted.installationId(), first['installationId']);
      final stored = await restarted.batch(limit: 100);
      expect(
        stored.singleWhere((e) => e['eventId'] == first['eventId']),
        first,
      );
    },
  );

  test('server failures retain pending errors across restart', () async {
    final item = await event();
    await outbox.enqueue(item);
    final uploader = DiagnosticUploader(
      outbox,
      (_) async => throw const HttpException('HTTP 500'),
    );
    await uploader.flush();
    expect(uploader.status.value.error, contains('500'));
    expect(uploader.status.value.sending, false);
    final restarted = DiagnosticOutbox(() async => directory);
    expect((await restarted.batch()).single, item);
    final retry = DiagnosticUploader(restarted, (events) async => ids(events));
    await retry.flush();
    expect(await restarted.count(), 0);
    expect(retry.status.value.lastSent, isNotNull);
    final next = DiagnosticUploader(restarted, (_) async => {});
    await next.refreshStatus();
    expect(
      next.status.value.lastSent!.toUtc(),
      retry.status.value.lastSent!.toUtc(),
    );
  });

  test(
    'lost acknowledgement retries the same ID without a second server event',
    () async {
      final server = <String, Map<String, Object?>>{};
      await outbox.enqueue(await event());
      var dropResponse = true;
      Future<Set<String>> send(List<Map<String, Object?>> events) async {
        for (final e in events) {
          server.putIfAbsent(e['eventId'] as String, () => e);
        }
        if (dropResponse) throw TimeoutException('Reply lost after commit');
        return ids(events);
      }

      await DiagnosticUploader(outbox, send).flush();
      expect(await outbox.count(), 1);
      dropResponse = false;
      await DiagnosticUploader(
        DiagnosticOutbox(() async => directory),
        send,
      ).flush();
      expect(server.length, 1);
      expect(await outbox.count(), 0);
    },
  );

  test('only explicitly acknowledged IDs are removed', () async {
    final first = await event('one');
    final second = await event('two');
    await outbox.enqueue(first);
    await outbox.enqueue(second);
    await DiagnosticUploader(
      outbox,
      (_) async => {first['eventId'] as String},
    ).flush();
    expect((await outbox.batch()).single, second);
    await DiagnosticUploader(outbox, (_) async => {diagnosticUuid()}).flush();
    expect((await outbox.batch()).single, second);
    await DiagnosticUploader(outbox, (_) async => {}).flush();
    expect(await outbox.count(), 1);
  });

  test(
    'one upload at a time; a new error during upload is retained and then sent',
    () async {
      final response = Completer<Set<String>>();
      final started = Completer<void>();
      final first = await event();
      await outbox.enqueue(first);
      var calls = 0;
      final uploader = DiagnosticUploader(outbox, (events) {
        calls++;
        if (calls == 1) {
          started.complete();
          return response.future;
        }
        return Future.value(ids(events));
      });
      final a = uploader.flush();
      await started.future;
      final b = uploader.flush(force: true);
      await outbox.enqueue(await event('During upload'));
      expect(calls, 1);
      response.complete({first['eventId'] as String});
      await Future.wait([a, b]);
      expect(calls, 2);
      expect(await outbox.count(), 0);
    },
  );

  test(
    'retry backoff prevents continuous network calls, explicit retry bypasses it',
    () async {
      var time = DateTime.utc(2026);
      var calls = 0;
      await outbox.enqueue(await event());
      final uploader = DiagnosticUploader(outbox, (_) async {
        calls++;
        throw const SocketException('Offline');
      }, now: () => time);
      await uploader.flush();
      await uploader.flush();
      expect(calls, 1);
      time = time.add(const Duration(minutes: 1));
      await uploader.flush();
      expect(calls, 2);
      await uploader.flush(force: true);
      expect(calls, 3);
      expect(await outbox.count(), 1);
    },
  );

  test(
    'flushed partial files recover; corrupt files are not deleted or block valid events',
    () async {
      final item = await event();
      final pending = await Directory('${directory.path}/pending').create();
      final partial = File('${pending.path}/${item['eventId']}.json.part');
      await partial.writeAsString(jsonEncode(item));
      final broken = File('${pending.path}/${diagnosticUuid()}.json');
      await broken.writeAsString('{');
      final uploader = DiagnosticUploader(
        outbox,
        (events) async => ids(events),
      );
      await uploader.flush();
      expect(await partial.exists(), false);
      expect(await broken.exists(), true);
      expect(await outbox.count(), 1);
      expect(uploader.status.value.error, contains('nečitljive'));
    },
  );

  test('log rotation does not rotate or discard unsent errors', () async {
    final log = DiagnosticLogStore(
      () async => Directory('${directory.path}/log'),
      maxFileBytes: 400,
    );
    for (var i = 0; i < 20; i++) {
      await outbox.enqueue(await event('Error $i'));
      await log.append(
        DiagnosticEntry(
          time: DateTime.now(),
          level: 'error',
          message: 'Error $i',
        ),
      );
    }
    expect((await log.read()).length, lessThan(20));
    expect(await outbox.count(), 20);
  });

  test('large backlog is bounded to three batches per run', () async {
    for (var i = 0; i < 65; i++) {
      await outbox.enqueue(await event());
    }
    var calls = 0;
    final uploader = DiagnosticUploader(outbox, (events) async {
      expect(events.length, lessThanOrEqualTo(20));
      calls++;
      return ids(events);
    });
    await uploader.flush();
    expect(calls, 3);
    expect(await outbox.count(), 5);
    await uploader.flush();
    expect(await outbox.count(), 0);
  });

  test(
    'HTTP sends UTF-8 with key, verifies ACK and refuses redirects',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var mode = 'ok';
      server.listen((request) async {
        expect(request.headers.value('X-Diagnostics-Key'), 'test-only-key');
        final body =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        expect((body['events'] as List).first['message'], 'Greška očitavanja');
        if (mode == 'redirect') {
          request.response.statusCode = 302;
          request.response.headers.set(
            'Location',
            'http://127.0.0.1:${server.port}/unexpected',
          );
        } else if (mode == 'invalid') {
          request.response.write('{"acceptedEventIds":["wrong-id"]}');
        } else {
          request.response.write(
            jsonEncode({
              'acceptedEventIds': (body['events'] as List)
                  .map((e) => e['eventId'])
                  .toList(),
            }),
          );
        }
        await request.response.close();
      });
      final sender = DiagnosticHttpSender(
        Uri.parse('http://127.0.0.1:${server.port}/api/app-errors/batch'),
        'test-only-key',
      );
      final item = await event();
      expect(await sender.send([item]), {item['eventId']});
      mode = 'invalid';
      await expectLater(sender.send([item]), throwsFormatException);
      mode = 'redirect';
      await expectLater(sender.send([item]), throwsA(isA<HttpException>()));
    },
  );

  test('HTTP timeout leaves the queue untouched', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await request.drain<void>();
    });
    final sender = DiagnosticHttpSender(
      Uri.parse('http://127.0.0.1:${server.port}/batch'),
      'key',
      timeout: const Duration(milliseconds: 100),
    );
    await outbox.enqueue(await event());
    final uploader = DiagnosticUploader(outbox, sender.send);
    await uploader.flush();
    expect(await outbox.count(), 1);
    expect(uploader.status.value.error, contains('na vrijeme'));
  });
}
