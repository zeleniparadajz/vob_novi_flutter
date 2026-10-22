import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

const notePhotoMaxDimension = 1920;

Future<String> prepareNotePhoto({
  required String sourcePath,
  required String outputPath,
  required String label,
}) => compute(_prepareNotePhoto, (
  sourcePath: sourcePath,
  outputPath: outputPath,
  label: label,
), debugLabel: 'prepareNotePhoto');

// Pass paths, not decoded images or widget state, across the isolate boundary.
Future<String> _prepareNotePhoto(
  ({String sourcePath, String outputPath, String label}) request,
) async {
  final bytes = await File(request.sourcePath).readAsBytes();
  if (bytes.length < 16) throw const FormatException('Slika nije validna.');
  var photo = img.decodeImage(bytes, frame: 0);
  if (photo == null) throw const FormatException('Slika nije validna.');

  if (photo.exif.imageIfd.hasOrientation &&
      photo.exif.imageIfd.orientation != 1) {
    photo = img.bakeOrientation(photo);
  }
  // Bound both portrait and landscape photos, even if a picker ignores its limit.
  if (photo.width > notePhotoMaxDimension ||
      photo.height > notePhotoMaxDimension) {
    photo = photo.width >= photo.height
        ? img.copyResize(photo, width: notePhotoMaxDimension)
        : img.copyResize(photo, height: notePhotoMaxDimension);
  }

  img.drawString(
    photo,
    request.label,
    font: img.arial24,
    x: 50,
    y: 50,
    color: img.ColorRgb8(0, 0, 0),
  );
  img.drawString(
    photo,
    request.label,
    font: img.arial24,
    x: 48,
    y: 48,
    color: img.ColorRgb8(255, 255, 255),
  );

  final output = File(request.outputPath);
  final partial = File('${request.outputPath}.part');
  try {
    await partial.writeAsBytes(img.encodeJpg(photo, quality: 90), flush: true);
    await partial.rename(output.path);
    return output.path;
  } finally {
    if (await partial.exists()) await partial.delete();
  }
}
