import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class UpdateCancelled implements Exception {}

class ApkUpdater {
  ApkUpdater({Future<Directory> Function()? directory})
    : _directory = directory ?? getTemporaryDirectory;

  static const channel = MethodChannel('com.vodovodbd/app_update');
  static Future<bool> canInstall() async =>
      await channel.invokeMethod<bool>('canInstall') ?? false;
  final Future<Directory> Function() _directory;
  HttpClient? _client;
  bool _cancelled = false;
  bool _downloading = false;
  static const _idleTimeout = Duration(seconds: 30);
  static const _maxBytes = 300 * 1024 * 1024;

  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }

  Future<void> _validate(File file, int versionCode) async {
    await channel.invokeMethod<void>('validateApk', {
      'path': file.path,
      'versionCode': versionCode,
    });
  }

  Future<File> download({
    required String url,
    required int versionCode,
    required void Function(int received, int? total) onProgress,
  }) async {
    if (_downloading) throw StateError('Preuzimanje je već u toku.');
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw const FormatException('Neispravan link za novu verziju.');
    }
    _downloading = true;
    _cancelled = false;
    File? partial;
    RandomAccessFile? output;
    try {
      final root = await _directory();
      final directory = Directory('${root.path}/updates');
      await directory.create(recursive: true);
      final apk = File('${directory.path}/update-$versionCode.apk');
      if (await apk.exists()) {
        try {
          await _validate(apk, versionCode);
          if (_cancelled) throw UpdateCancelled();
          return apk;
        } on PlatformException {
          await apk.delete();
        }
      }
      // Only this updater's cache is removed; local readings and photos are separate.
      await for (final file in directory.list()) {
        if (file is File &&
            RegExp(r'/update-\d+\.apk(?:\.part)?$').hasMatch(file.path)) {
          await file.delete();
        }
      }
      if (_cancelled) throw UpdateCancelled();
      partial = File('${apk.path}.part');
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15);
      _client = client;
      final request = await client.getUrl(uri).timeout(_idleTimeout);
      final response = await request.close().timeout(_idleTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Preuzimanje nije uspjelo (HTTP ${response.statusCode}).',
        );
      }
      final total = response.contentLength > 0 ? response.contentLength : null;
      if (total != null && total > _maxBytes) {
        throw const FormatException('APK je veći od dozvoljene veličine.');
      }
      output = await partial.open(mode: FileMode.write);
      var received = 0;
      final progressClock = Stopwatch()..start();
      onProgress(0, total);
      await for (final chunk in response.timeout(_idleTimeout)) {
        if (_cancelled) throw UpdateCancelled();
        received += chunk.length;
        if (received > _maxBytes) {
          throw const FormatException('APK je prevelik.');
        }
        await output.writeFrom(chunk);
        if (progressClock.elapsedMilliseconds >= 100) {
          onProgress(received, total);
          progressClock.reset();
        }
      }
      await output.flush();
      await output.close();
      output = null;
      if (_cancelled) throw UpdateCancelled();
      if (received == 0 || (total != null && received != total)) {
        throw const FormatException(
          'APK nije preuzet u cjelosti. Pokušajte ponovo.',
        );
      }
      // Check package, build and signing certificate before exposing an Install action.
      await _validate(partial, versionCode);
      if (_cancelled) throw UpdateCancelled();
      await partial.rename(apk.path);
      onProgress(received, total ?? received);
      return apk;
    } catch (_) {
      if (_cancelled) throw UpdateCancelled();
      rethrow;
    } finally {
      _client?.close(force: true);
      _client = null;
      _downloading = false;
      try {
        if (output != null) await output.close();
      } finally {
        if (partial != null && await partial.exists()) await partial.delete();
      }
    }
  }

  Future<String> install(File file, int versionCode) async =>
      await channel.invokeMethod<String>('installApk', {
        'path': file.path,
        'versionCode': versionCode,
      }) ??
      'installer_opened';
}
