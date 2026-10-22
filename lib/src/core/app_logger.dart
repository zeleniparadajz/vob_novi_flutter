import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'app_config.dart';
import 'diagnostics_delivery.dart';

class DiagnosticEntry {
  const DiagnosticEntry({
    required this.time,
    required this.level,
    required this.message,
    this.details = '',
    this.userId,
    this.version = '',
    this.eventId,
  });

  final DateTime time;
  final String level;
  final String message;
  final String details;
  final String? userId;
  final String version;
  final String? eventId;

  Map<String, Object?> toJson() => {
    'time': time.toUtc().toIso8601String(),
    'level': level,
    'message': message,
    'details': details,
    'userId': userId,
    'version': version,
    if (eventId != null) 'eventId': eventId,
  };

  factory DiagnosticEntry.fromJson(Map<String, dynamic> json) =>
      DiagnosticEntry(
        time: DateTime.parse(json['time'] as String).toLocal(),
        level: json['level'] as String,
        message: json['message'] as String,
        details: json['details'] as String? ?? '',
        userId: json['userId'] as String?,
        version: json['version'] as String? ?? '',
        eventId: json['eventId'] as String?,
      );

  String get report =>
      '${time.toIso8601String()} [$level] $message\n'
      'Verzija: $version | Inkasant: ${userId ?? "-"}\n'
      '${eventId == null ? "" : "ID greske: $eventId\n"}$details';
}

// Serialize writes and rotation so simultaneous sync/UI errors cannot mix lines.
class DiagnosticLogStore {
  DiagnosticLogStore(this.directory, {this.maxFileBytes = 512 * 1024});
  final Future<Directory> Function() directory;
  final int maxFileBytes;
  Future<void> _pending = Future.value();
  bool _tailChecked = false;

  Future<void> append(DiagnosticEntry entry) {
    final operation = _pending.then((_) async {
      final dir = await directory();
      await dir.create(recursive: true);
      final file = File('${dir.path}/events.jsonl');
      if (!_tailChecked && await file.exists() && await file.length() > 0) {
        final handle = await file.open();
        int lastByte;
        try {
          await handle.setPosition(await handle.length() - 1);
          lastByte = await handle.readByte();
        } finally {
          await handle.close();
        }
        // Separate a partially written record from the first new record after restart.
        if (lastByte != 10) {
          await file.writeAsString('\n', mode: FileMode.append);
        }
      }
      _tailChecked = true;
      final bytes = utf8.encode('${jsonEncode(entry.toJson())}\n');
      if (await file.exists() &&
          await file.length() + bytes.length > maxFileBytes) {
        final previous = File('${dir.path}/events.previous.jsonl');
        if (await previous.exists()) await previous.delete();
        await file.rename(previous.path);
      }
      await file.writeAsBytes(bytes, mode: FileMode.append, flush: true);
    });
    _pending = operation.catchError((Object _) {});
    return operation;
  }

  Future<List<DiagnosticEntry>> read() {
    final operation = _pending.then((_) async {
      final dir = await directory();
      final entries = <DiagnosticEntry>[];
      for (final name in ['events.previous.jsonl', 'events.jsonl']) {
        final file = File('${dir.path}/$name');
        if (!await file.exists()) continue;
        final lines = const LineSplitter().convert(
          utf8.decode(await file.readAsBytes(), allowMalformed: true),
        );
        for (final line in lines) {
          try {
            entries.add(
              DiagnosticEntry.fromJson(
                jsonDecode(line) as Map<String, dynamic>,
              ),
            );
          } on FormatException {
            // A process interruption may leave only the final line incomplete.
          } on TypeError {
            // Keep the remaining entries if an older record has a bad shape.
          }
        }
      }
      return entries.reversed.toList();
    });
    _pending = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }
}

