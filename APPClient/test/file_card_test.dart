import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opc_app/core/app_controller.dart';
import 'package:opc_app/data/models.dart';
import 'package:opc_app/features/api_file_card.dart';
import 'package:opc_app/features/api_forms.dart';

import 'api_ui_test.dart' show LiveUiRepository, host;

void main() {
  for (final dark in [false, true]) {
    for (final locale in ['zh', 'ja']) {
      testWidgets(
        'file cards fit small screens, $locale dark=$dark, without reading files',
        (tester) async {
          tester.view.physicalSize = const Size(320, 850);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final repo = LiveUiRepository();
          final app = AppController(repo);
          await app.setLocale(Locale(locale));
          final files = [
            for (final ext in [
              'docx',
              'xlsx',
              'pptx',
              'pdf',
              'jpg',
              'mp3',
              'mp4',
              'md',
              'zip',
            ])
              RemoteFile(
                id: ext,
                name: '项目说明_長い添付資料ファイル名.$ext',
                sizeBytes: 2400000,
                scanStatus: ext == 'pdf' ? 'pending' : 'clean',
              ),
          ];
          RemoteFile? removed;
          await tester.pumpWidget(
            host(
              app,
              Scaffold(
                body: MediaQuery(
                  data: const MediaQueryData(
                    textScaler: TextScaler.linear(1.5),
                  ),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: ApiFileList(
                        app: app,
                        files: files,
                        onRemove: (f) => removed = f,
                      ),
                    ),
                  ),
                ),
              ),
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byType(FileTypeCover), findsNWidgets(files.length));
          expect(repo.metadataReads, 0);
          await tester.tap(find.byIcon(Icons.close).first);
          await tester.pumpAndSettle();
          expect(removed?.id, 'docx');
          expect(repo.metadataReads, 0);
          await tester.pumpWidget(const SizedBox());
          app.dispose();
        },
      );
    }
  }

  testWidgets(
    'attachment opens the existing authorized preview only after tap',
    (tester) async {
      final repo = LiveUiRepository();
      final app = AppController(repo);
      await tester.pumpWidget(
        host(
          app,
          Scaffold(
            body: ApiFileList(
              app: app,
              files: const [
                RemoteFile(
                  id: 'file-1',
                  name: 'manual.pdf',
                  sizeBytes: 1024,
                  scanStatus: 'clean',
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.metadataReads, 0);
      await tester.tap(find.text('manual.pdf'));
      await tester.pumpAndSettle();
      expect(repo.metadataReads, greaterThan(0));
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  // 可选输出真实控件截图，供改版时人工复核；正常测试不写图片。
  if (Platform.environment['OPC_CAPTURE_FILE_CARDS'] == '1') {
    setUpAll(() async {
      for (final entry in {
        'OPCCapture': Platform.environment['OPC_CAPTURE_TEXT_FONT'],
        'MaterialIcons': Platform.environment['OPC_CAPTURE_ICON_FONT'],
      }.entries) {
        if (entry.value == null) continue;
        await (FontLoader(entry.key)..addFont(
              File(entry.value!).readAsBytes().then(ByteData.sublistView),
            ))
            .load();
      }
    });
    for (final dark in [false, true]) {
      testWidgets('capture file cards dark=$dark', (tester) async {
        tester.view.physicalSize = const Size(420, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final app = AppController(LiveUiRepository());
        await app.setLocale(const Locale('zh'));
        final boundary = GlobalKey();
        await tester.pumpWidget(
          host(
            app,
            Builder(
              builder: (context) => Theme(
                data: Theme.of(context).copyWith(
                  textTheme: Theme.of(
                    context,
                  ).textTheme.apply(fontFamily: 'OPCCapture'),
                ),
                child: RepaintBoundary(
                  key: boundary,
                  child: Scaffold(
                    body: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 12),
                          const Text(
                            '附件资料',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          ApiFileList(
                            app: app,
                            files: [
                              for (final name in [
                                'media-requirements.docx',
                                'media-data.xlsx',
                                'media-overview.pptx',
                                'media-acceptance.pdf',
                                'landscape.jpg',
                                'sample-tone.mp3',
                                'sample-road.mp4',
                                'media-sources.md',
                              ])
                                RemoteFile(
                                  id: name,
                                  name: name,
                                  sizeBytes: 37888,
                                  scanStatus: 'clean',
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            brightness: dark ? Brightness.dark : Brightness.light,
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            'test_artifacts/file-cards-${dark ? 'dark' : 'light'}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.pumpWidget(const SizedBox());
        app.dispose();
      });
    }
  }
}
