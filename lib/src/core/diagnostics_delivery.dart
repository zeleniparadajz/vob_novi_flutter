import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

String diagnosticUuid() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

// Independent from reading/import tables and from the rotating local log.
class DiagnosticOutbox {
  DiagnosticOutbox(this.directory);
  final Future<Directory> Function() directory;
  Future<void> _pending = Future.value();

  Future<T> _serial<T>(Future<T> Function(Directory) action) {
    final operation = _pending.then((_) async {
      final dir = await directory();
      await dir.create(recursive: true);
      return action(dir);
    });
    _pending = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> _atomic(File file, String value) async {
    final partial = File('${file.path}.part');
    await partial.writeAsString(value, flush: true);
    await partial.rename(file.path);
  }

  Future<String> installationId() => _serial((dir) async {
    final file = File('${dir.path}/installation-id');
    if (await file.exists()) {
      final value = (await file.readAsString()).trim();
      if (_uuidPattern.hasMatch(value)) return value;
      throw const FormatException('Neispravan identifikator dijagnostike.');
    }
    final partial = File('${file.path}.part');
    if (await partial.exists()) {
      final value = (await partial.readAsString()).trim();
      if (_uuidPattern.hasMatch(value)) {
        await partial.rename(file.path);
        return value;
      }
    }
    final value = diagnosticUuid();
    await _atomic(file, value);
    return value;
  });

  Future<void> enqueue(Map<String, Object?> event) => _serial((dir) async {
    final id = event['eventId'] as String;
    if (!_uuidPattern.hasMatch(id)) {
      throw const FormatException('Invalid event ID');
    }
    final pending = Directory('${dir.path}/pending');
    await pending.create(recursive: true);
    final file = File('${pending.path}/$id.json');
    if (!await file.exists()) await _atomic(file, jsonEncode(event));
  });

  Future<List<Map<String, Object?>>> batch({int limit = 20}) => _serial((
    dir,
  ) async {
    final pending = Directory('${dir.path}/pending');
    if (!await pending.exists()) return [];
    final events = <Map<String, Object?>>[];
    final seenIds = <String>{};
    await for (final file in pending.list()) {
      if (file is! File) continue;
      final partial = file.path.endsWith('.json.part');
      if (!partial && !file.path.endsWith('.json')) continue;
      try {
        final event =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final id = event['eventId'];
        if (id is! String || !_uuidPattern.hasMatch(id)) continue;
        final target = '${pending.path}/$id.json';
        if (file.path != target && file.path != '$target.part') continue;
        // Recover a completely flushed event if termination preceded the rename.
        if (partial) {
          if (await File(target).exists()) continue;
          await file.rename(target);
        }
        if (!seenIds.add(id)) continue;
        events.add(event);
        if (events.length >= limit) break;
      } on FormatException {
        // Preserve damaged records for investigation; other records still upload.
      } on TypeError {
        // Never delete an entry just because it cannot be decoded.
      }
    }
    return events;
  });

  Future<void> acknowledge(Set<String> ids) => _serial((dir) async {
    for (final id in ids) {
      if (!_uuidPattern.hasMatch(id)) {
        throw const FormatException('Invalid ACK');
      }
      final file = File('${dir.path}/pending/$id.json');
      if (await file.exists()) await file.delete();
    }
  });

  Future<int> count() => _serial((dir) async {
    final pending = Directory('${dir.path}/pending');
    if (!await pending.exists()) return 0;
    var count = 0;
    await for (final file in pending.list()) {
      if (file is File &&
          (file.path.endsWith('.json') || file.path.endsWith('.json.part'))) {
        count++;
      }
    }
    return count;
  });

  Future<String?> readValue(String key) => _serial((dir) async {
    final file = File('${dir.path}/$key');
    return await file.exists() ? await file.readAsString() : null;
  });

  Future<void> writeValue(String key, String value) =>
      _serial((dir) => _atomic(File('${dir.path}/$key'), value));
}

typedef DiagnosticSender =
    Future<Set<String>> Function(List<Map<String, Object?>> events);

class DiagnosticHttpSender {
  DiagnosticHttpSender(
    this.endpoint,
    this.key, {
    this.timeout = const Duration(seconds: 12),
  });
  final Uri endpoint;
  final String key;
  final Duration timeout;

