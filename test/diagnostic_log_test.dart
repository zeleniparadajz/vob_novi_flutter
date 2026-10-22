import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vodovod_bd_flutter/src/core/app_logger.dart';

void main() {
  late Directory directory;
  setUp(
    () async => directory = await Directory.systemTemp.createTemp('vob-log-'),
  );
  tearDown(() async => directory.delete(recursive: true));

  DiagnosticEntry entry(int i) => DiagnosticEntry(
    time: DateTime.utc(2026, 10, 22, 10, 0, i),
    level: i.isEven ? 'info' : 'error',
    message: 'Event $i',
    details: 'Details $i',
    userId: '37',
    version: '1.9.10+100',
  );

  test('concurrent events persist and can be read after a restart', () async {
    final log = DiagnosticLogStore(() async => directory);
    await Future.wait(List.generate(40, (i) => log.append(entry(i))));
    final restored = await DiagnosticLogStore(() async => directory).read();
    expect(restored.length, 40);
    expect(restored.first.message, 'Event 39');
    expect(restored.last.userId, '37');
    expect(restored.first.version, '1.9.10+100');
  });

  test('rotation bounds storage and preserves newest events', () async {
    final log = DiagnosticLogStore(() async => directory, maxFileBytes: 500);
    for (var i = 0; i < 20; i++) {
      await log.append(entry(i));
    }
    final files = await directory.list().toList();
    expect(files.length, 2);
    for (final file in files.cast<File>()) {
      expect(await file.length(), lessThanOrEqualTo(500));
    }
    expect((await log.read()).first.message, 'Event 19');
  });

  test('an interrupted final line does not hide earlier errors', () async {
    final log = DiagnosticLogStore(() async => directory);
    await log.append(entry(1));
    await File(
      '${directory.path}/events.jsonl',
    ).writeAsString('{"time":', mode: FileMode.append);
    expect((await log.read()).single.message, 'Event 1');
    final restarted = DiagnosticLogStore(() async => directory);
    await restarted.append(entry(2));
    expect((await restarted.read()).map((event) => event.message), [
      'Event 2',
      'Event 1',
    ]);
  });

  test('secrets and URL query parameters are removed', () {
    final result = AppLogger.sanitize(
      'password=secret "lozinka":"tajna" Authorization: Bearer abc.def.xyz\n'
      'https://server/api?token=abc&password=def https://name:pass@server/api',
    );
    for (final secret in [
      'secret',
      'tajna',
      'abc.def.xyz',
      'token=abc',
      'name:pass',
    ]) {
      expect(result, isNot(contains(secret)));
    }
  });
}
