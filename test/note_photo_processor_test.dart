import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:vodovod_bd_flutter/src/core/note_photo_processor.dart';

void main() {
  late Directory directory;
  setUp(
    () async => directory = await Directory.systemTemp.createTemp('vob-photo-'),
  );
  tearDown(() async => directory.delete(recursive: true));

  final cornerColors = [
    img.ColorRgb8(240, 20, 20),
    img.ColorRgb8(20, 220, 20),
    img.ColorRgb8(20, 20, 240),
    img.ColorRgb8(240, 220, 20),
  ];

  Future<File> source(
    int width,
    int height, {
    int? orientation,
    bool markCorners = false,
  }) async {
    final photo = img.Image(width: width, height: height);
    img.fill(photo, color: img.ColorRgb8(120, 120, 120));
    if (markCorners) {
      const size = 40;
      final corners = [
        (0, 0),
        (width - size, 0),
        (width - size, height - size),
        (0, height - size),
      ];
      for (var i = 0; i < corners.length; i++) {
        final (x, y) = corners[i];
        img.fillRect(
          photo,
          x1: x,
          y1: y,
          x2: x + size - 1,
          y2: y + size - 1,
          color: cornerColors[i],
        );
      }
    }
    if (orientation != null) photo.exif.imageIfd.orientation = orientation;
    return File('${directory.path}/source.jpg')
      ..writeAsBytesSync(img.encodeJpg(photo));
  }

  Future<img.Image> prepare(File input) async {
    final path = await prepareNotePhoto(
      sourcePath: input.path,
      outputPath: '${directory.path}/prepared.jpg',
      label: 'Vodomjer: 18854323 | 22/10/2026 12:00',
    );
    expect(await File('$path.part').exists(), false);
    return img.decodeJpg(await File(path).readAsBytes())!;
  }

  test('landscape is bounded without changing the source', () async {
    final input = await source(2400, 800);
    final original = await input.readAsBytes();
    final photo = await prepare(input);
    expect((photo.width, photo.height), (1920, 640));
    expect(await input.readAsBytes(), original);
    // The formerly flat grey area must contain the meter/date watermark.
    var textPixels = 0;
    for (var y = 48; y < 90; y++) {
      for (var x = 48; x < 550; x++) {
        final red = photo.getPixel(x, y).r;
        if (red < 50 || red > 200) textPixels++;
      }
    }
    expect(textPixels, greaterThan(100));
  });

  test('portrait is limited by its height, not just its width', () async {
    final photo = await prepare(await source(800, 2400));
    expect((photo.width, photo.height), (640, 1920));
  });

  test(
    'camera EXIF rotation is applied before writing the watermark',
    () async {
      final photo = await prepare(await source(800, 400, orientation: 6));
      expect((photo.width, photo.height), (400, 800));
      expect(photo.exif.imageIfd.orientation, isNot(6));
    },
  );

  test('small photos are not upscaled', () async {
    final photo = await prepare(await source(320, 240));
    expect((photo.width, photo.height), (320, 240));
  });

  for (final (width, height, orientation, expectedCorners) in [
    (2400, 800, 1, [0, 1, 2, 3]),
    (800, 2400, 1, [0, 1, 2, 3]),
    (2400, 800, 6, [3, 0, 1, 2]),
  ]) {
    test('full frame retained: ${width}x$height, EXIF $orientation', () async {
      final input = await source(
        width,
        height,
        orientation: orientation,
        markCorners: true,
      );
      final photo = await prepare(input);
      final expectedRatio = orientation == 6 ? height / width : width / height;
      expect(photo.width / photo.height, closeTo(expectedRatio, 0.001));
      final corners = [
        (5, 5),
        (photo.width - 6, 5),
        (photo.width - 6, photo.height - 6),
        (5, photo.height - 6),
      ];
      for (var i = 0; i < corners.length; i++) {
        final (x, y) = corners[i];
        final pixel = photo.getPixel(x, y);
        final expected = cornerColors[expectedCorners[i]];
        // JPEG may change color values slightly, but must retain each corner.
        expect(pixel.r, closeTo(expected.r, 12));
        expect(pixel.g, closeTo(expected.g, 12));
        expect(pixel.b, closeTo(expected.b, 12));
      }
    });
  }

  test('invalid input cannot produce a partial or uploadable JPEG', () async {
    final input = File('${directory.path}/source.jpg');
    await input.writeAsBytes([1, 2, 3]);
    await expectLater(prepare(input), throwsA(isA<FormatException>()));
    expect(await File('${directory.path}/prepared.jpg').exists(), false);
    expect(await File('${directory.path}/prepared.jpg.part').exists(), false);
  });

  test(
    'main isolate continues handling events during a large photo conversion',
    () async {
      final input = await source(2400, 3200);
      var ticks = 0;
      final timer = Timer.periodic(
        const Duration(milliseconds: 10),
        (_) => ticks++,
      );
      try {
        await prepareNotePhoto(
          sourcePath: input.path,
          outputPath: '${directory.path}/large.jpg',
          label: 'Vodomjer: 18854323',
        );
        expect(ticks, greaterThan(3));
      } finally {
        timer.cancel();
      }
    },
  );
}