  Future<Set<String>> send(List<Map<String, Object?>> events) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      return await (() async {
        final request = await client.postUrl(endpoint);
        request.followRedirects = false;
        request.headers.contentType = ContentType.json;
        request.headers.set('X-Diagnostics-Key', key);
        request.add(utf8.encode(jsonEncode({'events': events})));
        final response = await request.close();
        if (response.statusCode != 200) {
          throw HttpException(
            'Slanje dijagnostike: HTTP ${response.statusCode}.',
          );
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
          if (bytes.length > 65536) {
            throw const FormatException('Prevelika potvrda servera.');
          }
        }
        final body = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        final accepted = (body['acceptedEventIds'] as List)
            .cast<String>()
            .toSet();
        final requested = events.map((e) => e['eventId']).toSet();
        if (!accepted.every(requested.contains)) {
          throw const FormatException(
            'Server je vratio nepoznate identifikatore.',
          );
        }
        return accepted;
      })().timeout(timeout);
    } finally {
      client.close(force: true);
    }
  }
}

class DiagnosticDeliveryStatus {
  const DiagnosticDeliveryStatus({
    this.pending = 0,
    this.sending = false,
    this.lastSent,
    this.error,
  });
  final int pending;
  final bool sending;
  final DateTime? lastSent;
  final String? error;
}

class DiagnosticUploader {
  DiagnosticUploader(this.outbox, this.send, {DateTime Function()? now})
    : now = now ?? DateTime.now;
  final DiagnosticOutbox outbox;
  final DiagnosticSender send;
  final DateTime Function() now;
  final status = ValueNotifier(const DiagnosticDeliveryStatus());
  Future<void>? _active;
  DateTime? _retryAfter;
  int _failures = 0;

  Future<void> refreshStatus() async {
    status.value = DiagnosticDeliveryStatus(
      pending: await outbox.count(),
      sending: status.value.sending,
      lastSent:
          status.value.lastSent ??
          DateTime.tryParse(await outbox.readValue('last-sent') ?? ''),
      error: status.value.error,
    );
  }

  Future<void> flush({bool force = false}) {
    if (_active != null) return _active!;
    final future = _flush(force);
    _active = future;
    // _flush catches failures; delivery failures must not feed the error outbox.
    return future.whenComplete(() => _active = null);
  }

  Future<void> _flush(bool force) async {
    try {
      await refreshStatus();
      if (!force && _retryAfter != null && now().isBefore(_retryAfter!)) return;
      if (status.value.pending == 0) return;
      status.value = DiagnosticDeliveryStatus(
        pending: status.value.pending,
        sending: true,
        lastSent: status.value.lastSent,
      );
      // Bound each run so a large backlog cannot monopolize fieldwork traffic.
      for (var batchNumber = 0; batchNumber < 3; batchNumber++) {
        final candidates = await outbox.batch();
        final events = <Map<String, Object?>>[];
        var bytes = 32;
        for (final event in candidates) {
          final size = utf8.encode(jsonEncode(event)).length + 1;
          if (bytes + size > 900000) break;
          events.add(event);
          bytes += size;
        }
        if (events.isEmpty) {
          throw const FormatException('Red sadrži nečitljive zapise.');
        }
        final accepted = await send(events);
        final requested = events.map((e) => e['eventId'] as String).toSet();
        if (!accepted.every(requested.contains)) {
          throw const FormatException('Neispravna potvrda servera.');
        }
        await outbox.acknowledge(accepted);
        if (accepted.isNotEmpty) {
          final time = now();
          await outbox.writeValue('last-sent', time.toUtc().toIso8601String());
          status.value = DiagnosticDeliveryStatus(
            lastSent: time,
            sending: true,
          );
        }
        if (accepted.length != events.length) {
          throw const FormatException('Server nije potvrdio sve greške.');
        }
        if (await outbox.count() == 0) break;
      }
      _failures = 0;
      _retryAfter = null;
      status.value = DiagnosticDeliveryStatus(
        pending: await outbox.count(),
        lastSent: status.value.lastSent,
      );
    } catch (error) {
      _failures = min(_failures + 1, 6);
      _retryAfter = now().add(
        Duration(seconds: min(30 * (1 << _failures), 1200)),
      );
      status.value = DiagnosticDeliveryStatus(
        pending: status.value.pending,
        lastSent: status.value.lastSent,
        error: 'Greške ostaju na telefonu. ${_failureMessage(error)}',
      );
      try {
        await refreshStatus();
      } catch (_) {
        /* Storage itself may be unavailable. */
      }
    }
  }

  static String _failureMessage(Object error) {
    if (error is HttpException) return error.message;
    if (error is TimeoutException) return 'Server nije odgovorio na vrijeme.';
    if (error is SocketException) return 'Veza sa serverom nije dostupna.';
    if (error is FormatException) return error.message;
    return 'Slanje nije potvrđeno (${error.runtimeType}).';
  }
}