class AppLogger {
  static final _store = DiagnosticLogStore(() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/diagnostics');
  });
  static final _outbox = DiagnosticOutbox(() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/diagnostics/delivery');
  });
  static final _uploader = DiagnosticUploader(
    _outbox,
    DiagnosticHttpSender(
      Uri.parse('${AppConfig.diagnosticsBaseUrl}${AppConfig.diagnosticsPath}'),
      AppConfig.diagnosticsKey,
    ).send,
  );
  static const _native = MethodChannel('com.vodovodbd/diagnostics');
  static ValueListenable<DiagnosticDeliveryStatus> get delivery =>
      _uploader.status;
  static bool get uploadConfigured => AppConfig.diagnosticsKey.length >= 32;
  static Timer? _timer;
  static Timer? _debounce;
  static Future<void>? _initializing;
  static String? _userId;
  static String? get userId => _userId;
  static set userId(String? value) {
    _userId = value;
    unawaited(_updateNativeContext());
  }

  static String? writeFailure;
  static Future<String>? _version;
  static Future<PackageInfo?>? _packageInfo;
  static final _reportedImageFailures = <String>{};

  static void imageError(String resource, Object error, StackTrace? stack) {
    // errorBuilder can run repeatedly for the same failed image during rebuilds.
    final key = '$resource|$error';
    if (!_reportedImageFailures.add(key)) return;
    if (_reportedImageFailures.length > 256) {
      _reportedImageFailures.remove(_reportedImageFailures.first);
    }
    unawaited(AppLogger.error('Prikaz slike', '$resource: $error', stack));
  }

  static Future<PackageInfo?> _info() => _packageInfo ??= () async {
    try {
      return await PackageInfo.fromPlatform();
    } catch (_) {
      return null;
    }
  }();

  static Future<String> _appVersion() => _version ??= () async {
    try {
      final info = await _info();
      if (info == null) return Platform.operatingSystem;
      return '${info.version}+${info.buildNumber} (${Platform.operatingSystem})';
    } catch (_) {
      return Platform.operatingSystem;
    }
  }();

  static Future<void> log(String message) => _write('info', message, '');
  static Future<void> error(
    String message,
    Object error, [
    StackTrace? stack,
  ]) => _write('error', message, '$error${stack == null ? "" : "\n$stack"}');

  static Future<void> _write(
    String level,
    String message,
    String details,
  ) async {
    final time = DateTime.now();
    final inkasant = userId;
    try {
      final entry = DiagnosticEntry(
        time: time,
        level: level,
        message: sanitize(message),
        details: sanitize(details),
        userId: inkasant,
        version: await _appVersion(),
        eventId: level == 'error' ? diagnosticUuid() : null,
      );
      // Persist delivery first: rotating the visible log must never drop pending errors.
      if (level == 'error') await _enqueue(entry);
      await _store.append(entry);
      writeFailure = null;
      if (level == 'error' && _timer != null) _scheduleUpload();
    } catch (_) {
      writeFailure = 'Dnevnik nije moguće sačuvati na telefonu.';
      debugPrint(writeFailure);
    }
  }

  static Future<void> _enqueue(
    DiagnosticEntry entry, {
    Map<String, dynamic>? native,
  }) async {
    final recordedVersion = RegExp(
      r'^([^+ ]+)\+(\d+)',
    ).firstMatch(entry.version);
    await _outbox.enqueue({
      'eventId': entry.eventId!,
      'installationId': await _outbox.installationId(),
      'occurredAtUtc': entry.time.toUtc().toIso8601String(),
      'inkasantId': entry.userId == null ? null : _limit(entry.userId!, 64),
      'appVersion': _limit(
        native?['appVersion'] as String? ??
            recordedVersion?.group(1) ??
            'unknown',
        32,
      ),
      'buildNumber':
          native?['buildNumber'] ??
          int.tryParse(recordedVersion?.group(2) ?? '') ??
          0,
      'platform': Platform.operatingSystem,
      'osVersion': _limit(Platform.operatingSystemVersion, 64),
      'level': entry.level,
      'operation': _limit(sanitize(entry.message), 128),
      'message': sanitize(entry.message),
      'stackTrace': sanitize(entry.details),
    });
  }

  static String _limit(String value, int max) =>
      value.length <= max ? value : value.substring(0, max);

  static void start() {
    if (_timer != null) return;
    _native.setMethodCallHandler((call) async {
      if (call.method == 'networkAvailable') _scheduleUpload(force: true);
    });
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(sendPending()),
    );
    unawaited(sendPending());
  }

  static void _scheduleUpload({bool force = false}) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(seconds: 2),
      () => unawaited(sendPending(force: force)),
    );
  }

  static Future<void> _initialize() => _initializing ??= () async {
    // Import pre-upload-version errors exactly once, with a durable ID plan.
    if (await _outbox.readValue('legacy-imported') == null) {
      var plan = await _outbox.readValue('legacy-plan');
      if (plan == null) {
        final old = (await _store.read()).where(
          (e) => e.level == 'error' && e.eventId == null,
        );
        plan = jsonEncode(
          old.map((e) => {...e.toJson(), 'eventId': diagnosticUuid()}).toList(),
        );
        await _outbox.writeValue('legacy-plan', plan);
      }
      for (final json in jsonDecode(plan) as List) {
        await _enqueue(DiagnosticEntry.fromJson(json as Map<String, dynamic>));
      }
      await _outbox.writeValue('legacy-imported', '1');
    }
    await _readNativeReports();
    await _updateNativeContext();
  }();

  static Future<void> _updateNativeContext() async {
    if (!Platform.isAndroid) return;
    try {
      final info = await _info();
      await _native.invokeMethod<void>('setContext', {
        'userId': userId,
        'appVersion': info?.version ?? 'unknown',
        'buildNumber': int.tryParse(info?.buildNumber ?? '') ?? 0,
      });
    } catch (_) {
      /* Logging cannot break login if a native channel is absent. */
    }
  }

  static Future<void> _readNativeReports() async {
    if (!Platform.isAndroid) return;
    try {
      final reports =
          await _native.invokeListMethod<dynamic>('readReports') ?? [];
      for (final raw in reports) {
        final report = Map<String, dynamic>.from(raw as Map);
        final entry = DiagnosticEntry(
          eventId: report['eventId'] as String,
          time: DateTime.fromMillisecondsSinceEpoch(report['time'] as int),
          level: 'fatal',
          message: sanitize(report['operation'] as String),
          details: sanitize(report['details'] as String? ?? ''),
          userId: report['userId'] as String?,
          version: '${report['appVersion']}+${report['buildNumber']} (android)',
        );
        await _enqueue(entry, native: report);
        await _store.append(entry);
        await _native.invokeMethod<void>('acknowledgeReport', {
          'eventId': entry.eventId,
        });
      }
    } on MissingPluginException {
      // Non-Android tests and older installed native builds have no channel.
    } catch (error, stack) {
      // Native collection failure must not prevent ordinary Dart errors uploading.
      await AppLogger.error(
        'Preuzimanje Android izvjestaja o greskama',
        error,
        stack,
      );
    }
  }

  static Future<void> sendPending({bool force = false}) async {
    try {
      await _initialize();
      if (uploadConfigured) {
        await _uploader.flush(force: force);
      } else {
        await _uploader.refreshStatus();
      }
    } catch (_) {
      _initializing = null;
      writeFailure =
          'Dijagnostika nije spremna za slanje; lokalni zapisi se ne brišu.';
    }
  }

  static Future<List<DiagnosticEntry>> read() async {
    await _appVersion();
    return _store.read();
  }

  static String sanitize(String value) {
    value = _limit(value, 64000);
    var result = AppConfig.diagnosticsKey.isEmpty
        ? value
        : value.replaceAll(AppConfig.diagnosticsKey, '[skriveno]');
    result = result
        .replaceAll(
          RegExp(
            r'\b(Bearer|Basic)\s+[A-Za-z0-9_./+=-]+',
            caseSensitive: false,
          ),
          '[skrivena autorizacija]',
        )
        .replaceAll(
          RegExp(r'(?:(?:https?://)[^\s?]+)\?[^\s]+', caseSensitive: false),
          '[URL bez parametara]',
        );
    result = result.replaceAllMapped(
      RegExp(
        r'''["']?(password|passwd|pwd|lozinka|access_token|refresh_token|token|authorization|cookie|x-diagnostics-key|diagnostics_upload_key)["']?\s*[:=]\s*(?:"[^"]*"|'[^']*'|[^\s,;]+)''',
        caseSensitive: false,
      ),
      (match) => '${match[1]}: [skriveno]',
    );
    result = result.replaceAll(
      RegExp(r'://[^/\s]+:[^/@\s]+@'),
      '://[skriveno]@',
    );
    result = result.replaceAll(
      RegExp(r'\{[\s\S]*\}'),
      '[JSON payload izostavljen]',
    );
    return result.length > 8000 ? '${result.substring(0, 8000)}...' : result;
  }
}
