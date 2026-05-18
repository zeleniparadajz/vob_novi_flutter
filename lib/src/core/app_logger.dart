import 'dart:io';

import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class AppLogger {
  static Future<void> log(String message) async {
    try {
      final file = await _logFile();
      final timestamp = DateFormat(
        'yyyy-MM-dd HH:mm:ss',
      ).format(DateTime.now());
      await file.writeAsString(
        '$timestamp: $message\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // Logging must never interrupt field work.
    }
  }

  static Future<File> _logFile() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final fileName = 'VOBLog_${packageInfo.version}.txt';
    final directory =
        await _downloadsDirectory() ?? await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return File('${directory.path}${Platform.pathSeparator}$fileName');
  }

  static Future<Directory?> _downloadsDirectory() async {
    try {
      final directory = await getDownloadsDirectory();
      if (directory != null) return directory;
    } catch (_) {
      // Fall through to Android public Downloads path.
    }

    if (Platform.isAndroid) {
      final directory = Directory('/storage/emulated/0/Download');
      if (await directory.exists()) return directory;
    }
    return null;
  }
}
