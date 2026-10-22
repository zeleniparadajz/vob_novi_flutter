import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:vodovod_bd_flutter/src/data/demo_repository.dart';
import 'package:vodovod_bd_flutter/src/models/vodovod_models.dart';
import 'package:vodovod_bd_flutter/src/screens/napomena_screen.dart';

class RecordingNotesRepository extends DemoVodovodRepository {
  final saved = Completer<NapomenaDraft>();
  int saveCount = 0;

  @override
  Future<void> sacuvajNapomenu(NapomenaDraft draft) async {
    saveCount++;
    saved.complete(draft);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const camera = MethodChannel('plugins.flutter.io/image_picker');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final item = OcitavanjeModel.fromJson({
    'id': 1,
    'idpot': '64808',
    'potrosac': 'Test potrosac',
    'vodomjer': '18854323',
  });
  tearDown(() => messenger.setMockMethodCallHandler(camera, null));

  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: NapomenaScreen(
          repository: DemoVodovodRepository(),
          ocitavanje: item,
        ),
      ),
    );
    await tester.ensureVisible(find.text('Kamera'));
  }

  testWidgets(
    'one picker at a time, bounded image, controls recover after cancellation',
    (tester) async {
      final response = Completer<String?>();
      var calls = 0;
      messenger.setMockMethodCallHandler(camera, (call) async {
        calls++;
        expect(call.arguments['maxWidth'], 1920);
        expect(call.arguments['maxHeight'], 1920);
        return response.future;
      });
      await show(tester);
      await tester.tap(find.text('Kamera'));
      await tester.pump();
      await tester.tap(find.text('Kamera'));
      await tester.tap(find.text('Galerija'));
      expect(calls, 1);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Potvrdi napomenu'),
            )
            .onPressed,
        isNull,
      );
      response.complete(null);
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Kamera'),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('picker failure releases controls and shows the error', (
    tester,
  ) async {
    messenger.setMockMethodCallHandler(camera, (_) async {
      throw PlatformException(code: 'camera_access_denied');
    });
    await show(tester);
    await tester.tap(find.text('Kamera'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Greška pri obradi slike'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'returning from camera to a disposed form causes no setState error',
    (tester) async {
      final response = Completer<String?>();
      messenger.setMockMethodCallHandler(camera, (_) => response.future);
      await show(tester);
      await tester.tap(find.text('Kamera'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      response.complete('/unused/photo.jpg');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('portrait preview displays the full frame without cropping', (
    tester,
  ) async {
    final directory = await tester.runAsync(
      () => Directory.systemTemp.createTemp('vob-preview-'),
    );
    addTearDown(() => directory!.delete(recursive: true));
    final input = File('${directory!.path}/portrait.jpg');
    await tester.runAsync(
      () =>
          input.writeAsBytes(img.encodeJpg(img.Image(width: 400, height: 800))),
    );
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
    addTearDown(() => messenger.setMockMethodCallHandler(paths, null));
    messenger.setMockMethodCallHandler(camera, (_) async => input.path);
    await show(tester);
    await tester.tap(find.text('Kamera'));
    await tester.pump();
    for (
      var attempt = 0;
      attempt < 1000 && find.byType(Image).evaluate().isEmpty;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byType(Image), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.fit, BoxFit.contain);
    expect(image.image, isA<ResizeImage>());
    final fitted = applyBoxFit(
      image.fit!,
      const Size(400, 800),
      tester.getSize(find.byType(Image)),
    );
    expect(fitted.source, const Size(400, 800));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => image.image.evict());
  });

  testWidgets('confirmed quick photo processes then saves exactly one note', (
    tester,
  ) async {
    final directory = await tester.runAsync(
      () => Directory.systemTemp.createTemp('vob-camera-'),
    );
    addTearDown(() => directory!.delete(recursive: true));
    final input = File('${directory!.path}/camera.jpg');
    await tester.runAsync(
      () =>
          input.writeAsBytes(img.encodeJpg(img.Image(width: 640, height: 480))),
    );
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
    addTearDown(() => messenger.setMockMethodCallHandler(paths, null));
    final cameraResult = Completer<String?>();
    messenger.setMockMethodCallHandler(camera, (_) => cameraResult.future);
    final repository = RecordingNotesRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => NapomenaScreen(
                    repository: repository,
                    ocitavanje: item,
                    quickMode: true,
                    autoOpenCamera: true,
                  ),
                ),
              ),
              child: const Text('Otvori kameru'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Otvori kameru'));
    await tester.pump();
    cameraResult.complete(input.path);
    // Alternate real IO/compute progress with the widget test's fake event loop.
    for (
      var attempt = 0;
      attempt < 1000 && !repository.saved.isCompleted;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(repository.saved.isCompleted, true);
    await tester.runAsync(() async {
      final note = await repository.saved.future;
      expect(note.vodomjer, item.vodomjer);
      expect(note.idpot, item.idpot);
      expect(await File(note.slikaPath).exists(), true);
      expect(
        img.decodeJpg(await File(note.slikaPath).readAsBytes()),
        isNotNull,
      );
    });
    await tester.pumpAndSettle();
    expect(repository.saveCount, 1);
    expect(find.text('Otvori kameru'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
